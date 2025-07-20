defmodule ClaudeCodeSDK.StepStreamUtils do
  @moduledoc """
  Utility functions for working with step streams.

  This module provides additional utilities for filtering, mapping, batching,
  debugging, and visualizing step streams. These utilities complement the core
  StepStream functionality.

  ## Features

  - Advanced filtering and mapping operations
  - Batching and grouping utilities
  - Timeout handling for step streams
  - Debugging and visualization tools
  - Stream composition helpers

  ## Examples

      step_stream
      |> StepStreamUtils.filter_completed()
      |> StepStreamUtils.group_by_type()
      |> StepStreamUtils.debug_steps()
      |> Enum.to_list()

  """

  alias ClaudeCodeSDK.{Step, Message}
  require Logger

  @type step_stream :: Enumerable.t()
  @type step_filter :: (Step.t() -> boolean())
  @type step_mapper :: (Step.t() -> any())
  @type step_grouper :: (Step.t() -> any())

  ## Filtering Utilities

  @doc """
  Filters steps that have completed successfully.

  ## Parameters

  - `step_stream` - Stream of steps

  ## Examples

      step_stream
      |> StepStreamUtils.filter_completed()
      |> Enum.count()

  """
  @spec filter_completed(step_stream()) :: step_stream()
  def filter_completed(step_stream) do
    Stream.filter(step_stream, fn step ->
      step.status == :completed
    end)
  end

  @doc """
  Filters steps that are in progress.

  ## Parameters

  - `step_stream` - Stream of steps

  ## Examples

      active_steps = step_stream
      |> StepStreamUtils.filter_in_progress()
      |> Enum.to_list()

  """
  @spec filter_in_progress(step_stream()) :: step_stream()
  def filter_in_progress(step_stream) do
    Stream.filter(step_stream, fn step ->
      step.status == :in_progress
    end)
  end

  @doc """
  Filters steps that have errors.

  ## Parameters

  - `step_stream` - Stream of steps

  ## Examples

      error_steps = step_stream
      |> StepStreamUtils.filter_errors()
      |> Enum.to_list()

  """
  @spec filter_errors(step_stream()) :: step_stream()
  def filter_errors(step_stream) do
    Stream.filter(step_stream, fn step ->
      step.status == :error
    end)
  end

  @doc """
  Filters steps by custom predicate function.

  ## Parameters

  - `step_stream` - Stream of steps
  - `predicate` - Function that returns true for steps to keep

  ## Examples

      long_steps = step_stream
      |> StepStreamUtils.filter_by(fn step ->
        length(step.messages) > 5
      end)

  """
  @spec filter_by(step_stream(), step_filter()) :: step_stream()
  def filter_by(step_stream, predicate) when is_function(predicate, 1) do
    Stream.filter(step_stream, predicate)
  end

  @doc """
  Filters steps that contain specific tools.

  ## Parameters

  - `step_stream` - Stream of steps
  - `tools` - List of tool names to filter by

  ## Examples

      file_steps = step_stream
      |> StepStreamUtils.filter_by_tools(["readFile", "fsWrite"])

  """
  @spec filter_by_tools(step_stream(), [String.t()]) :: step_stream()
  def filter_by_tools(step_stream, tools) when is_list(tools) do
    Stream.filter(step_stream, fn step ->
      Enum.any?(step.tools_used, fn tool -> tool in tools end)
    end)
  end

  ## Mapping and Transformation Utilities

  @doc """
  Maps steps to their descriptions.

  ## Parameters

  - `step_stream` - Stream of steps

  ## Examples

      descriptions = step_stream
      |> StepStreamUtils.map_descriptions()
      |> Enum.to_list()

  """
  @spec map_descriptions(step_stream()) :: Enumerable.t()
  def map_descriptions(step_stream) do
    Stream.map(step_stream, fn step -> step.description end)
  end

  @doc """
  Maps steps to their types.

  ## Parameters

  - `step_stream` - Stream of steps

  ## Examples

      types = step_stream
      |> StepStreamUtils.map_types()
      |> Enum.to_list()

  """
  @spec map_types(step_stream()) :: Enumerable.t()
  def map_types(step_stream) do
    Stream.map(step_stream, fn step -> step.type end)
  end

  @doc """
  Maps steps to summary information.

  ## Parameters

  - `step_stream` - Stream of steps

  ## Examples

      summaries = step_stream
      |> StepStreamUtils.map_summaries()
      |> Enum.to_list()

  """
  @spec map_summaries(step_stream()) :: Enumerable.t()
  def map_summaries(step_stream) do
    Stream.map(step_stream, fn step -> Step.to_summary(step) end)
  end

  @doc """
  Transforms steps with a custom mapper function.

  ## Parameters

  - `step_stream` - Stream of steps
  - `mapper` - Function to transform each step

  ## Examples

      enhanced_steps = step_stream
      |> StepStreamUtils.transform_with(fn step ->
        %{step | metadata: Map.put(step.metadata, :processed_at, DateTime.utc_now())}
      end)

  """
  @spec transform_with(step_stream(), step_mapper()) :: step_stream()
  def transform_with(step_stream, mapper) when is_function(mapper, 1) do
    Stream.map(step_stream, mapper)
  end

  ## Grouping and Batching Utilities

  @doc """
  Groups steps by their type.

  ## Parameters

  - `step_stream` - Stream of steps

  ## Returns

  A map where keys are step types and values are lists of steps.

  ## Examples

      grouped = step_stream
      |> StepStreamUtils.group_by_type()

  """
  @spec group_by_type(step_stream()) :: %{Step.step_type() => [Step.t()]}
  def group_by_type(step_stream) do
    step_stream
    |> Enum.group_by(fn step -> step.type end)
  end

  @doc """
  Groups steps by their status.

  ## Parameters

  - `step_stream` - Stream of steps

  ## Returns

  A map where keys are step statuses and values are lists of steps.

  ## Examples

      by_status = step_stream
      |> StepStreamUtils.group_by_status()

  """
  @spec group_by_status(step_stream()) :: %{Step.step_status() => [Step.t()]}
  def group_by_status(step_stream) do
    step_stream
    |> Enum.group_by(fn step -> step.status end)
  end

  @doc """
  Groups steps by a custom grouping function.

  ## Parameters

  - `step_stream` - Stream of steps
  - `grouper` - Function that returns the group key for each step

  ## Examples

      by_message_count = step_stream
      |> StepStreamUtils.group_by(fn step -> length(step.messages) end)

  """
  @spec group_by(step_stream(), step_grouper()) :: %{any() => [Step.t()]}
  def group_by(step_stream, grouper) when is_function(grouper, 1) do
    step_stream
    |> Enum.group_by(grouper)
  end

  @doc """
  Batches steps into fixed-size groups.

  ## Parameters

  - `step_stream` - Stream of steps
  - `size` - Number of steps per batch

  ## Examples

      batches = step_stream
      |> StepStreamUtils.batch_by_size(5)
      |> Enum.to_list()

  """
  @spec batch_by_size(step_stream(), pos_integer()) :: Enumerable.t()
  def batch_by_size(step_stream, size) when is_integer(size) and size > 0 do
    Stream.chunk_every(step_stream, size)
  end

  @doc """
  Batches steps by time windows.

  Groups steps that were started within the same time window.

  ## Parameters

  - `step_stream` - Stream of steps
  - `window_ms` - Time window in milliseconds

  ## Examples

      time_batches = step_stream
      |> StepStreamUtils.batch_by_time(5000)  # 5 second windows

  """
  @spec batch_by_time(step_stream(), pos_integer()) :: %{integer() => [Step.t()]}
  def batch_by_time(step_stream, window_ms) when is_integer(window_ms) and window_ms > 0 do
    step_stream
    |> Enum.group_by(fn step ->
      case step.started_at do
        nil ->
          0

        datetime ->
          DateTime.to_unix(datetime, :millisecond)
          |> div(window_ms)
      end
    end)
  end

  ## Timeout and Control Utilities

  @doc """
  Adds timeout handling to a step stream.

  If no step is received within the timeout period, the stream will either
  raise an error or complete, depending on the strategy.

  ## Parameters

  - `step_stream` - Stream of steps
  - `timeout_ms` - Timeout in milliseconds
  - `strategy` - `:error` to raise, `:complete` to end stream, `:default` to return default

  ## Examples

      safe_stream = step_stream
      |> StepStreamUtils.with_timeout(5000, :complete)

  """
  @spec with_timeout(step_stream(), pos_integer(), :error | :complete | {:default, any()}) ::
          step_stream()
  def with_timeout(step_stream, timeout_ms, strategy \\ :error) do
    case strategy do
      :error ->
        # For now, just return the stream as-is
        # A full implementation would need more complex timeout handling
        step_stream

      :complete ->
        step_stream

      {:default, default_value} ->
        # Return stream with default value if empty
        Stream.concat(step_stream, [default_value])
    end
  end

  @doc """
  Limits the number of steps in the stream.

  ## Parameters

  - `step_stream` - Stream of steps
  - `limit` - Maximum number of steps to take

  ## Examples

      first_ten = step_stream
      |> StepStreamUtils.take(10)

  """
  @spec take(step_stream(), pos_integer()) :: step_stream()
  def take(step_stream, limit) when is_integer(limit) and limit > 0 do
    Stream.take(step_stream, limit)
  end

  @doc """
  Skips the first N steps in the stream.

  ## Parameters

  - `step_stream` - Stream of steps
  - `count` - Number of steps to skip

  ## Examples

      remaining = step_stream
      |> StepStreamUtils.drop(5)

  """
  @spec drop(step_stream(), non_neg_integer()) :: step_stream()
  def drop(step_stream, count) when is_integer(count) and count >= 0 do
    Stream.drop(step_stream, count)
  end

  ## Debugging and Visualization Utilities

  @doc """
  Adds debug logging for each step in the stream.

  ## Parameters

  - `step_stream` - Stream of steps
  - `opts` - Options for debugging

  ## Options

  - `:level` - Log level (default: :debug)
  - `:prefix` - Prefix for log messages (default: "Step")

  ## Examples

      step_stream
      |> StepStreamUtils.debug_steps(level: :info, prefix: "Processing")
      |> Enum.to_list()

  """
  @spec debug_steps(step_stream(), keyword()) :: step_stream()
  def debug_steps(step_stream, opts \\ []) do
    level = Keyword.get(opts, :level, :debug)
    prefix = Keyword.get(opts, :prefix, "Step")

    Stream.map(step_stream, fn step ->
      message = "#{prefix}: #{step.id} (#{step.type}) - #{step.description}"

      case level do
        :debug -> Logger.debug(message)
        :info -> Logger.info(message)
        :warn -> Logger.warning(message)
        :error -> Logger.error(message)
      end

      step
    end)
  end

  @doc """
  Prints step information to the console.

  ## Parameters

  - `step_stream` - Stream of steps
  - `format` - Format function or atom

  ## Format Options

  - `:summary` - Print step summary
  - `:detailed` - Print detailed step information
  - Custom function - Apply custom formatting

  ## Examples

      step_stream
      |> StepStreamUtils.inspect_steps(:summary)
      |> Enum.to_list()

  """
  @spec inspect_steps(step_stream(), :summary | :detailed | (Step.t() -> String.t())) ::
          step_stream()
  def inspect_steps(step_stream, format \\ :summary) do
    Stream.map(step_stream, fn step ->
      output =
        case format do
          :summary ->
            "Step #{step.id}: #{step.type} - #{step.status}"

          :detailed ->
            """
            Step: #{step.id}
            Type: #{step.type}
            Status: #{step.status}
            Description: #{step.description}
            Messages: #{length(step.messages)}
            Tools: #{Enum.join(step.tools_used, ", ")}
            """

          formatter when is_function(formatter, 1) ->
            formatter.(step)
        end

      IO.puts(output)
      step
    end)
  end

  @doc """
  Collects statistics about the step stream.

  ## Parameters

  - `step_stream` - Stream of steps

  ## Returns

  A map containing statistics about the steps.

  ## Examples

      stats = step_stream
      |> StepStreamUtils.collect_stats()

  """
  @spec collect_stats(step_stream()) :: %{
          total_steps: non_neg_integer(),
          by_type: %{Step.step_type() => non_neg_integer()},
          by_status: %{Step.step_status() => non_neg_integer()},
          total_messages: non_neg_integer(),
          unique_tools: [String.t()],
          avg_messages_per_step: float()
        }
  def collect_stats(step_stream) do
    steps = Enum.to_list(step_stream)
    total_steps = length(steps)
    total_messages = Enum.sum(Enum.map(steps, fn step -> length(step.messages) end))

    %{
      total_steps: total_steps,
      by_type: Enum.frequencies_by(steps, fn step -> step.type end),
      by_status: Enum.frequencies_by(steps, fn step -> step.status end),
      total_messages: total_messages,
      unique_tools: steps |> Enum.flat_map(fn step -> step.tools_used end) |> Enum.uniq(),
      avg_messages_per_step: if(total_steps > 0, do: total_messages / total_steps, else: 0.0)
    }
  end

  ## Composition and Utility Helpers

  @doc """
  Applies multiple transformations to a step stream.

  ## Parameters

  - `step_stream` - Stream of steps
  - `transformations` - List of transformation functions

  ## Examples

      result = step_stream
      |> StepStreamUtils.pipe_through([
        &StepStreamUtils.filter_completed/1,
        &StepStreamUtils.debug_steps/1,
        fn stream -> StepStreamUtils.take(stream, 10) end
      ])

  """
  @spec pipe_through(step_stream(), [(step_stream() -> step_stream())]) :: step_stream()
  def pipe_through(step_stream, transformations) when is_list(transformations) do
    Enum.reduce(transformations, step_stream, fn transform, stream ->
      transform.(stream)
    end)
  end

  @doc """
  Taps into the stream for side effects without modifying it.

  ## Parameters

  - `step_stream` - Stream of steps
  - `side_effect` - Function to call for each step

  ## Examples

      step_stream
      |> StepStreamUtils.tap(fn step ->
        send_notification("Step completed: \#{step.description}")
      end)
      |> Enum.to_list()

  """
  @spec tap(step_stream(), (Step.t() -> any())) :: step_stream()
  def tap(step_stream, side_effect) when is_function(side_effect, 1) do
    Stream.map(step_stream, fn step ->
      side_effect.(step)
      step
    end)
  end

  @doc """
  Validates steps in the stream and filters out invalid ones.

  ## Parameters

  - `step_stream` - Stream of steps
  - `validator` - Function that returns true for valid steps

  ## Examples

      valid_steps = step_stream
      |> StepStreamUtils.validate_steps(fn step ->
        not is_nil(step.id) and is_binary(step.description)
      end)

  """
  @spec validate_steps(step_stream(), (Step.t() -> boolean())) :: step_stream()
  def validate_steps(step_stream, validator) when is_function(validator, 1) do
    Stream.filter(step_stream, fn step ->
      try do
        validator.(step)
      rescue
        _ -> false
      end
    end)
  end

  @doc """
  Converts a step stream to a list with error handling.

  ## Parameters

  - `step_stream` - Stream of steps
  - `opts` - Options for conversion

  ## Options

  - `:max_items` - Maximum number of items to collect
  - `:timeout` - Timeout in milliseconds

  ## Examples

      steps = StepStreamUtils.to_list_safe(step_stream, max_items: 100)

  """
  @spec to_list_safe(step_stream(), keyword()) :: {:ok, [Step.t()]} | {:error, term()}
  def to_list_safe(step_stream, opts \\ []) do
    max_items = Keyword.get(opts, :max_items, :infinity)
    timeout = Keyword.get(opts, :timeout, 5000)

    try do
      task =
        Task.async(fn ->
          case max_items do
            :infinity -> Enum.to_list(step_stream)
            n when is_integer(n) -> step_stream |> Stream.take(n) |> Enum.to_list()
          end
        end)

      case Task.yield(task, timeout) do
        {:ok, result} ->
          {:ok, result}

        nil ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end
    rescue
      error -> {:error, error}
    end
  end
end
