defmodule ClaudeCodeSDK.StepBufferTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{StepBuffer, StepDetector, Message}

  # Test helper to create test messages
  defp create_test_message(type \\ :assistant, content \\ "test content") do
    %Message{
      type: type,
      data: %{
        message: %{"content" => content},
        session_id: "test-session"
      }
    }
  end

  # Test helper to capture step handler calls
  defp create_step_handler(test_pid) do
    fn step ->
      send(test_pid, {:step_emitted, step})
    end
  end

  # Test helper to capture error handler calls
  defp create_error_handler(test_pid) do
    fn error, state ->
      send(test_pid, {:error_handled, error, state})
    end
  end

  describe "start_link/1" do
    test "starts successfully with step detector" do
      detector = StepDetector.new()

      assert {:ok, pid} = StepBuffer.start_link(step_detector: detector)
      assert Process.alive?(pid)

      StepBuffer.stop(pid)
    end

    test "fails without step detector" do
      Process.flag(:trap_exit, true)

      result = StepBuffer.start_link([])

      case result do
        {:error, :step_detector_required} ->
          :ok

        {:error, {:error, :step_detector_required}} ->
          :ok

        other ->
          flunk("Expected error but got: #{inspect(other)}")
      end
    end

    test "accepts custom configuration" do
      detector = StepDetector.new()
      step_handler = fn _step -> :ok end

      assert {:ok, pid} =
               StepBuffer.start_link(
                 step_detector: detector,
                 step_handler: step_handler,
                 buffer_timeout_ms: 1000,
                 max_buffer_size: 50,
                 max_memory_mb: 25
               )

      status = StepBuffer.get_status(pid)
      assert is_map(status)

      StepBuffer.stop(pid)
    end

    test "can be started with name" do
      detector = StepDetector.new()

      assert {:ok, pid} =
               StepBuffer.start_link(
                 step_detector: detector,
                 name: :test_buffer
               )

      assert Process.whereis(:test_buffer) == pid

      StepBuffer.stop(:test_buffer)
    end
  end

  describe "add_message/2" do
    setup do
      detector = StepDetector.new()
      step_handler = create_step_handler(self())

      {:ok, buffer} =
        StepBuffer.start_link(
          step_detector: detector,
          step_handler: step_handler
        )

      %{buffer: buffer}
    end

    test "adds message successfully", %{buffer: buffer} do
      message = create_test_message()

      assert :ok = StepBuffer.add_message(buffer, message)

      status = StepBuffer.get_status(buffer)
      assert status.buffer_size > 0
    end

    test "handles step start detection", %{buffer: buffer} do
      message = create_test_message(:assistant, "Let me read the file")

      assert :ok = StepBuffer.add_message(buffer, message)

      status = StepBuffer.get_status(buffer)
      assert status.current_step_id != nil
    end

    test "handles step continuation", %{buffer: buffer} do
      message1 = create_test_message(:assistant, "Reading file...")
      message2 = create_test_message(:assistant, "File content: ...")

      assert :ok = StepBuffer.add_message(buffer, message1)
      assert :ok = StepBuffer.add_message(buffer, message2)

      status = StepBuffer.get_status(buffer)
      assert status.buffer_size == 2
    end

    test "emits step on completion", %{buffer: buffer} do
      # This test would need a more sophisticated mock detector
      # that returns step_end for certain messages
      message = create_test_message(:result, "Task completed")

      assert :ok = StepBuffer.add_message(buffer, message)

      # In a real scenario with proper step detection,
      # we would receive a step_emitted message
    end
  end

  describe "timeout handling" do
    test "emits step on timeout" do
      detector = StepDetector.new()
      step_handler = create_step_handler(self())

      {:ok, buffer} =
        StepBuffer.start_link(
          step_detector: detector,
          step_handler: step_handler,
          # Very short timeout for testing
          buffer_timeout_ms: 100
        )

      message = create_test_message()
      assert :ok = StepBuffer.add_message(buffer, message)

      # Wait for timeout
      assert_receive {:step_emitted, step}, 200
      assert step.status == :timeout

      StepBuffer.stop(buffer)
    end
  end

  describe "memory management" do
    test "handles memory limit exceeded" do
      detector = StepDetector.new()
      error_handler = create_error_handler(self())

      {:ok, buffer} =
        StepBuffer.start_link(
          step_detector: detector,
          error_handler: error_handler,
          # Very small limit for testing
          max_memory_mb: 0.001
        )

      # Add many messages to exceed memory limit
      for _i <- 1..10 do
        message = create_test_message(:assistant, String.duplicate("x", 1000))
        StepBuffer.add_message(buffer, message)
      end

      # Should receive memory error
      assert_receive {:error_handled, {:memory_limit_exceeded, _, _}, _state}, 1000

      StepBuffer.stop(buffer)
    end

    test "flushes step when buffer size limit exceeded" do
      detector = StepDetector.new()
      step_handler = create_step_handler(self())

      {:ok, buffer} =
        StepBuffer.start_link(
          step_detector: detector,
          step_handler: step_handler,
          # Small buffer for testing
          max_buffer_size: 3
        )

      # Add messages to exceed buffer size
      for i <- 1..5 do
        message = create_test_message(:assistant, "Message #{i}")
        StepBuffer.add_message(buffer, message)
      end

      # Should receive step emission due to buffer size limit
      assert_receive {:step_emitted, step}, 1000
      assert length(step.messages) >= 3

      StepBuffer.stop(buffer)
    end
  end

  describe "flush/1" do
    setup do
      detector = StepDetector.new()
      step_handler = create_step_handler(self())

      {:ok, buffer} =
        StepBuffer.start_link(
          step_detector: detector,
          step_handler: step_handler
        )

      %{buffer: buffer}
    end

    test "flushes current step", %{buffer: buffer} do
      message = create_test_message()
      assert :ok = StepBuffer.add_message(buffer, message)

      assert :ok = StepBuffer.flush(buffer)

      # Should receive flushed step
      assert_receive {:step_emitted, step}, 1000
      # Flushed steps are marked as timeout
      assert step.status == :timeout
    end

    test "handles flush with no current step", %{buffer: buffer} do
      assert :ok = StepBuffer.flush(buffer)

      # Should not receive any step
      refute_receive {:step_emitted, _step}, 100
    end
  end

  describe "get_status/1" do
    setup do
      detector = StepDetector.new()

      {:ok, buffer} = StepBuffer.start_link(step_detector: detector)

      %{buffer: buffer}
    end

    test "returns correct status", %{buffer: buffer} do
      status = StepBuffer.get_status(buffer)

      assert is_map(status)
      assert Map.has_key?(status, :buffer_size)
      assert Map.has_key?(status, :memory_usage_mb)
      assert Map.has_key?(status, :current_step_id)
      assert Map.has_key?(status, :steps_emitted)
      assert Map.has_key?(status, :timeouts)
      assert Map.has_key?(status, :errors)
      assert Map.has_key?(status, :uptime_ms)

      assert status.buffer_size == 0
      assert status.current_step_id == nil
      assert status.steps_emitted == 0
    end

    test "updates status after adding messages", %{buffer: buffer} do
      message = create_test_message()
      StepBuffer.add_message(buffer, message)

      status = StepBuffer.get_status(buffer)
      assert status.buffer_size > 0
      assert status.memory_usage_mb > 0
    end
  end

  describe "error handling" do
    test "handles step handler errors" do
      detector = StepDetector.new()
      error_handler = create_error_handler(self())

      # Step handler that raises an error
      step_handler = fn _step ->
        raise "Test error"
      end

      {:ok, buffer} =
        StepBuffer.start_link(
          step_detector: detector,
          step_handler: step_handler,
          error_handler: error_handler,
          buffer_timeout_ms: 100
        )

      message = create_test_message()
      StepBuffer.add_message(buffer, message)

      # Wait for timeout to trigger step emission and error
      assert_receive {:error_handled, %RuntimeError{}, _state}, 200

      StepBuffer.stop(buffer)
    end

    test "handles detection errors gracefully" do
      # This would require a mock detector that raises errors
      # For now, we test that the buffer continues to function
      detector = StepDetector.new()
      step_handler = create_step_handler(self())

      {:ok, buffer} =
        StepBuffer.start_link(
          step_detector: detector,
          step_handler: step_handler
        )

      message = create_test_message()
      assert :ok = StepBuffer.add_message(buffer, message)

      status = StepBuffer.get_status(buffer)
      assert status.buffer_size > 0

      StepBuffer.stop(buffer)
    end
  end

  describe "concurrent access" do
    test "handles concurrent message additions" do
      detector = StepDetector.new()
      step_handler = create_step_handler(self())

      {:ok, buffer} =
        StepBuffer.start_link(
          step_detector: detector,
          step_handler: step_handler
        )

      # Spawn multiple processes adding messages concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            message = create_test_message(:assistant, "Concurrent message #{i}")
            StepBuffer.add_message(buffer, message)
          end)
        end

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      status = StepBuffer.get_status(buffer)
      assert status.buffer_size > 0

      StepBuffer.stop(buffer)
    end
  end

  describe "cleanup and termination" do
    test "cleans up on termination" do
      detector = StepDetector.new()
      step_handler = create_step_handler(self())

      {:ok, buffer} =
        StepBuffer.start_link(
          step_detector: detector,
          step_handler: step_handler
        )

      message = create_test_message()
      StepBuffer.add_message(buffer, message)

      # Stop the buffer
      StepBuffer.stop(buffer)

      # Should receive the flushed step
      assert_receive {:step_emitted, _step}, 1000

      refute Process.alive?(buffer)
    end
  end
end
