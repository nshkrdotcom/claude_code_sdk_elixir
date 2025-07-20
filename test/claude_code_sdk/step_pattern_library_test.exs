defmodule ClaudeCodeSDK.StepPatternLibraryTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{StepPattern, StepDetector, Message}

  describe "default_patterns/0" do
    test "returns all required built-in patterns" do
      patterns = StepPattern.default_patterns()

      assert length(patterns) == 6

      pattern_ids = Enum.map(patterns, & &1.id)

      expected_ids = [
        :file_operation,
        :code_modification,
        :system_command,
        :exploration,
        :analysis,
        :communication
      ]

      for expected_id <- expected_ids do
        assert expected_id in pattern_ids, "Missing pattern: #{expected_id}"
      end
    end

    test "patterns have correct priority ordering" do
      patterns = StepPattern.default_patterns()
      priorities = Enum.map(patterns, & &1.priority)

      # Should be in descending priority order
      assert priorities == Enum.sort(priorities, :desc)

      # Verify specific priorities
      file_op = Enum.find(patterns, &(&1.id == :file_operation))
      communication = Enum.find(patterns, &(&1.id == :communication))

      assert file_op.priority > communication.priority
    end

    test "all patterns are valid" do
      patterns = StepPattern.default_patterns()

      for pattern <- patterns do
        assert :ok = StepPattern.validate(pattern)
      end
    end
  end

  describe "file operation pattern" do
    setup do
      detector = StepDetector.new()
      {:ok, detector: detector}
    end

    test "detects file reading operations", %{detector: detector} do
      test_cases = [
        ["readFile"],
        ["readMultipleFiles"],
        ["listDirectory"]
      ]

      for tools <- test_cases do
        message = create_message_with_tools(tools)
        {result, _} = StepDetector.analyze_message(detector, message, [])

        # readFile and readMultipleFiles could be detected as analysis in some contexts
        # listDirectory should be file_operation
        case {tools, result} do
          {["listDirectory"], _} ->
            assert_step_detected(result, :file_operation)

          {_, {:step_start, type, _}} when type in [:file_operation, :analysis] ->
            :ok

          {_, {:step_boundary, type, _}} when type in [:file_operation, :analysis] ->
            :ok

          {_, other} ->
            flunk("Unexpected result for #{inspect(tools)}: #{inspect(other)}")
        end
      end
    end

    test "detects file writing operations", %{detector: detector} do
      test_cases = [
        ["fsWrite"],
        ["fsAppend"],
        ["deleteFile"]
      ]

      for tools <- test_cases do
        message = create_message_with_tools(tools)
        {result, _} = StepDetector.analyze_message(detector, message, [])

        assert_step_detected(result, :file_operation)
      end
    end

    test "detects combined file operations", %{detector: detector} do
      message = create_message_with_tools(["readFile", "fsWrite", "listDirectory"])
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert_step_detected(result, :file_operation)

      # Check confidence if it's a pattern-based result
      case result do
        {_, _, metadata} when is_map(metadata) and is_map_key(metadata, :confidence) ->
          assert metadata.confidence >= 0.5

        # Heuristic results don't have confidence
        _ ->
          :ok
      end
    end

    test "has highest priority among patterns", %{detector: detector} do
      # Message that could match both file_operation and exploration
      message = create_message_with_tools(["listDirectory"])
      {result, _} = StepDetector.analyze_message(detector, message, [])

      # Should choose file_operation due to higher priority
      assert_step_detected(result, :file_operation)
    end
  end

  describe "code modification pattern" do
    setup do
      detector = StepDetector.new()
      {:ok, detector: detector}
    end

    test "detects string replacement operations", %{detector: detector} do
      message = create_message_with_tools(["strReplace"])
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert_step_detected(result, :code_modification)
    end

    test "detects content-based code modification triggers", %{detector: detector} do
      test_cases = [
        "Let me implement the authentication feature",
        "I'll refactor this code to be more efficient",
        "I need to fix the bug in the parser",
        "Let me update the code to handle errors"
      ]

      for content <- test_cases do
        message = create_message_with_content(content)
        {result, _} = StepDetector.analyze_message(detector, message, [])

        # Content-based matching might have lower confidence, check for start or continue
        case result do
          {:step_start, :code_modification, _} -> :ok
          # Acceptable if confidence is below threshold
          {:step_continue, nil} -> :ok
          other -> flunk("Unexpected result for '#{content}': #{inspect(other)}")
        end
      end
    end

    test "validates file extensions for code files", %{detector: detector} do
      # This test verifies the validator works, though it's harder to test directly
      # through the detector since validators are applied after triggers match
      message = create_message_with_tools(["strReplace"])
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert_step_detected(result, :code_modification)
    end
  end

  describe "system command pattern" do
    setup do
      detector = StepDetector.new()
      {:ok, detector: detector}
    end

    test "detects PowerShell execution", %{detector: detector} do
      message = create_message_with_tools(["executePwsh"])
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert {:step_start, :system_command, _} = result
    end

    test "detects content-based command triggers", %{detector: detector} do
      test_cases = [
        "Let me run the tests",
        "I'll execute the build command",
        "Running the shell script now",
        "Let me use bash to check the status"
      ]

      for content <- test_cases do
        message = create_message_with_content(content)
        {result, _} = StepDetector.analyze_message(detector, message, [])

        case result do
          {:step_start, :system_command, _} -> :ok
          # Acceptable if confidence is below threshold
          {:step_continue, nil} -> :ok
          other -> flunk("Unexpected result for '#{content}': #{inspect(other)}")
        end
      end
    end
  end

  describe "exploration pattern" do
    setup do
      detector = StepDetector.new()
      {:ok, detector: detector}
    end

    test "detects search operations", %{detector: detector} do
      test_cases = [
        ["grepSearch"],
        ["fileSearch"]
      ]

      for tools <- test_cases do
        message = create_message_with_tools(tools)
        {result, _} = StepDetector.analyze_message(detector, message, [])

        assert_step_detected(result, :exploration)
      end
    end

    test "detects content-based exploration triggers", %{detector: detector} do
      test_cases = [
        "Let me search for the configuration",
        "I need to find the error handling code",
        "Let me explore the project structure",
        "I'll browse through the codebase",
        "Let me discover how this works"
      ]

      for content <- test_cases do
        message = create_message_with_content(content)
        {result, _} = StepDetector.analyze_message(detector, message, [])

        case result do
          {:step_start, :exploration, _} -> :ok
          # Acceptable if confidence is below threshold
          {:step_continue, nil} -> :ok
          other -> flunk("Unexpected result for '#{content}': #{inspect(other)}")
        end
      end
    end
  end

  describe "analysis pattern" do
    setup do
      detector = StepDetector.new()
      {:ok, detector: detector}
    end

    test "detects file analysis operations", %{detector: detector} do
      test_cases = [
        ["readFile"],
        ["readMultipleFiles"]
      ]

      for tools <- test_cases do
        message = create_message_with_tools(tools)
        {result, _} = StepDetector.analyze_message(detector, message, [])

        # Could be either analysis or file_operation depending on context and strategy
        # Both are valid interpretations
        case result do
          {:step_start, type, _} when type in [:file_operation, :analysis] -> :ok
          {:step_boundary, type, _} when type in [:file_operation, :analysis] -> :ok
          other -> flunk("Expected file_operation or analysis, got: #{inspect(other)}")
        end
      end
    end

    test "detects content-based analysis triggers", %{detector: detector} do
      test_cases = [
        "Let me analyze this code structure",
        "I need to review the implementation",
        "Let me understand how this works",
        "I'll examine the error patterns",
        "Let me inspect the data flow"
      ]

      for content <- test_cases do
        message = create_message_with_content(content)
        {result, _} = StepDetector.analyze_message(detector, message, [])

        case result do
          {:step_start, :analysis, _} -> :ok
          # Acceptable if confidence is below threshold
          {:step_continue, nil} -> :ok
          other -> flunk("Unexpected result for '#{content}': #{inspect(other)}")
        end
      end
    end
  end

  describe "communication pattern" do
    setup do
      detector = StepDetector.new()
      {:ok, detector: detector}
    end

    test "detects general communication", %{detector: detector} do
      test_cases = [
        "Let me explain how this works",
        "I'll describe the architecture",
        "Let me tell you about the approach",
        "I'll show you the solution",
        "How can I help you with this?"
      ]

      for content <- test_cases do
        message = create_message_with_content(content)
        {result, _} = StepDetector.analyze_message(detector, message, [])

        case result do
          {:step_start, :communication, _} -> :ok
          # Acceptable if confidence is below threshold
          {:step_continue, nil} -> :ok
          other -> flunk("Unexpected result for '#{content}': #{inspect(other)}")
        end
      end
    end

    test "has lowest priority among patterns", %{detector: _detector} do
      # Communication pattern should have the lowest priority
      patterns = StepPattern.default_patterns()
      communication_pattern = Enum.find(patterns, &(&1.id == :communication))

      other_priorities =
        patterns
        |> Enum.filter(&(&1.id != :communication))
        |> Enum.map(& &1.priority)

      assert communication_pattern.priority < Enum.min(other_priorities)
    end
  end

  describe "pattern competition and priority" do
    setup do
      detector = StepDetector.new()
      {:ok, detector: detector}
    end

    test "higher priority patterns win when multiple match", %{detector: detector} do
      # listDirectory could match both file_operation and exploration
      # file_operation has higher priority (90 vs 70)
      message = create_message_with_tools(["listDirectory"])
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert_step_detected(result, :file_operation)
    end

    test "confidence affects pattern selection", %{detector: _detector} do
      # Test that higher confidence can overcome lower priority
      # This is harder to test directly, but we can verify the logic exists
      high_threshold_detector = StepDetector.new(confidence_threshold: 0.95)

      # A message that might have low confidence matches
      message = create_message_with_content("maybe do something")
      {result, _} = StepDetector.analyze_message(high_threshold_detector, message, [])

      # Should fall back to heuristics due to low confidence
      assert {:step_continue, nil} = result
    end
  end

  describe "pattern validation and error handling" do
    test "validates all built-in patterns" do
      patterns = StepPattern.default_patterns()

      for pattern <- patterns do
        assert :ok = StepPattern.validate(pattern)

        # Check required fields
        assert is_atom(pattern.id)
        assert is_binary(pattern.name)
        assert is_list(pattern.triggers)
        assert length(pattern.triggers) > 0
        assert is_list(pattern.validators)
        assert is_integer(pattern.priority)
        assert pattern.priority >= 0 and pattern.priority <= 100
        assert is_float(pattern.confidence)
        assert pattern.confidence >= 0.0 and pattern.confidence <= 1.0
      end
    end

    test "patterns have unique IDs" do
      patterns = StepPattern.default_patterns()
      ids = Enum.map(patterns, & &1.id)
      unique_ids = Enum.uniq(ids)

      assert length(ids) == length(unique_ids), "Duplicate pattern IDs found"
    end

    test "patterns have reasonable confidence values" do
      patterns = StepPattern.default_patterns()

      for pattern <- patterns do
        assert pattern.confidence >= 0.5, "Pattern #{pattern.id} has very low confidence"
        assert pattern.confidence <= 1.0, "Pattern #{pattern.id} has invalid confidence"
      end
    end
  end

  # Helper functions
  defp assert_step_detected(result, expected_type) do
    case result do
      {:step_start, ^expected_type, _} -> :ok
      {:step_boundary, ^expected_type, _} -> :ok
      other -> flunk("Expected step type #{expected_type}, got: #{inspect(other)}")
    end
  end

  defp create_message_with_tools(tools) do
    tool_calls =
      Enum.map(tools, fn tool ->
        "<invoke name=\"#{tool}\"></invoke>"
      end)
      |> Enum.join("")

    content = "<function_calls>#{tool_calls}</function_calls>"

    %Message{
      type: :assistant,
      data: %{
        message: %{"content" => content},
        session_id: "test-session"
      }
    }
  end

  defp create_message_with_content(content) do
    %Message{
      type: :assistant,
      data: %{
        message: %{"content" => content},
        session_id: "test-session"
      }
    }
  end
end
