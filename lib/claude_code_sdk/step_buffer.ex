defmodule ClaudeCodeSDK.StepBuffer do
  @moduledoc """
  GenServer that buffers messages and emits complete steps with timeout handling.

  The StepBuffer accumulates messages until a complete step is detected, then emits
  the step to configured handlers. It provides memory management, timeout handling,
  and concurrent access safety for step processing.

  ## Features

  - Message buffering with configurable timeout
  - Step completion detection and emission
  - Memory management with configurable limits
  - Concurrent access handling
  - Error recovery and cleanup

  ## Configuration Options

  - `:buffer_timeout_ms` - Timeout for step completion (default: 5000)
  - `:max_buffer_size` - Maximum messages in buffer (default: 100)
  - `:max_memory_mb` - Maximum memory usage in MB (default: 50)
  - `:step_detector` - StepDetector instance for pattern matching
  - `:step_handler` - Function to handle completed steps
  - `:error_handler` - Function to handle errors

  ## Examples

      # Start buffer with default options
      {:ok, buffer} = ClaudeCodeSDK.StepBuffer.start_link([])

      # Add messages to buffer
      :ok = ClaudeCodeSDK.StepBuffer.add_message(buffer, message)

      # Flush incomplete steps
      :ok = ClaudeCodeSDK.StepBuffer.flush(buffer)

      # Get buffer status
      status = ClaudeCodeSDK.StepBuffer.get_status(buffer)

  """

  use GenServer
  require Logger

  alias ClaudeCodeSDK.{Message, Step, StepDetector}

  # Default configuration
  @default_buffer_timeout_ms 5000
  @default_max_buffer_size 100
  @default_max_memory_mb 50
  @default_step_handler &__MODULE__.default_step_handler/1
  @default_error_handler &__MODULE__.default_error_handler/2

  defstruct [
    # StepDetector instance
    :step_detector,
    # Function to handle completed steps
    :step_handler,
    # Function to handle errors
    :error_handler,
    # Timeout for step completion
    :buffer_timeout_ms,
    # Maximum messages in buffer
    :max_buffer_size,
    # Maximum memory usage in MB
    :max_memory_mb,
    # Current step being built
    :current_step,
    # List of buffered messages
    :message_buffer,
    # Timer reference for timeout
    :timeout_ref,
    # Buffer statistics
    :stats
  ]

  @type t :: %__MODULE__{
          step_detector: StepDetector.t(),
          step_handler: (Step.t() -> any()),
          error_handler: (term(), t() -> any()),
          buffer_timeout_ms: pos_integer(),
          max_buffer_size: pos_integer(),
          max_memory_mb: pos_integer(),
          current_step: Step.t() | nil,
          message_buffer: [Message.t()],
          timeout_ref: reference() | nil,
          stats: map()
        }

  @type buffer_status :: %{
          buffer_size: non_neg_integer(),
          memory_usage_mb: float(),
          current_step_id: String.t() | nil,
          steps_emitted: non_neg_integer(),
          timeouts: non_neg_integer(),
          errors: non_neg_integer()
        }

  ## Public API

  @doc """
  Starts the StepBuffer GenServer.

  ## Options

  - `:step_detector` - StepDetector instance (required)
  - `:step_handler` - Function to handle completed steps
  - `:error_handler` - Function to handle errors
  - `:buffer_timeout_ms` - Timeout for step completion
  - `:max_buffer_size` - Maximum messages in buffer
  - `:max_memory_mb` - Maximum memory usage in MB
  - `:name` - GenServer name for registration

  ## Examples

      {:ok, buffer} = ClaudeCodeSDK.StepBuffer.start_link(
        step_detector: detector,
        step_handler: &MyModule.handle_step/1
      )

  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Adds a message to the buffer for step processing.

  The message will be analyzed for step boundaries and either added to the current
  step or used to complete the current step and start a new one.

  ## Parameters

  - `buffer` - The buffer process PID or name
  - `message` - The message to add

  ## Returns

  `:ok` on success, `{:error, reason}` on failure.

  ## Examples

      message = %ClaudeCodeSDK.Message{type: :assistant, data: %{...}}
      :ok = ClaudeCodeSDK.StepBuffer.add_message(buffer, message)

  """
  @spec add_message(GenServer.server(), Message.t()) :: :ok | {:error, term()}
  def add_message(buffer, %Message{} = message) do
    GenServer.call(buffer, {:add_message, message})
  end

  @doc """
  Flushes any incomplete step from the buffer.

  This forces emission of the current step even if it's not complete, useful
  for cleanup or when ending a conversation.

  ## Parameters

  - `buffer` - The buffer process PID or name

  ## Returns

  `:ok` on success.

  ## Examples

      :ok = ClaudeCodeSDK.StepBuffer.flush(buffer)

  """
  @spec flush(GenServer.server()) :: :ok
  def flush(buffer) do
    GenServer.call(buffer, :flush)
  end

  @doc """
  Gets the current status of the buffer.

  ## Parameters

  - `buffer` - The buffer process PID or name

  ## Returns

  Map containing buffer status information.

  ## Examples

      status = ClaudeCodeSDK.StepBuffer.get_status(buffer)
      IO.puts("Buffer size: \#{status.buffer_size}")

  """
  @spec get_status(GenServer.server()) :: buffer_status()
  def get_status(buffer) do
    GenServer.call(buffer, :get_status)
  end

  @doc """
  Stops the buffer process gracefully.

  ## Parameters

  - `buffer` - The buffer process PID or name

  ## Returns

  `:ok`

  """
  @spec stop(GenServer.server()) :: :ok
  def stop(buffer) do
    GenServer.stop(buffer)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    step_detector = Keyword.get(opts, :step_detector)

    if is_nil(step_detector) do
      {:stop, {:error, :step_detector_required}}
    else
      state = %__MODULE__{
        step_detector: step_detector,
        step_handler: Keyword.get(opts, :step_handler, @default_step_handler),
        error_handler: Keyword.get(opts, :error_handler, @default_error_handler),
        buffer_timeout_ms: Keyword.get(opts, :buffer_timeout_ms, @default_buffer_timeout_ms),
        max_buffer_size: Keyword.get(opts, :max_buffer_size, @default_max_buffer_size),
        max_memory_mb: Keyword.get(opts, :max_memory_mb, @default_max_memory_mb),
        current_step: nil,
        message_buffer: [],
        timeout_ref: nil,
        stats: %{
          steps_emitted: 0,
          timeouts: 0,
          errors: 0,
          started_at: DateTime.utc_now()
        }
      }

      {:ok, state}
    end
  end

  @impl true
  def handle_call({:add_message, message}, _from, state) do
    case add_message_to_buffer(message, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = flush_current_step(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = build_status(state)
    {:reply, status, state}
  end

  @impl true
  def handle_info(:step_timeout, state) do
    Logger.debug("Step timeout occurred, flushing current step")

    new_state =
      state
      |> flush_current_step()
      |> update_stats(:timeouts, &(&1 + 1))

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message received: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("StepBuffer terminating: #{inspect(reason)}")

    # Cancel timeout if active
    if state.timeout_ref do
      Process.cancel_timer(state.timeout_ref)
    end

    # Flush any remaining step
    flush_current_step(state)

    :ok
  end

  ## Private Functions

  # Adds a message to the buffer and processes step detection
  defp add_message_to_buffer(message, state) do
    # Check memory limits first
    case check_memory_limits(state) do
      :ok ->
        process_message(message, state)

      {:error, reason} ->
        handle_memory_error(reason, state)
    end
  end

  # Processes a message through step detection
  defp process_message(message, state) do
    try do
      # Analyze message for step boundaries
      {detection_result, _updated_detector} =
        StepDetector.analyze_message(
          state.step_detector,
          message,
          state.message_buffer
        )

      # Process based on detection result
      case detection_result do
        {:step_start, step_type, metadata} ->
          handle_step_start(message, step_type, metadata, state)

        {:step_continue, _} ->
          handle_step_continue(message, state)

        {:step_end, step_metadata} ->
          handle_step_end(message, step_metadata, state)

        {:step_boundary, step_type, metadata} ->
          handle_step_boundary(message, step_type, metadata, state)
      end
    rescue
      error ->
        handle_detection_error(error, message, state)
    end
  end

  # Handles the start of a new step
  defp handle_step_start(message, step_type, metadata, state) do
    # If we have a current step, complete it first
    state = if state.current_step, do: emit_current_step(state), else: state

    # Create new step
    new_step =
      Step.new(
        type: step_type,
        description: Map.get(metadata, :description, ""),
        metadata: metadata
      )
      |> Step.add_message(message)

    # Update state with new step
    new_state = %{
      state
      | current_step: new_step,
        message_buffer: [message],
        timeout_ref: schedule_timeout(state.buffer_timeout_ms)
    }

    {:ok, new_state}
  end

  # Handles continuation of current step
  defp handle_step_continue(message, state) do
    case state.current_step do
      nil ->
        # No current step, start a new one
        handle_step_start(message, :unknown, %{}, state)

      current_step ->
        # Add message to current step
        updated_step = Step.add_message(current_step, message)
        updated_buffer = state.message_buffer ++ [message]

        # Check buffer size limits
        if length(updated_buffer) > state.max_buffer_size do
          # Force completion due to size limit
          new_state =
            %{state | current_step: updated_step, message_buffer: updated_buffer}
            |> emit_current_step()

          {:ok, new_state}
        else
          new_state = %{state | current_step: updated_step, message_buffer: updated_buffer}

          {:ok, new_state}
        end
    end
  end

  # Handles the end of current step
  defp handle_step_end(message, step_metadata, state) do
    case state.current_step do
      nil ->
        # No current step, treat as standalone message
        handle_step_start(message, :unknown, step_metadata, state)

      current_step ->
        # Complete current step with final message
        completed_step =
          current_step
          |> Step.add_message(message)
          |> Step.complete()
          |> Step.update_metadata(step_metadata)

        # Emit the completed step
        new_state =
          %{
            state
            | current_step: completed_step,
              message_buffer: state.message_buffer ++ [message]
          }
          |> emit_current_step()

        {:ok, new_state}
    end
  end

  # Handles step boundary (end current, start new)
  defp handle_step_boundary(message, new_step_type, metadata, state) do
    # Complete current step if exists
    state = if state.current_step, do: emit_current_step(state), else: state

    # Start new step
    handle_step_start(message, new_step_type, metadata, state)
  end

  # Handles detection errors
  defp handle_detection_error(error, message, state) do
    Logger.warning("Step detection error: #{inspect(error)}")

    # Fall back to continuing current step or starting new one
    case state.current_step do
      nil ->
        handle_step_start(message, :unknown, %{error: error}, state)

      _current_step ->
        handle_step_continue(message, state)
    end
  end

  # Emits the current step and resets buffer state
  defp emit_current_step(state) do
    case state.current_step do
      nil ->
        state

      step ->
        # Cancel timeout
        if state.timeout_ref do
          Process.cancel_timer(state.timeout_ref)
        end

        # Emit step to handler
        try do
          state.step_handler.(step)
        rescue
          error ->
            Logger.error("Step handler error: #{inspect(error)}")
            state.error_handler.(error, state)
        end

        # Reset buffer state
        %{
          state
          | current_step: nil,
            message_buffer: [],
            timeout_ref: nil,
            stats: update_in(state.stats, [:steps_emitted], &(&1 + 1))
        }
    end
  end

  # Flushes current step (forces completion)
  defp flush_current_step(state) do
    case state.current_step do
      nil ->
        state

      step ->
        # Mark step as timeout and emit
        timeout_step = Step.timeout(step)

        new_state = %{state | current_step: timeout_step}
        emit_current_step(new_state)
    end
  end

  # Schedules a timeout for step completion
  defp schedule_timeout(timeout_ms) do
    Process.send_after(self(), :step_timeout, timeout_ms)
  end

  # Checks memory usage limits
  defp check_memory_limits(state) do
    memory_mb = calculate_memory_usage(state)

    if memory_mb > state.max_memory_mb do
      {:error, {:memory_limit_exceeded, memory_mb, state.max_memory_mb}}
    else
      :ok
    end
  end

  # Calculates approximate memory usage in MB
  defp calculate_memory_usage(state) do
    # Rough estimation based on buffer size and step data
    buffer_size = length(state.message_buffer)
    step_size = if state.current_step, do: length(state.current_step.messages), else: 0

    # Estimate ~1KB per message on average
    estimated_bytes = (buffer_size + step_size) * 1024
    # Convert to MB
    estimated_bytes / (1024 * 1024)
  end

  # Handles memory limit errors
  defp handle_memory_error(reason, state) do
    Logger.warning("Memory limit error: #{inspect(reason)}")

    # Call error handler
    try do
      state.error_handler.(reason, state)
    rescue
      error ->
        Logger.error("Error handler failed: #{inspect(error)}")
    end

    # Force flush current step to free memory
    new_state =
      flush_current_step(state)
      |> update_stats(:errors, &(&1 + 1))

    {:error, reason, new_state}
  end

  # Builds status information
  defp build_status(state) do
    %{
      buffer_size: length(state.message_buffer),
      memory_usage_mb: calculate_memory_usage(state),
      current_step_id: if(state.current_step, do: state.current_step.id, else: nil),
      steps_emitted: state.stats.steps_emitted,
      timeouts: state.stats.timeouts,
      errors: state.stats.errors,
      uptime_ms: DateTime.diff(DateTime.utc_now(), state.stats.started_at, :millisecond)
    }
  end

  # Updates statistics
  defp update_stats(state, key, update_fn) do
    %{state | stats: update_in(state.stats, [key], update_fn)}
  end

  ## Default Handlers

  @doc """
  Default step handler that logs completed steps.
  """
  def default_step_handler(step) do
    Logger.info("Step completed: #{step.id} (#{step.type}) - #{step.description}")
  end

  @doc """
  Default error handler that logs errors.
  """
  def default_error_handler(error, _state) do
    Logger.error("StepBuffer error: #{inspect(error)}")
  end
end
