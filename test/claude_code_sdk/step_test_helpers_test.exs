defmodule ClaudeCodeSDK.StepTestHelpersTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{Step, StepTestHelpers, StepConfig}

  describe "StepTestHelpers.create_test_step/2" do
    test "creates a test step with default values" do
      step = StepTestHelpers.create_test_step(:file_operation)

      assert step.type == :file_operation
      assert step.status == :completed
      assert length(step.messages) == 3
      assert "readFile" in step.tools_used
      assert step.description == "Performing file operations"
    end

    test "creates a test step with custom options" do
      step =
        StepTestHelpers.create_test_step(
          :code_modification,
          tools_used: ["strReplace"],
          status: :in_progress,
          description: "Custom description"
        )

      assert step.type == :code_modification
      assert step.status == :in_progress
      assert step.tools_used == ["strReplace"]
      assert step.description == "Custom description"
    end
  end

  describe "StepTestHelpers.create_test_messages/2" do
    test "creates test messages for step type" do
      messages = StepTestHelpers.create_test_messages(:file_operation)

      assert length(messages) == 3

      Enum.each(messages, fn message ->
        assert message.type == :assistant
        assert is_map(message.data)
        assert is_binary(message.data.message["content"])
      end)
    end

    test "creates specified number of messages" do
      messages = StepTestHelpers.create_test_messages(:analysis, 5)

      assert length(messages) == 5
    end
  end

  describe "StepTestHelpers.create_mock_step_stream/1" do
    test "creates stream from scenarios" do
      scenarios = [
        {:file_operation, 2},
        {:code_modification, 1, status: :in_progress}
      ]

      stream = StepTestHelpers.create_mock_step_stream(scenarios)
      steps = Enum.to_list(stream)

      assert length(steps) == 3

      # First two should be file operations
      assert Enum.at(steps, 0).type == :file_operation
      assert Enum.at(steps, 1).type == :file_operation

      # Third should be code modification with custom status
      code_mod_step = Enum.at(steps, 2)
      assert code_mod_step.type == :code_modification
      assert code_mod_step.status == :in_progress
    end

    test "handles step instances in scenarios" do
      custom_step = StepTestHelpers.create_test_step(:analysis, description: "Custom step")
      scenarios = [custom_step, {:file_operation, 1}]

      stream = StepTestHelpers.create_mock_step_stream(scenarios)
      steps = Enum.to_list(stream)

      assert length(steps) == 2
      assert Enum.at(steps, 0) == custom_step
      assert Enum.at(steps, 1).type == :file_operation
    end
  end

  describe "StepTestHelpers.create_test_config/1" do
    test "creates test config with default values" do
      config = StepTestHelpers.create_test_config()

      assert %StepConfig{} = config
      assert config.step_grouping.enabled == false
    end

    test "creates test config with custom options" do
      config =
        StepTestHelpers.create_test_config(
          step_grouping: %{enabled: true},
          step_control: %{mode: :manual}
        )

      assert config.step_grouping.enabled == true
      assert config.step_control.mode == :manual
    end
  end

  describe "StepTestHelpers.create_test_patterns/1" do
    test "creates test patterns for default types" do
      patterns = StepTestHelpers.create_test_patterns()

      assert is_list(patterns)
      assert length(patterns) == 3

      pattern_ids = Enum.map(patterns, & &1.id)
      assert :file_operation in pattern_ids
      assert :code_modification in pattern_ids
      assert :analysis in pattern_ids
    end

    test "creates test patterns for specified types" do
      patterns = StepTestHelpers.create_test_patterns([:file_operation])

      assert length(patterns) == 1
      assert hd(patterns).id == :file_operation
    end
  end

  describe "assertion helpers" do
    test "assert_step_type/2 passes for correct type" do
      step = StepTestHelpers.create_test_step(:file_operation)

      assert :ok = StepTestHelpers.assert_step_type(step, :file_operation)
    end

    test "assert_step_type/2 raises for incorrect type" do
      step = StepTestHelpers.create_test_step(:file_operation)

      assert_raise RuntimeError, ~r/Expected step type/, fn ->
        StepTestHelpers.assert_step_type(step, :code_modification)
      end
    end

    test "assert_step_completed/1 passes for completed step" do
      step = StepTestHelpers.create_test_step(:file_operation, status: :completed)

      assert :ok = StepTestHelpers.assert_step_completed(step)
    end

    test "assert_step_completed/1 raises for incomplete step" do
      step = StepTestHelpers.create_test_step(:file_operation, status: :in_progress)

      assert_raise RuntimeError, ~r/Expected step to be completed/, fn ->
        StepTestHelpers.assert_step_completed(step)
      end
    end

    test "assert_step_tools/2 passes for correct tools" do
      step =
        StepTestHelpers.create_test_step(:file_operation, tools_used: ["readFile", "fsWrite"])

      assert :ok = StepTestHelpers.assert_step_tools(step, ["readFile"])
    end

    test "assert_step_tools/2 raises for missing tools" do
      step = StepTestHelpers.create_test_step(:file_operation, tools_used: ["readFile"])

      assert_raise RuntimeError, ~r/missing:/, fn ->
        StepTestHelpers.assert_step_tools(step, ["readFile", "fsWrite"])
      end
    end

    test "assert_step_message_count/2 passes for correct count" do
      step = StepTestHelpers.create_test_step(:file_operation)

      assert :ok = StepTestHelpers.assert_step_message_count(step, 3)
    end

    test "assert_step_message_count/2 raises for incorrect count" do
      step = StepTestHelpers.create_test_step(:file_operation)

      assert_raise RuntimeError, ~r/Expected step to have/, fn ->
        StepTestHelpers.assert_step_message_count(step, 5)
      end
    end

    test "assert_valid_step/1 passes for valid step" do
      step = StepTestHelpers.create_test_step(:file_operation)

      assert :ok = StepTestHelpers.assert_valid_step(step)
    end

    test "assert_valid_step/1 raises for invalid step" do
      invalid_step = %Step{
        # Invalid - should not be nil
        id: nil,
        type: :file_operation,
        description: "Test",
        messages: [],
        tools_used: [],
        status: :completed,
        metadata: %{},
        interventions: []
      }

      assert_raise RuntimeError, ~r/Step must have a non-empty ID/, fn ->
        StepTestHelpers.assert_valid_step(invalid_step)
      end
    end
  end
end
