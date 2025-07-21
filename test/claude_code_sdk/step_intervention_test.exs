defmodule ClaudeCodeSDK.StepInterventionTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{Step, StepIntervention}

  describe "new/4" do
    test "creates intervention with required fields" do
      intervention = StepIntervention.new(:guidance, "Be careful")

      assert intervention.type == :guidance
      assert intervention.content == "Be careful"
      assert intervention.status == :pending
      assert intervention.priority == :medium
      assert is_binary(intervention.id)
      assert %DateTime{} = intervention.created_at
    end

    test "creates intervention with custom options" do
      metadata = %{context: "file operations"}

      intervention =
        StepIntervention.new(
          :correction,
          "Fix the error",
          metadata,
          id: "custom-id",
          source: "safety_system",
          priority: :high
        )

      assert intervention.id == "custom-id"
      assert intervention.type == :correction
      assert intervention.content == "Fix the error"
      assert intervention.metadata == metadata
      assert intervention.source == "safety_system"
      assert intervention.priority == :high
    end
  end

  describe "apply/3" do
    test "applies guidance intervention with default handling" do
      step = create_test_step()
      intervention = StepIntervention.new(:guidance, "Be more careful")

      {:ok, updated_step} = StepIntervention.apply(step, intervention)

      assert updated_step.metadata.guidance == "Be more careful"
      assert length(updated_step.interventions) == 1

      applied_intervention = List.first(updated_step.interventions)
      assert applied_intervention.type == :guidance
      assert applied_intervention.content == "Be more careful"
    end

    test "applies correction intervention with default handling" do
      step = create_test_step()
      intervention = StepIntervention.new(:correction, "Fix syntax error")

      {:ok, updated_step} = StepIntervention.apply(step, intervention)

      assert updated_step.metadata.correction == "Fix syntax error"
      assert String.contains?(updated_step.description, "[CORRECTED: Fix syntax error]")
      assert length(updated_step.interventions) == 1
    end

    test "applies context intervention with default handling" do
      step = create_test_step()
      context_metadata = %{context: %{file_type: "elixir", safety_level: "high"}}
      intervention = StepIntervention.new(:context, "Additional context", context_metadata)

      {:ok, updated_step} = StepIntervention.apply(step, intervention)

      assert updated_step.metadata.file_type == "elixir"
      assert updated_step.metadata.safety_level == "high"
      assert length(updated_step.interventions) == 1
    end

    test "applies intervention with custom processor" do
      defmodule CustomProcessor do
        @behaviour StepIntervention.Processor

        def handle_guidance(step, intervention) do
          updated_metadata = Map.put(step.metadata, :custom_guidance, intervention.content)
          {:ok, %{step | metadata: updated_metadata}}
        end
      end

      step = create_test_step()
      intervention = StepIntervention.new(:guidance, "Custom guidance")

      {:ok, updated_step} = StepIntervention.apply(step, intervention, CustomProcessor)

      assert updated_step.metadata.custom_guidance == "Custom guidance"
      assert length(updated_step.interventions) == 1
    end

    test "handles intervention validation errors" do
      step = create_test_step()

      invalid_intervention = %StepIntervention{
        id: "test",
        type: :invalid_type,
        content: "test",
        metadata: %{},
        created_at: DateTime.utc_now(),
        status: :pending,
        priority: :medium
      }

      {:error, {:validation_failed, {:invalid_type, :invalid_type}}} =
        StepIntervention.apply(step, invalid_intervention)
    end

    test "handles processor errors gracefully" do
      defmodule ErrorProcessor do
        @behaviour StepIntervention.Processor

        def handle_guidance(_step, _intervention) do
          raise "Processor error"
        end
      end

      step = create_test_step()
      intervention = StepIntervention.new(:guidance, "Test guidance")

      {:error, {:application_exception, _}} =
        StepIntervention.apply(step, intervention, ErrorProcessor)
    end
  end

  describe "apply_multiple/3" do
    test "applies multiple interventions in priority order" do
      step = create_test_step()

      interventions = [
        StepIntervention.new(:guidance, "Low priority", %{}, priority: :low),
        StepIntervention.new(:correction, "High priority", %{}, priority: :high),
        StepIntervention.new(:context, "Medium priority", %{context: %{test_key: "test_value"}},
          priority: :medium
        )
      ]

      {:ok, updated_step} = StepIntervention.apply_multiple(step, interventions)

      # Should have all three interventions applied
      assert length(updated_step.interventions) == 3

      # High priority correction should be applied
      assert updated_step.metadata.correction == "High priority"

      # Context should be applied
      assert updated_step.metadata.test_key == "test_value"

      # Guidance should be applied
      assert updated_step.metadata.guidance == "Low priority"
    end

    test "handles partial application failures" do
      defmodule PartialErrorProcessor do
        @behaviour StepIntervention.Processor

        def handle_guidance(step, _intervention) do
          # This will succeed
          {:ok, step}
        end

        def handle_correction(_step, _intervention) do
          # This will fail
          {:error, :correction_failed}
        end
      end

      step = create_test_step()

      interventions = [
        StepIntervention.new(:guidance, "First intervention"),
        StepIntervention.new(:correction, "Second intervention")
      ]

      {:error, :correction_failed, _partial_step} =
        StepIntervention.apply_multiple(step, interventions, PartialErrorProcessor)
    end
  end

  describe "rollback/2" do
    test "rolls back applied intervention" do
      step = create_test_step()
      intervention = StepIntervention.new(:guidance, "Test guidance")

      {:ok, updated_step} = StepIntervention.apply(step, intervention)
      assert Map.has_key?(updated_step.metadata, :guidance)

      {:ok, rolled_back_step} = StepIntervention.rollback(updated_step, intervention.id)

      refute Map.has_key?(rolled_back_step.metadata, :guidance)
      assert length(rolled_back_step.interventions) == 0
    end

    test "handles rollback of non-existent intervention" do
      step = create_test_step()

      {:error, :intervention_not_found} =
        StepIntervention.rollback(step, "non-existent-id")
    end
  end

  describe "get_history/1" do
    test "returns intervention history sorted by application time" do
      step = create_test_step()

      intervention1 = StepIntervention.new(:guidance, "First")
      {:ok, step1} = StepIntervention.apply(step, intervention1)

      # Small delay to ensure different timestamps
      Process.sleep(1)

      intervention2 = StepIntervention.new(:correction, "Second")
      {:ok, step2} = StepIntervention.apply(step1, intervention2)

      history = StepIntervention.get_history(step2)

      assert length(history) == 2
      assert List.first(history).content == "First"
      assert List.last(history).content == "Second"
    end
  end

  describe "validate_intervention/1" do
    test "validates correct intervention" do
      intervention = StepIntervention.new(:guidance, "Valid intervention")
      assert :ok = StepIntervention.validate_intervention(intervention)
    end

    test "rejects invalid intervention type" do
      intervention = %StepIntervention{
        id: "test",
        type: :invalid,
        content: "test",
        metadata: %{},
        created_at: DateTime.utc_now(),
        status: :pending,
        priority: :medium
      }

      {:error, {:invalid_type, :invalid}} =
        StepIntervention.validate_intervention(intervention)
    end

    test "rejects empty content" do
      intervention = %StepIntervention{
        id: "test",
        type: :guidance,
        content: "",
        metadata: %{},
        created_at: DateTime.utc_now(),
        status: :pending,
        priority: :medium
      }

      {:error, {:invalid_content, ""}} =
        StepIntervention.validate_intervention(intervention)
    end

    test "rejects invalid priority" do
      intervention = %StepIntervention{
        id: "test",
        type: :guidance,
        content: "test",
        metadata: %{},
        created_at: DateTime.utc_now(),
        status: :pending,
        priority: :invalid
      }

      {:error, {:invalid_priority, :invalid}} =
        StepIntervention.validate_intervention(intervention)
    end
  end

  describe "Processor.Default" do
    test "handles guidance with history tracking" do
      step = create_test_step()
      intervention = StepIntervention.new(:guidance, "Test guidance")

      {:ok, updated_step} = StepIntervention.Processor.Default.handle_guidance(step, intervention)

      assert updated_step.metadata.guidance_history == ["Test guidance"]
    end

    test "handles correction with history tracking" do
      step = create_test_step()
      intervention = StepIntervention.new(:correction, "Fix error")

      {:ok, updated_step} =
        StepIntervention.Processor.Default.handle_correction(step, intervention)

      assert String.contains?(updated_step.description, "[CORRECTED: Fix error]")
      assert updated_step.metadata.correction_history == ["Fix error"]
    end

    test "handles context with history tracking" do
      step = create_test_step()
      context_metadata = %{context: %{file_type: "elixir"}}
      intervention = StepIntervention.new(:context, "Add context", context_metadata)

      {:ok, updated_step} = StepIntervention.Processor.Default.handle_context(step, intervention)

      assert updated_step.metadata.file_type == "elixir"
      assert updated_step.metadata.context_history == ["Add context"]
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
