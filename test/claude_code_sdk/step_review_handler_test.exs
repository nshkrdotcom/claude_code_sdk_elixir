defmodule ClaudeCodeSDK.StepReviewHandlerTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{Step, StepReviewHandler}

  describe "async_review/4" do
    test "completes review within timeout" do
      step = create_test_step()

      {:ok, _task_pid} =
        StepReviewHandler.async_review(
          StepReviewHandler.AlwaysApprove,
          step,
          1000,
          self()
        )

      assert_receive {:review_result, step_id, :approved}, 500
      assert step_id == step.id
    end

    test "handles review timeout" do
      defmodule SlowReviewer do
        @behaviour StepReviewHandler

        def review_step(_step) do
          Process.sleep(200)
          :approved
        end

        def handle_review_timeout(_step, _timeout) do
          :rejected
        end
      end

      step = create_test_step()

      {:ok, _task_pid} =
        StepReviewHandler.async_review(
          SlowReviewer,
          step,
          # Short timeout
          50,
          self()
        )

      assert_receive {:review_result, step_id, :rejected}, 200
      assert step_id == step.id
    end

    test "handles review exceptions" do
      defmodule ErrorReviewer do
        @behaviour StepReviewHandler

        def review_step(_step) do
          raise "Review failed"
        end
      end

      step = create_test_step()

      {:ok, _task_pid} =
        StepReviewHandler.async_review(
          ErrorReviewer,
          step,
          1000,
          self()
        )

      # Exceptions are caught and returned as {:error, {:review_exception, error}}
      assert_receive {:review_result, step_id, {:error, {:review_exception, _}}}, 500
      assert step_id == step.id
    end
  end

  describe "validate_review_decision/1" do
    test "validates approved decision" do
      assert :approved = StepReviewHandler.validate_review_decision(:approved)
    end

    test "validates rejected decision" do
      assert :rejected = StepReviewHandler.validate_review_decision(:rejected)
    end

    test "validates approved with changes" do
      changes = %{description: "Updated"}
      decision = {:approved_with_changes, changes}

      assert {:approved_with_changes, ^changes} =
               StepReviewHandler.validate_review_decision(decision)
    end

    test "validates error decision" do
      error = {:error, :some_reason}
      assert {:error, :some_reason} = StepReviewHandler.validate_review_decision(error)
    end

    test "rejects invalid decisions" do
      assert {:error, {:invalid_decision, :invalid}} =
               StepReviewHandler.validate_review_decision(:invalid)
    end

    test "rejects malformed approved_with_changes" do
      assert {:error, {:invalid_decision, {:approved_with_changes, "not a map"}}} =
               StepReviewHandler.validate_review_decision({:approved_with_changes, "not a map"})
    end
  end

  describe "apply_changes/2" do
    test "applies description changes" do
      step = create_test_step(description: "Original")
      changes = %{description: "Updated description"}

      updated_step = StepReviewHandler.apply_changes(step, changes)
      assert updated_step.description == "Updated description"
    end

    test "applies metadata changes" do
      step = create_test_step()
      changes = %{metadata: %{safety_reviewed: true, priority: :high}}

      updated_step = StepReviewHandler.apply_changes(step, changes)
      assert updated_step.metadata.safety_reviewed == true
      assert updated_step.metadata.priority == :high
    end

    test "applies intervention changes" do
      step = create_test_step()

      interventions = [
        %{type: :guidance, content: "Be careful", applied_at: DateTime.utc_now()}
      ]

      changes = %{interventions: interventions}

      updated_step = StepReviewHandler.apply_changes(step, changes)
      assert length(updated_step.interventions) == 1

      intervention = List.first(updated_step.interventions)
      assert intervention.type == :guidance
      assert intervention.content == "Be careful"
    end

    test "ignores unknown changes" do
      step = create_test_step(description: "Original")
      changes = %{unknown_field: "value", description: "Updated"}

      updated_step = StepReviewHandler.apply_changes(step, changes)
      assert updated_step.description == "Updated"
      # Unknown field should be ignored
    end

    test "applies multiple changes" do
      step = create_test_step(description: "Original")

      changes = %{
        description: "Updated",
        metadata: %{reviewed: true},
        interventions: [%{type: :guidance, content: "Test"}]
      }

      updated_step = StepReviewHandler.apply_changes(step, changes)
      assert updated_step.description == "Updated"
      assert updated_step.metadata.reviewed == true
      assert length(updated_step.interventions) == 1
    end
  end

  describe "AlwaysApprove" do
    test "always approves steps" do
      step = create_test_step()
      assert :approved = StepReviewHandler.AlwaysApprove.review_step(step)
    end
  end

  describe "AlwaysReject" do
    test "always rejects steps" do
      step = create_test_step()
      assert :rejected = StepReviewHandler.AlwaysReject.review_step(step)
    end
  end

  describe "SafetyFirst" do
    test "approves safe step types" do
      safe_types = [:exploration, :analysis, :communication]

      for step_type <- safe_types do
        step = create_test_step(type: step_type)
        assert :approved = StepReviewHandler.SafetyFirst.review_step(step)
      end
    end

    test "rejects system commands" do
      step = create_test_step(type: :system_command)
      assert :rejected = StepReviewHandler.SafetyFirst.review_step(step)
    end

    test "rejects dangerous tools" do
      dangerous_tools = ["deleteFile", "executePwsh", "executeCommand"]

      for tool <- dangerous_tools do
        step = create_test_step(tools_used: [tool])
        assert :rejected = StepReviewHandler.SafetyFirst.review_step(step)
      end
    end

    test "approves safe file operations" do
      step = create_test_step(type: :file_operation, tools_used: ["readFile", "listDirectory"])
      assert :approved = StepReviewHandler.SafetyFirst.review_step(step)
    end

    test "rejects file operations with dangerous tools" do
      step = create_test_step(type: :file_operation, tools_used: ["readFile", "deleteFile"])
      assert :rejected = StepReviewHandler.SafetyFirst.review_step(step)
    end

    test "approves code modifications with changes" do
      step = create_test_step(type: :code_modification)

      assert {:approved_with_changes, changes} =
               StepReviewHandler.SafetyFirst.review_step(step)

      assert changes.metadata.safety_reviewed == true
      assert is_list(changes.interventions)
      assert length(changes.interventions) == 1

      intervention = List.first(changes.interventions)
      assert intervention.type == :guidance
    end

    test "rejects unknown step types" do
      step = create_test_step(type: :unknown_type)
      assert :rejected = StepReviewHandler.SafetyFirst.review_step(step)
    end

    test "handles review timeout conservatively" do
      step = create_test_step()
      assert :rejected = StepReviewHandler.SafetyFirst.handle_review_timeout(step, 5000)
    end
  end

  describe "InteractiveReviewer" do
    # Note: InteractiveReviewer is difficult to test automatically since it requires user input
    # In a real scenario, you might mock IO.gets/1 for testing

    test "handles review timeout" do
      step = create_test_step()
      assert :rejected = StepReviewHandler.InteractiveReviewer.handle_review_timeout(step, 5000)
    end
  end

  describe "custom review handler" do
    defmodule CustomReviewer do
      @behaviour StepReviewHandler

      def review_step(step) do
        case step.type do
          :file_operation ->
            if "readFile" in step.tools_used do
              :approved
            else
              {:approved_with_changes,
               %{
                 metadata: %{custom_review: true}
               }}
            end

          :code_modification ->
            {:approved_with_changes,
             %{
               description: "Reviewed: #{step.description}",
               interventions: [
                 %{
                   type: :guidance,
                   content: "Code review completed"
                 }
               ]
             }}

          _ ->
            :rejected
        end
      end

      def handle_review_timeout(_step, _timeout) do
        {:error, :review_timeout}
      end
    end

    test "handles file operations" do
      step = create_test_step(type: :file_operation, tools_used: ["readFile"])
      assert :approved = CustomReviewer.review_step(step)
    end

    test "handles file operations with changes" do
      step = create_test_step(type: :file_operation, tools_used: ["writeFile"])

      assert {:approved_with_changes, changes} = CustomReviewer.review_step(step)
      assert changes.metadata.custom_review == true
    end

    test "handles code modifications with changes" do
      step = create_test_step(type: :code_modification, description: "Fix bug")

      assert {:approved_with_changes, changes} = CustomReviewer.review_step(step)
      assert changes.description == "Reviewed: Fix bug"
      assert is_list(changes.interventions)
    end

    test "rejects unknown types" do
      step = create_test_step(type: :unknown)
      assert :rejected = CustomReviewer.review_step(step)
    end

    test "handles timeout with error" do
      step = create_test_step()
      assert {:error, :review_timeout} = CustomReviewer.handle_review_timeout(step, 1000)
    end
  end

  # Helper functions
  defp create_test_step(opts \\ []) do
    Step.new(
      [
        type: Keyword.get(opts, :type, :file_operation),
        description: Keyword.get(opts, :description, "Test step"),
        tools_used: Keyword.get(opts, :tools_used, ["readFile"])
      ] ++ opts
    )
  end
end
