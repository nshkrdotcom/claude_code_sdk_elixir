defmodule ClaudeCodeSDK.StepStreamUtilsTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{StepStreamUtils, Step}

  # Test helper to create test steps
  defp create_test_step(opts) do
    defaults = [
      type: :unknown,
      description: "Test step",
      status: :completed,
      messages: [],
      tools_used: []
    ]

    opts = Keyword.merge(defaults, opts)
    desired_status = Keyword.get(opts, :status, :completed)

    step = Step.new(opts)

    # Set the desired status without calling complete() which overrides it
    case desired_status do
      :completed -> Step.complete(step)
      :error -> %{step | status: :error, completed_at: DateTime.utc_now()}
      :timeout -> Step.timeout(step)
      :aborted -> Step.abort(step)
      other -> %{step | status: other}
    end
  end

  # Test helper to create a list of test steps
  defp create_test_steps() do
    [
      create_test_step(
        type: :file_operation,
        description: "Read file",
        status: :completed,
        tools_used: ["readFile"]
      ),
      create_test_step(
        type: :code_modification,
        description: "Update code",
        status: :in_progress,
        tools_used: ["strReplace"]
      ),
      create_test_step(
        type: :file_operation,
        description: "Write file",
        status: :completed,
        tools_used: ["fsWrite"]
      ),
      create_test_step(
        type: :analysis,
        description: "Analyze code",
        status: :error,
        tools_used: ["grepSearch"]
      ),
      create_test_step(
        type: :system_command,
        description: "Run tests",
        status: :completed,
        tools_used: ["executePwsh"]
      )
    ]
  end

  describe "filtering utilities" do
    setup do
      %{steps: create_test_steps()}
    end

    test "filter_completed/1 filters completed steps", %{steps: steps} do
      completed =
        steps
        |> StepStreamUtils.filter_completed()
        |> Enum.to_list()

      assert length(completed) == 3
      assert Enum.all?(completed, &(&1.status == :completed))
    end

    test "filter_in_progress/1 filters in-progress steps", %{steps: steps} do
      in_progress =
        steps
        |> StepStreamUtils.filter_in_progress()
        |> Enum.to_list()

      assert length(in_progress) == 1
      assert Enum.all?(in_progress, &(&1.status == :in_progress))
    end

    test "filter_errors/1 filters error steps", %{steps: steps} do
      errors =
        steps
        |> StepStreamUtils.filter_errors()
        |> Enum.to_list()

      assert length(errors) == 1
      assert Enum.all?(errors, &(&1.status == :error))
    end

    test "filter_by/2 filters by custom predicate", %{steps: steps} do
      file_ops =
        steps
        |> StepStreamUtils.filter_by(fn step -> step.type == :file_operation end)
        |> Enum.to_list()

      assert length(file_ops) == 2
      assert Enum.all?(file_ops, &(&1.type == :file_operation))
    end

    test "filter_by_tools/2 filters by tools used", %{steps: steps} do
      file_tools =
        steps
        |> StepStreamUtils.filter_by_tools(["readFile", "fsWrite"])
        |> Enum.to_list()

      assert length(file_tools) == 2

      assert Enum.all?(file_tools, fn step ->
               Enum.any?(step.tools_used, fn tool -> tool in ["readFile", "fsWrite"] end)
             end)
    end
  end

  describe "mapping and transformation utilities" do
    setup do
      %{steps: create_test_steps()}
    end

    test "map_descriptions/1 maps to descriptions", %{steps: steps} do
      descriptions =
        steps
        |> StepStreamUtils.map_descriptions()
        |> Enum.to_list()

      assert length(descriptions) == 5
      assert Enum.all?(descriptions, &is_binary/1)
      assert "Read file" in descriptions
    end

    test "map_types/1 maps to types", %{steps: steps} do
      types =
        steps
        |> StepStreamUtils.map_types()
        |> Enum.to_list()

      assert length(types) == 5
      assert :file_operation in types
      assert :code_modification in types
    end

    test "map_summaries/1 maps to summaries", %{steps: steps} do
      summaries =
        steps
        |> StepStreamUtils.map_summaries()
        |> Enum.to_list()

      assert length(summaries) == 5
      assert Enum.all?(summaries, &is_map/1)
      assert Enum.all?(summaries, &Map.has_key?(&1, :id))
    end

    test "transform_with/2 applies custom transformation", %{steps: steps} do
      transformed =
        steps
        |> StepStreamUtils.transform_with(fn step ->
          %{step | description: String.upcase(step.description)}
        end)
        |> Enum.to_list()

      assert length(transformed) == 5

      assert Enum.all?(transformed, fn step ->
               step.description == String.upcase(step.description)
             end)
    end
  end

  describe "grouping and batching utilities" do
    setup do
      %{steps: create_test_steps()}
    end

    test "group_by_type/1 groups by step type", %{steps: steps} do
      grouped = StepStreamUtils.group_by_type(steps)

      assert is_map(grouped)
      assert Map.has_key?(grouped, :file_operation)
      assert Map.has_key?(grouped, :code_modification)
      assert length(grouped[:file_operation]) == 2
      assert length(grouped[:code_modification]) == 1
    end

    test "group_by_status/1 groups by step status", %{steps: steps} do
      grouped = StepStreamUtils.group_by_status(steps)

      assert is_map(grouped)
      assert Map.has_key?(grouped, :completed)
      assert Map.has_key?(grouped, :in_progress)
      assert Map.has_key?(grouped, :error)
      assert length(grouped[:completed]) == 3
    end

    test "group_by/2 groups by custom function", %{steps: steps} do
      grouped = StepStreamUtils.group_by(steps, fn step -> step.type end)

      assert is_map(grouped)
      assert Map.has_key?(grouped, :file_operation)
      assert length(grouped[:file_operation]) == 2
    end

    test "batch_by_size/2 batches by size", %{steps: steps} do
      batches =
        steps
        |> StepStreamUtils.batch_by_size(2)
        |> Enum.to_list()

      # 5 steps in batches of 2 = 3 batches
      assert length(batches) == 3
      assert length(Enum.at(batches, 0)) == 2
      assert length(Enum.at(batches, 1)) == 2
      assert length(Enum.at(batches, 2)) == 1
    end

    test "batch_by_time/2 batches by time windows", %{steps: steps} do
      # Add timestamps to steps
      now = DateTime.utc_now()

      timestamped_steps =
        steps
        |> Enum.with_index()
        |> Enum.map(fn {step, index} ->
          # 1 second apart
          timestamp = DateTime.add(now, index * 1000, :millisecond)
          %{step | started_at: timestamp}
        end)

      # 2.5 second windows
      batches = StepStreamUtils.batch_by_time(timestamped_steps, 2500)

      assert is_map(batches)
      assert map_size(batches) >= 1
    end
  end

  describe "timeout and control utilities" do
    setup do
      %{steps: create_test_steps()}
    end

    test "with_timeout/3 handles timeout with error strategy", %{steps: steps} do
      result =
        steps
        |> StepStreamUtils.with_timeout(1000, :error)
        |> Enum.to_list()

      # For now, just returns the original stream
      assert length(result) == 5
    end

    test "with_timeout/3 handles timeout with complete strategy", %{steps: steps} do
      result =
        steps
        |> StepStreamUtils.with_timeout(1000, :complete)
        |> Enum.to_list()

      assert length(result) == 5
    end

    test "with_timeout/3 handles default value", %{steps: _steps} do
      result =
        []
        |> StepStreamUtils.with_timeout(1000, {:default, :empty})
        |> Enum.to_list()

      assert result == [:empty]
    end

    test "take/2 limits number of steps", %{steps: steps} do
      limited =
        steps
        |> StepStreamUtils.take(3)
        |> Enum.to_list()

      assert length(limited) == 3
    end

    test "drop/2 skips first N steps", %{steps: steps} do
      remaining =
        steps
        |> StepStreamUtils.drop(2)
        |> Enum.to_list()

      assert length(remaining) == 3
    end
  end

  describe "debugging and visualization utilities" do
    setup do
      %{steps: create_test_steps()}
    end

    test "debug_steps/2 adds debug logging", %{steps: steps} do
      # Capture log output
      import ExUnit.CaptureLog

      result =
        capture_log(fn ->
          steps
          |> StepStreamUtils.debug_steps(level: :info, prefix: "Test")
          |> Enum.to_list()
        end)

      assert String.contains?(result, "Test:")
      assert String.contains?(result, "Read file")
    end

    test "inspect_steps/2 prints step information", %{steps: steps} do
      import ExUnit.CaptureIO

      result =
        capture_io(fn ->
          steps
          |> Stream.take(1)
          |> StepStreamUtils.inspect_steps(:summary)
          |> Enum.to_list()
        end)

      assert String.contains?(result, "Step")
      assert String.contains?(result, "file_operation")
    end

    test "inspect_steps/2 with detailed format", %{steps: steps} do
      import ExUnit.CaptureIO

      result =
        capture_io(fn ->
          steps
          |> Stream.take(1)
          |> StepStreamUtils.inspect_steps(:detailed)
          |> Enum.to_list()
        end)

      assert String.contains?(result, "Type:")
      assert String.contains?(result, "Status:")
      assert String.contains?(result, "Description:")
    end

    test "collect_stats/1 collects stream statistics", %{steps: steps} do
      stats = StepStreamUtils.collect_stats(steps)

      assert stats.total_steps == 5
      assert is_map(stats.by_type)
      assert is_map(stats.by_status)
      # Our test steps have no messages
      assert stats.total_messages == 0
      assert is_list(stats.unique_tools)
      assert is_float(stats.avg_messages_per_step)
    end
  end

  describe "composition and utility helpers" do
    setup do
      %{steps: create_test_steps()}
    end

    test "pipe_through/2 applies multiple transformations", %{steps: steps} do
      result =
        steps
        |> StepStreamUtils.pipe_through([
          &StepStreamUtils.filter_completed/1,
          fn stream -> StepStreamUtils.take(stream, 2) end
        ])
        |> Enum.to_list()

      assert length(result) == 2
      assert Enum.all?(result, &(&1.status == :completed))
    end

    test "tap/2 applies side effects without modifying stream", %{steps: steps} do
      test_pid = self()

      result =
        steps
        |> Stream.take(2)
        |> StepStreamUtils.tap(fn step ->
          send(test_pid, {:tapped, step.id})
        end)
        |> Enum.to_list()

      assert length(result) == 2

      # Should have received tap messages
      assert_receive {:tapped, _step_id}
      assert_receive {:tapped, _step_id}
    end

    test "validate_steps/2 filters valid steps", %{steps: steps} do
      valid =
        steps
        |> StepStreamUtils.validate_steps(fn step ->
          not is_nil(step.id) and is_binary(step.description)
        end)
        |> Enum.to_list()

      # All our test steps should be valid
      assert length(valid) == 5
    end

    test "validate_steps/2 handles validation errors", %{steps: steps} do
      valid =
        steps
        |> StepStreamUtils.validate_steps(fn _step ->
          raise "Validation error"
        end)
        |> Enum.to_list()

      # All steps should be filtered out due to errors
      assert length(valid) == 0
    end

    test "to_list_safe/2 converts stream safely", %{steps: steps} do
      result = StepStreamUtils.to_list_safe(steps)

      assert {:ok, list} = result
      assert length(list) == 5
    end

    test "to_list_safe/2 handles max_items option", %{steps: steps} do
      result = StepStreamUtils.to_list_safe(steps, max_items: 3)

      assert {:ok, list} = result
      assert length(list) == 3
    end

    test "to_list_safe/2 handles timeout", %{steps: _steps} do
      # Create a slow stream
      slow_stream =
        Stream.map(1..10, fn i ->
          Process.sleep(100)
          create_test_step(description: "Slow step #{i}")
        end)

      result = StepStreamUtils.to_list_safe(slow_stream, timeout: 50)

      assert {:error, :timeout} = result
    end
  end

  describe "edge cases and error handling" do
    test "handles empty streams gracefully" do
      empty_stream = []

      # Test various operations on empty streams
      assert [] == StepStreamUtils.filter_completed(empty_stream) |> Enum.to_list()
      assert [] == StepStreamUtils.map_descriptions(empty_stream) |> Enum.to_list()
      assert %{} == StepStreamUtils.group_by_type(empty_stream)

      stats = StepStreamUtils.collect_stats(empty_stream)
      assert stats.total_steps == 0
      assert stats.avg_messages_per_step == 0.0
    end

    test "handles invalid step data gracefully" do
      # Create steps with missing or invalid data
      invalid_steps = [
        %Step{id: nil, type: :unknown, description: "", status: :completed},
        %Step{id: "valid", type: :file_operation, description: "Valid step", status: :completed}
      ]

      # Should handle invalid data without crashing
      result =
        invalid_steps
        |> StepStreamUtils.filter_completed()
        |> Enum.to_list()

      # Both steps have :completed status
      assert length(result) == 2
    end

    test "handles large streams efficiently" do
      # Create a large stream
      large_stream =
        Stream.map(1..1000, fn i ->
          create_test_step(description: "Step #{i}")
        end)

      # Should process efficiently
      count =
        large_stream
        |> StepStreamUtils.filter_completed()
        |> StepStreamUtils.take(100)
        |> Enum.count()

      assert count == 100
    end
  end
end
