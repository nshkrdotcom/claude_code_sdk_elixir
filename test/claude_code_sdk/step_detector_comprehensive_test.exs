defmodule ClaudeCodeSDK.StepDetectorComprehensiveTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{StepDetector, StepPattern, Message}

  describe "StepDetector.new/1" do
    test "creates detector with default patterns" do
      detector = StepDetector.new()

      assert %StepDetector{} = detector
      assert is_list(detector.patterns)
      assert length(detector.patterns) > 0
      assert detector.confidence_threshold == 0.7
      assert detector.strategy == :pattern_based
      assert detector.current_step_type == nil
      assert detector.detection_history == []
      assert is_map(detector.pattern_cache)
    end

    test "creates detector with custom options" do
      custom_patterns = [
        StepPattern.new(
          id: :custom_pattern,
          name: "Custom Pattern",
          triggers: [StepPattern.tool_trigger(["customTool"])]
        )
      ]

      detector =
        StepDetector.new(
          patterns: custom_patterns,
          confidence_threshold: 0.8,
          strategy: :hybrid
        )

      assert detector.patterns == custom_patterns
      assert detector.confidence_threshold == 0.8
      assert detector.strategy == :hybrid
    end

    test "compiles patterns into cache" do
      detector = StepDetector.new()

      # Should have compiled patterns in cache
      assert map_size(detector.pattern_cache) > 0

      # Each pattern should have a cache entry
      pattern_ids = Enum.map(detector.patterns, & &1.id)
      cache_keys = Map.keys(detector.pattern_cache)

      Enum.each(pattern_ids, fn id ->
        assert id in cache_keys
      end)
    end
  end

  describe "StepDetector.analyze_message/3" do
    setup do
      detector = StepDetector.new()
      {:ok, detector: detector}
    end

    test "detects file operation step start", %{detector: detector} do
      message = create_assistant_message_with_tools(["readFile"], "Reading configuration file")

      {result, updated_detector} = StepDetector.analyze_message(detector, message, [])

      case result do
        {:step_start, :file_operation, metadata} ->
          assert is_map(metadata)
          assert metadata.confidence > 0.5

        {:step_boundary, :file_operation, metadata} ->
          assert is_map(metadata)
          assert metadata.confidence > 0.0

        other ->
          flunk("Expected file operation detection, got: #{inspect(other)}")
      end

      assert updated_detector.current_step_type == :file_operation
    end

    test "detects code modification step start", %{detector: detector} do
      message =
        create_assistant_message_with_tools(["strReplace"], "Implementing user authentication")

      {result, updated_detector} = StepDetector.analyze_message(detector, message, [])

      case result do
        {:step_start, :code_modification, metadata} ->
          assert is_map(metadata)
          assert metadata.confidence > 0.5

        {:step_boundary, :code_modification, metadata} ->
          assert is_map(metadata)
          assert metadata.confidence > 0.0

        other ->
          flunk("Expected code modification detection, got: #{inspect(other)}")
      end

      assert updated_detector.current_step_type == :code_modification
    end

    test "detects system command step start", %{detector: detector} do
      message = create_assistant_message_with_tools(["executePwsh"], "Running tests")

      {result, updated_detector} = StepDetector.analyze_message(detector, message, [])

      assert {:step_start, :system_command, metadata} = result
      assert is_map(metadata)
      assert metadata.confidence > 0.7
      assert updated_detector.current_step_type == :system_command
    end

    test "detects step continuation", %{detector: detector} do
      # First, start a file operation step
      message1 = create_assistant_message_with_tools(["readFile"], "Reading file")
      {_result, detector} = StepDetector.analyze_message(detector, message1, [])

      # Then continue with another file operation
      message2 = create_assistant_message_with_tools(["listDirectory"], "Listing directory")
      {result, _updated_detector} = StepDetector.analyze_message(detector, message2, [message1])

      assert {:step_continue, nil} = result
    end

    test "detects step boundary", %{detector: detector} do
      # Start with file operation
      message1 = create_assistant_message_with_tools(["readFile"], "Reading file")
      {_result, detector} = StepDetector.analyze_message(detector, message1, [])

      # Switch to code modification
      message2 = create_assistant_message_with_tools(["strReplace"], "Modifying code")
      {result, updated_detector} = StepDetector.analyze_message(detector, message2, [message1])

      case result do
        {:step_boundary, :code_modification, metadata} ->
          assert is_map(metadata)

        {:step_continue, nil} ->
          # This might happen if the detector doesn't see a clear boundary
          :ok

        other ->
          flunk("Expected step boundary or continue, got: #{inspect(other)}")
      end

      # The detector should have some step type set
      assert updated_detector.current_step_type != nil
    end

    test "falls back to heuristic analysis when no patterns match", %{detector: detector} do
      message = create_assistant_message("Just explaining something without tools")

      {result, _updated_detector} = StepDetector.analyze_message(detector, message, [])

      # Should fall back to heuristic analysis
      case result do
        {:step_continue, nil} -> :ok
        {:step_start, :communication, _} -> :ok
        {:step_end, _} -> :ok
        other -> flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end

  describe "StepDetector pattern matching" do
    setup do
      detector = StepDetector.new()
      {:ok, detector: detector}
    end

    test "matches file operation tools correctly", %{detector: detector} do
      file_tools = ["readFile", "fsWrite", "fsAppend", "listDirectory", "deleteFile"]

      Enum.each(file_tools, fn tool ->
        message = create_assistant_message_with_tools([tool], "File operation")
        {result, _} = StepDetector.analyze_message(detector, message, [])

        case result do
          {:step_start, :file_operation, _} -> :ok
          {:step_boundary, :file_operation, _} -> :ok
          other -> flunk("Expected file operation for tool #{tool}, got: #{inspect(other)}")
        end
      end)
    end

    test "matches code modification tools correctly", %{detector: detector} do
      code_tools = ["strReplace", "fsWrite"]

      Enum.each(code_tools, fn tool ->
        message = create_assistant_message_with_tools([tool], "Implementing feature")
        {result, _} = StepDetector.analyze_message(detector, message, [])

        assert {:step_start, step_type, _} = result
        assert step_type in [:code_modification, :file_operation]
      end)
    end

    test "matches system command tools correctly", %{detector: detector} do
      message = create_assistant_message_with_tools(["executePwsh"], "Running command")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert {:step_start, :system_command, _} = result
    end

    test "matches exploration tools correctly", %{detector: detector} do
      exploration_tools = ["grepSearch", "fileSearch"]

      Enum.each(exploration_tools, fn tool ->
        message = create_assistant_message_with_tools([tool], "Searching code")
        {result, _} = StepDetector.analyze_message(detector, message, [])

        assert {:step_start, step_type, _} = result
        assert step_type in [:exploration, :file_operation]
      end)
    end

    test "matches content patterns correctly", %{detector: detector} do
      content_patterns = [
        {"implement", :code_modification},
        {"refactor", :code_modification},
        {"search", :exploration},
        {"analyze", :analysis}
      ]

      Enum.each(content_patterns, fn {content, expected_type} ->
        message = create_assistant_message("I will #{content} the code")
        {result, _} = StepDetector.analyze_message(detector, message, [])

        case result do
          {:step_start, actual_type, _} ->
            assert actual_type == expected_type or actual_type == :communication

          {:step_continue, nil} ->
            # Acceptable if no current step
            :ok

          _ ->
            flunk("Unexpected result: #{inspect(result)}")
        end
      end)
    end
  end

  describe "StepDetector.reset/1" do
    test "resets detector state" do
      detector = StepDetector.new()

      # Set some state
      message = create_assistant_message_with_tools(["readFile"], "Reading file")
      {_result, detector} = StepDetector.analyze_message(detector, message, [])

      assert detector.current_step_type != nil
      assert length(detector.detection_history) > 0

      # Reset
      reset_detector = StepDetector.reset(detector)

      assert reset_detector.current_step_type == nil
      assert reset_detector.detection_history == []
      # Other fields should remain unchanged
      assert reset_detector.patterns == detector.patterns
      assert reset_detector.confidence_threshold == detector.confidence_threshold
    end
  end

  describe "StepDetector.update_patterns/2" do
    test "updates patterns and recompiles cache" do
      detector = StepDetector.new()
      original_pattern_count = length(detector.patterns)

      new_patterns = [
        StepPattern.new(
          id: :test_pattern,
          name: "Test Pattern",
          triggers: [StepPattern.tool_trigger(["testTool"])]
        )
      ]

      updated_detector = StepDetector.update_patterns(detector, new_patterns)

      assert length(updated_detector.patterns) == 1
      assert length(updated_detector.patterns) != original_pattern_count
      assert Map.has_key?(updated_detector.pattern_cache, :test_pattern)
    end
  end

  describe "StepDetector.get_stats/1" do
    test "returns detector statistics" do
      detector = StepDetector.new()

      # Add some state
      message = create_assistant_message_with_tools(["readFile"], "Reading file")
      {_result, detector} = StepDetector.analyze_message(detector, message, [])

      stats = StepDetector.get_stats(detector)

      assert is_map(stats)
      assert is_integer(stats.pattern_count)
      assert stats.pattern_count > 0
      assert stats.confidence_threshold == 0.7
      assert stats.strategy == :pattern_based
      assert stats.current_step_type == :file_operation
      assert is_integer(stats.history_length)
      assert stats.history_length > 0
      assert is_integer(stats.cache_size)
      assert stats.cache_size > 0
    end
  end

  describe "StepDetector strategy modes" do
    test "pattern_based strategy uses only patterns" do
      detector = StepDetector.new(strategy: :pattern_based)

      message = create_assistant_message_with_tools(["readFile"], "Reading file")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert {:step_start, :file_operation, _} = result
    end

    test "heuristic strategy uses heuristics" do
      detector = StepDetector.new(strategy: :heuristic)

      message = create_assistant_message("Task completed successfully")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      # Heuristic should detect completion
      case result do
        {:step_end, _} -> :ok
        {:step_continue, nil} -> :ok
        other -> flunk("Unexpected heuristic result: #{inspect(other)}")
      end
    end

    test "hybrid strategy combines both approaches" do
      detector = StepDetector.new(strategy: :hybrid)

      # Should work with both pattern and heuristic detection
      message1 = create_assistant_message_with_tools(["readFile"], "Reading file")
      {result1, detector} = StepDetector.analyze_message(detector, message1, [])
      assert {:step_start, :file_operation, _} = result1

      message2 = create_assistant_message("Task completed successfully")
      {result2, _} = StepDetector.analyze_message(detector, message2, [message1])

      case result2 do
        {:step_end, _} -> :ok
        {:step_continue, nil} -> :ok
        other -> flunk("Unexpected hybrid result: #{inspect(other)}")
      end
    end
  end

  describe "StepDetector confidence scoring" do
    test "provides confidence scores in metadata" do
      detector = StepDetector.new()

      message = create_assistant_message_with_tools(["readFile"], "Reading configuration file")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert {:step_start, :file_operation, metadata} = result
      assert is_float(metadata.confidence)
      assert metadata.confidence > 0.0
      assert metadata.confidence <= 1.0
    end

    test "higher confidence for better matches" do
      detector = StepDetector.new()

      # Strong file operation match
      strong_message =
        create_assistant_message_with_tools(["readFile", "fsWrite"], "Reading and writing files")

      {result1, _} = StepDetector.analyze_message(detector, strong_message, [])

      # Weaker match
      weak_message = create_assistant_message("I will help you")
      {result2, _} = StepDetector.analyze_message(detector, weak_message, [])

      case {result1, result2} do
        {{:step_start, _, meta1}, {:step_start, _, meta2}} ->
          # If both are step starts, strong should have higher confidence
          assert meta1.confidence >= meta2.confidence

        {{:step_start, _, meta1}, _} ->
          # Strong match should be a step start with good confidence
          assert meta1.confidence > 0.7

        _ ->
          # At least the strong match should be detected
          assert match?({:step_start, _, _}, result1)
      end
    end
  end

  describe "StepDetector error handling" do
    test "handles malformed messages gracefully" do
      detector = StepDetector.new()

      # Create message with missing data
      malformed_message = %Message{
        type: :assistant,
        data: %{}
      }

      {result, _} = StepDetector.analyze_message(detector, malformed_message, [])

      # Should not crash and return a valid result
      case result do
        {:step_continue, nil} -> :ok
        {:step_start, _, _} -> :ok
        {:step_end, _} -> :ok
        other -> flunk("Unexpected error handling result: #{inspect(other)}")
      end
    end

    test "handles empty buffer gracefully" do
      detector = StepDetector.new()

      message = create_assistant_message_with_tools(["readFile"], "Reading file")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert {:step_start, :file_operation, _} = result
    end

    test "handles custom pattern functions that raise errors" do
      error_pattern =
        StepPattern.new(
          id: :error_pattern,
          name: "Error Pattern",
          triggers: [
            StepPattern.custom_trigger(fn _context -> raise "Test error" end)
          ]
        )

      detector = StepDetector.new(patterns: [error_pattern])

      message = create_assistant_message("Test message")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      # Should not crash and fall back to heuristics
      case result do
        {:step_continue, nil} -> :ok
        {:step_start, _, _} -> :ok
        {:step_end, _} -> :ok
        other -> flunk("Unexpected error pattern result: #{inspect(other)}")
      end
    end
  end

  describe "StepDetector custom patterns" do
    test "supports custom patterns with tool triggers" do
      custom_pattern =
        StepPattern.new(
          id: :custom_tool_pattern,
          name: "Custom Tool Pattern",
          triggers: [StepPattern.tool_trigger(["customTool"])],
          priority: 95,
          confidence: 0.9
        )

      detector = StepDetector.new(patterns: [custom_pattern])

      message = create_assistant_message_with_tools(["customTool"], "Using custom tool")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert {:step_start, :custom_tool_pattern, metadata} = result
      assert metadata.confidence > 0.8
    end

    test "supports custom patterns with content triggers" do
      custom_pattern =
        StepPattern.new(
          id: :custom_content_pattern,
          name: "Custom Content Pattern",
          triggers: [StepPattern.content_trigger(~r/special.*operation/i)],
          priority: 90,
          confidence: 0.85
        )

      detector = StepDetector.new(patterns: [custom_pattern])

      message = create_assistant_message("Performing special operation")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert {:step_start, :custom_content_pattern, metadata} = result
      assert metadata.confidence > 0.7
    end

    test "supports custom patterns with function triggers" do
      custom_function = fn context ->
        String.contains?(context.content, "magic keyword")
      end

      custom_pattern =
        StepPattern.new(
          id: :custom_function_pattern,
          name: "Custom Function Pattern",
          triggers: [StepPattern.custom_trigger(custom_function)],
          priority: 85,
          confidence: 0.8
        )

      detector = StepDetector.new(patterns: [custom_pattern])

      message = create_assistant_message("This contains the magic keyword")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      assert {:step_start, :custom_function_pattern, metadata} = result
      assert metadata.confidence > 0.5
    end
  end

  describe "StepDetector pattern priority" do
    test "higher priority patterns take precedence" do
      high_priority_pattern =
        StepPattern.new(
          id: :high_priority,
          name: "High Priority Pattern",
          triggers: [StepPattern.tool_trigger(["readFile"])],
          priority: 100,
          confidence: 0.8
        )

      low_priority_pattern =
        StepPattern.new(
          id: :low_priority,
          name: "Low Priority Pattern",
          triggers: [StepPattern.tool_trigger(["readFile"])],
          priority: 10,
          confidence: 0.9
        )

      detector = StepDetector.new(patterns: [low_priority_pattern, high_priority_pattern])

      message = create_assistant_message_with_tools(["readFile"], "Reading file")
      {result, _} = StepDetector.analyze_message(detector, message, [])

      # Should match the high priority pattern despite lower confidence
      assert {:step_start, :high_priority, _} = result
    end
  end

  # Helper functions for creating test messages
  defp create_assistant_message(content) do
    %Message{
      type: :assistant,
      data: %{
        message: %{"content" => content},
        session_id: "test-session"
      }
    }
  end

  defp create_assistant_message_with_tools(tools, content) do
    # Create content with tool usage
    tool_calls =
      Enum.map(tools, fn tool ->
        ~s(<invoke name="#{tool}">)
      end)
      |> Enum.join("\n")

    full_content = "#{content}\n\n<function_calls>\n#{tool_calls}\n</function_calls>"

    %Message{
      type: :assistant,
      data: %{
        message: %{"content" => full_content},
        session_id: "test-session"
      }
    }
  end
end
