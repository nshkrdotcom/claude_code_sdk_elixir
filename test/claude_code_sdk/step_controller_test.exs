defmodule ClaudeCodeSDK.StepControllerTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{Step, StepController, StepReviewHandler}

  describe "start_link/2" do
    test "starts controller with default options" do
      step_stream = [create_test_step()]

      assert {:ok, pid} = StepController.start_link(step_stream)
      assert Process.alive?(pid)

      StepController.stop(pid)
    end

    test "starts controller with custom options" do
      step_stream = [create_test_step()]

      assert {:ok, pid} =
               StepController.start_link(step_stream,
                 control_mode: :manual,
                 control_timeout_ms: 10_000
               )

      status = StepController.get_status(pid)
      assert status.control_mode == :manual

      StepController.stop(pid)
    end

    test "starts controller with name registration" do
      step_stream = [create_test_step()]

      assert {:ok, pid} = StepController.start_link(step_stream, name: :test_controller)
      assert Process.whereis(:test_controller) == pid

      StepController.stop(:test_controller)
    end
  end

  describe "automatic mode" do
    test "processes steps automatically without pausing" do
      steps = [
        create_test_step(type: :file_operation),
        create_test_step(type: :code_modification)
      ]

      {:ok, controller} = StepController.start_link(steps, control_mode: :automatic)

      # First step should complete immediately
      assert {:ok, step1} = StepController.next_step(controller)
      assert step1.status == :completed
      assert step1.type == :file_operation

      # Second step should also complete immediately
      assert {:ok, step2} = StepController.next_step(controller)
      assert step2.status == :completed
      assert step2.type == :code_modification

      # No more steps
      assert :completed = StepController.next_step(controller)

      StepController.stop(controller)
    end

    test "pauses between steps when configured" do
      steps = [create_test_step(), create_test_step()]

      {:ok, controller} =
        StepController.start_link(steps,
          control_mode: :automatic,
          pause_between_steps: true
        )

      # First step should pause
      assert {:paused, step1} = StepController.next_step(controller)
      assert step1.status == :in_progress

      # Resume to continue
      assert :ok = StepController.resume(controller, :continue)

      # Should get the completed step
      assert {:ok, completed_step} = StepController.next_step(controller)
      assert completed_step.status == :completed

      StepController.stop(controller)
    end
  end

  describe "manual mode" do
    test "pauses after each step for user decision" do
      steps = [create_test_step(), create_test_step()]

      {:ok, controller} = StepController.start_link(steps, control_mode: :manual)

      # First step should pause
      assert {:paused, step1} = StepController.next_step(controller)
      assert step1.status == :in_progress

      # Resume to continue
      assert :ok = StepController.resume(controller, :continue)

      # Should get completed step and move to next
      assert {:ok, completed_step} = StepController.next_step(controller)
      assert completed_step.status == :completed

      StepController.stop(controller)
    end

    test "allows skipping steps" do
      steps = [create_test_step(), create_test_step()]

      {:ok, controller} = StepController.start_link(steps, control_mode: :manual)

      # First step should pause
      assert {:paused, _step1} = StepController.next_step(controller)

      # Skip the step
      assert :ok = StepController.resume(controller, :skip)

      # Should get aborted step
      assert {:ok, skipped_step} = StepController.next_step(controller)
      assert skipped_step.status == :aborted

      StepController.stop(controller)
    end

    test "allows aborting execution" do
      steps = [create_test_step(), create_test_step()]

      {:ok, controller} = StepController.start_link(steps, control_mode: :manual)

      # First step should pause
      assert {:paused, _step} = StepController.next_step(controller)

      # Abort execution
      assert :ok = StepController.resume(controller, :abort)

      # Should get error
      assert {:error, :aborted} = StepController.next_step(controller)

      StepController.stop(controller)
    end
  end

  describe "review_required mode" do
    test "waits for review approval without review handler" do
      steps = [create_test_step()]

      {:ok, controller} = StepController.start_link(steps, control_mode: :review_required)

      # Should pause since no review handler configured
      assert {:paused, step} = StepController.next_step(controller)
      assert step.status == :in_progress

      StepController.stop(controller)
    end

    test "processes review with approval" do
      steps = [create_test_step()]

      {:ok, controller} =
        StepController.start_link(steps,
          control_mode: :review_required,
          review_handler: StepReviewHandler.AlwaysApprove
        )

      # Should wait for review
      assert {:waiting_review, step} = StepController.next_step(controller)
      assert step.review_status == :pending

      # Simulate review approval
      send(controller, {:review_result, step.id, :approved})

      # Should continue after approval
      # Allow message processing
      Process.sleep(10)
      assert {:ok, approved_step} = StepController.next_step(controller)
      assert approved_step.review_status == :approved

      StepController.stop(controller)
    end

    test "processes review with rejection" do
      steps = [create_test_step()]

      {:ok, controller} =
        StepController.start_link(steps,
          control_mode: :review_required,
          review_handler: StepReviewHandler.AlwaysReject
        )

      # Should wait for review
      assert {:waiting_review, step} = StepController.next_step(controller)

      # Simulate review rejection
      send(controller, {:review_result, step.id, :rejected})

      # Should skip after rejection
      # Allow message processing
      Process.sleep(10)
      assert {:ok, rejected_step} = StepController.next_step(controller)
      assert rejected_step.review_status == :rejected
      assert rejected_step.status == :aborted

      StepController.stop(controller)
    end
  end

  describe "interventions" do
    test "applies intervention and continues" do
      steps = [create_test_step()]

      {:ok, controller} = StepController.start_link(steps, control_mode: :manual)

      # First step should pause
      assert {:paused, _step} = StepController.next_step(controller)

      # Apply intervention
      intervention = %{
        type: :guidance,
        content: "Be careful with this operation",
        metadata: %{}
      }

      assert :ok = StepController.resume(controller, {:intervene, intervention})

      # Should get step with intervention applied
      assert {:ok, updated_step} = StepController.next_step(controller)
      assert length(updated_step.interventions) == 1

      intervention_data = List.first(updated_step.interventions)
      assert intervention_data.type == :guidance
      assert intervention_data.content == "Be careful with this operation"

      StepController.stop(controller)
    end

    test "handles intervention with custom handler" do
      intervention_handler = fn intervention, step ->
        updated_metadata = Map.put(step.metadata, :custom_intervention, intervention.content)
        %{step | metadata: updated_metadata}
      end

      steps = [create_test_step()]

      {:ok, controller} =
        StepController.start_link(steps,
          control_mode: :manual,
          intervention_handler: intervention_handler
        )

      # First step should pause
      assert {:paused, _step} = StepController.next_step(controller)

      # Apply intervention
      intervention = %{
        type: :guidance,
        content: "Custom intervention",
        metadata: %{}
      }

      assert :ok = StepController.resume(controller, {:intervene, intervention})

      # Should get step with custom intervention handling
      assert {:ok, updated_step} = StepController.next_step(controller)
      assert updated_step.metadata.custom_intervention == "Custom intervention"

      StepController.stop(controller)
    end
  end

  describe "timeout handling" do
    test "handles control timeout in manual mode" do
      steps = [create_test_step()]

      {:ok, controller} =
        StepController.start_link(steps,
          control_mode: :manual,
          control_timeout_ms: 50
        )

      # First step should pause
      assert {:paused, _step} = StepController.next_step(controller)

      # Wait for timeout
      Process.sleep(100)

      # Should still be paused after timeout
      assert {:paused, _step} = StepController.next_step(controller)

      StepController.stop(controller)
    end

    test "handles review timeout" do
      # Create a slow review handler that takes longer than timeout
      defmodule SlowReviewer do
        @behaviour StepReviewHandler

        def review_step(_step) do
          # Sleep longer than timeout
          Process.sleep(200)
          :approved
        end
      end

      steps = [create_test_step()]

      {:ok, controller} =
        StepController.start_link(steps,
          control_mode: :review_required,
          review_handler: SlowReviewer,
          control_timeout_ms: 50
        )

      # Should wait for review
      assert {:waiting_review, _step} = StepController.next_step(controller)

      # Wait for timeout (don't send review result)
      Process.sleep(100)

      # Should default to rejection on timeout
      assert {:ok, timed_out_step} = StepController.next_step(controller)
      assert timed_out_step.review_status == :rejected

      StepController.stop(controller)
    end
  end

  describe "error handling" do
    test "handles invalid control decisions" do
      steps = [create_test_step()]

      {:ok, controller} = StepController.start_link(steps, control_mode: :manual)

      # First step should pause
      assert {:paused, _step} = StepController.next_step(controller)

      # Try invalid decision
      assert {:error, {:invalid_decision, :invalid}} =
               StepController.resume(controller, :invalid)

      StepController.stop(controller)
    end

    test "handles review handler errors" do
      defmodule ErrorReviewer do
        @behaviour StepReviewHandler

        def review_step(_step) do
          raise "Review error"
        end
      end

      steps = [create_test_step()]

      {:ok, controller} =
        StepController.start_link(steps,
          control_mode: :review_required,
          review_handler: ErrorReviewer
        )

      # Should wait for review
      assert {:waiting_review, _step} = StepController.next_step(controller)

      # Wait for error handling
      Process.sleep(50)

      # Should handle error gracefully (default to pause)
      assert {:paused, _step} = StepController.next_step(controller)

      StepController.stop(controller)
    end
  end

  describe "status and monitoring" do
    test "provides accurate status information" do
      steps = [create_test_step(), create_test_step()]

      {:ok, controller} = StepController.start_link(steps, control_mode: :manual)

      status = StepController.get_status(controller)

      assert status.control_mode == :manual
      assert status.control_state == :running
      assert status.stats.steps_processed == 0
      assert status.stats.steps_paused == 0
      assert is_integer(status.uptime_ms)

      # Process a step
      assert {:paused, _step} = StepController.next_step(controller)

      updated_status = StepController.get_status(controller)
      assert updated_status.stats.steps_processed == 1
      assert updated_status.stats.steps_paused == 1
      assert updated_status.control_state == :waiting_decision

      StepController.stop(controller)
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
