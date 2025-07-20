defmodule ClaudeCodeSDK.StepPatternTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.StepPattern

  describe "StepPattern.new/1" do
    test "creates a pattern with required fields" do
      pattern =
        StepPattern.new(
          id: :test_pattern,
          name: "Test Pattern",
          triggers: [%{type: :tool_usage, tools: ["readFile"]}]
        )

      assert pattern.id == :test_pattern
      assert pattern.name == "Test Pattern"
      assert pattern.description == ""
      assert length(pattern.triggers) == 1
      assert pattern.validators == []
      assert pattern.priority == 50
      assert pattern.confidence == 0.5
    end

    test "creates a pattern with all options" do
      triggers = [%{type: :tool_usage, tools: ["readFile"]}]
      validators = [%{type: :tool_sequence, min_tools: 1}]

      pattern =
        StepPattern.new(
          id: :full_pattern,
          name: "Full Pattern",
          description: "A complete pattern",
          triggers: triggers,
          validators: validators,
          priority: 80,
          confidence: 0.9
        )

      assert pattern.id == :full_pattern
      assert pattern.name == "Full Pattern"
      assert pattern.description == "A complete pattern"
      assert pattern.triggers == triggers
      assert pattern.validators == validators
      assert pattern.priority == 80
      assert pattern.confidence == 0.9
    end

    test "raises error for missing required fields" do
      assert_raise ArgumentError, ~r/Pattern :id is required/, fn ->
        StepPattern.new(name: "Test", triggers: [])
      end

      assert_raise ArgumentError, ~r/Pattern :name is required/, fn ->
        StepPattern.new(id: :test, triggers: [])
      end

      assert_raise ArgumentError, ~r/Pattern :triggers is required/, fn ->
        StepPattern.new(id: :test, name: "Test")
      end
    end
  end

  describe "trigger creation helpers" do
    test "content_trigger/2 creates content trigger" do
      trigger = StepPattern.content_trigger(~r/implement/i)

      assert trigger.type == :message_content
      assert trigger.regex == ~r/implement/i
      assert trigger.options == %{}
    end

    test "tool_trigger/2 creates tool trigger" do
      trigger = StepPattern.tool_trigger(["readFile", "fsWrite"])

      assert trigger.type == :tool_usage
      assert trigger.tools == ["readFile", "fsWrite"]
      assert trigger.options == %{}
    end

    test "sequence_trigger/2 creates sequence trigger" do
      trigger = StepPattern.sequence_trigger([:assistant, :user])

      assert trigger.type == :message_sequence
      assert trigger.sequence == [:assistant, :user]
      assert trigger.options == %{}
    end

    test "custom_trigger/2 creates custom trigger" do
      func = fn _context -> true end
      trigger = StepPattern.custom_trigger(func)

      assert trigger.type == :custom_function
      assert trigger.function == func
      assert trigger.options == %{}
    end
  end

  describe "validator creation helpers" do
    test "content_validator/2 creates content validator" do
      validator = StepPattern.content_validator(~r/\.ex$/)

      assert validator.type == :content_regex
      assert validator.regex == ~r/\.ex$/
      assert validator.options == %{}
    end

    test "tool_validator/1 creates tool validator" do
      validator = StepPattern.tool_validator(min_tools: 1, max_tools: 5)

      assert validator.type == :tool_sequence
      assert validator.min_tools == 1
      assert validator.max_tools == 5
      assert validator.options == %{}
    end

    test "message_validator/1 creates message validator" do
      validator = StepPattern.message_validator(min_messages: 2)

      assert validator.type == :message_count
      assert validator.min_messages == 2
      assert validator.options == %{}
    end

    test "custom_validator/2 creates custom validator" do
      func = fn _context -> true end
      validator = StepPattern.custom_validator(func)

      assert validator.type == :custom_function
      assert validator.function == func
      assert validator.options == %{}
    end
  end

  describe "StepPattern.default_patterns/0" do
    test "returns list of default patterns" do
      patterns = StepPattern.default_patterns()

      assert is_list(patterns)
      assert length(patterns) > 0

      # Check that all patterns are valid
      Enum.each(patterns, fn pattern ->
        assert %StepPattern{} = pattern
        assert is_atom(pattern.id)
        assert is_binary(pattern.name)
        assert is_list(pattern.triggers)
        assert is_list(pattern.validators)
      end)
    end

    test "includes expected pattern types" do
      patterns = StepPattern.default_patterns()
      pattern_ids = Enum.map(patterns, & &1.id)

      assert :file_operation in pattern_ids
      assert :code_modification in pattern_ids
      assert :system_command in pattern_ids
      assert :exploration in pattern_ids
      assert :analysis in pattern_ids
      assert :communication in pattern_ids
    end

    test "patterns have appropriate priorities" do
      patterns = StepPattern.default_patterns()

      file_op = Enum.find(patterns, &(&1.id == :file_operation))
      communication = Enum.find(patterns, &(&1.id == :communication))

      # File operations should have higher priority than communication
      assert file_op.priority > communication.priority
    end
  end

  describe "StepPattern.validate/1" do
    test "validates correct pattern" do
      pattern =
        StepPattern.new(
          id: :valid_pattern,
          name: "Valid Pattern",
          triggers: [StepPattern.tool_trigger(["readFile"])],
          validators: [StepPattern.tool_validator(min_tools: 1)],
          priority: 75,
          confidence: 0.8
        )

      assert StepPattern.validate(pattern) == :ok
    end

    test "validates default patterns" do
      patterns = StepPattern.default_patterns()

      Enum.each(patterns, fn pattern ->
        assert StepPattern.validate(pattern) == :ok
      end)
    end

    test "returns error for invalid pattern" do
      # Test invalid priority
      pattern =
        StepPattern.new(
          id: :invalid_pattern,
          name: "Invalid Pattern",
          triggers: [StepPattern.tool_trigger(["readFile"])],
          # Invalid - should be 0-100
          priority: 150
        )

      assert {:error, _reason} = StepPattern.validate(pattern)
    end
  end
end
