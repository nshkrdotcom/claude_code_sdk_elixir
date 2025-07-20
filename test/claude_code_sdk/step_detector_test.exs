defmodule ClaudeCodeSDK.StepDetectorBasicTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{StepDetector, Message}

  test "creates detector with default patterns" do
    detector = StepDetector.new()

    assert %StepDetector{} = detector
    assert is_list(detector.patterns)
    assert length(detector.patterns) > 0
    assert detector.confidence_threshold == 0.7
    assert detector.strategy == :pattern_based
  end

  test "analyzes message with file operation tools" do
    detector = StepDetector.new()

    message = %Message{
      type: :assistant,
      data: %{
        message: %{"content" => "Reading file\n\n<function_calls>\n<invoke name=\"readFile\">"},
        session_id: "test-session"
      }
    }

    {result, updated_detector} = StepDetector.analyze_message(detector, message, [])

    # Should detect a step boundary or start
    case result do
      {:step_start, :file_operation, _metadata} -> :ok
      {:step_boundary, :file_operation, _metadata} -> :ok
      other -> flunk("Expected file operation step, got: #{inspect(other)}")
    end

    assert updated_detector.current_step_type == :file_operation
  end

  test "analyzes message with code modification tools" do
    detector = StepDetector.new()

    message = %Message{
      type: :assistant,
      data: %{
        message: %{
          "content" => "Implementing feature\n\n<function_calls>\n<invoke name=\"strReplace\">"
        },
        session_id: "test-session"
      }
    }

    {result, updated_detector} = StepDetector.analyze_message(detector, message, [])

    # Should detect code modification
    case result do
      {:step_start, :code_modification, _metadata} -> :ok
      {:step_boundary, :code_modification, _metadata} -> :ok
      other -> flunk("Expected code modification step, got: #{inspect(other)}")
    end

    assert updated_detector.current_step_type == :code_modification
  end

  test "provides statistics" do
    detector = StepDetector.new()
    stats = StepDetector.get_stats(detector)

    assert is_map(stats)
    assert stats.pattern_count > 0
    assert stats.confidence_threshold == 0.7
    assert stats.strategy == :pattern_based
  end

  test "resets detector state" do
    detector = StepDetector.new()

    # Set some state
    message = %Message{
      type: :assistant,
      data: %{
        message: %{"content" => "Reading file\n\n<function_calls>\n<invoke name=\"readFile\">"},
        session_id: "test-session"
      }
    }

    {_result, detector} = StepDetector.analyze_message(detector, message, [])
    assert detector.current_step_type != nil

    # Reset
    reset_detector = StepDetector.reset(detector)
    assert reset_detector.current_step_type == nil
    assert reset_detector.detection_history == []
  end
end
