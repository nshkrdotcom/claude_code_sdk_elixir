defmodule ClaudeCodeSDK.StepController do
  @moduledoc """
  GenServer that manages step execution flow with pause/resume capabilities.

  The StepController provides control over step execution with three modes:
  - `:automatic` - Steps execute without interruption
  - `:manual` - Pause after each step for user decision
  - `:review_required` - Pause for external review handler approval

  ## Features

  - Automatic, manual, and review_required control modes
  - Pause/resume functionality with decision handling
  - Intervention injection and processing
  - Control timeouts and error scenarios
  - Integration with external review systems

  ## Configuration Options

  - `:control_mode` - Control mode (default: :automatic)
  - `:review_handler` - Module implementing review behavior
  - `:intervention_handler` - Function to handle interventions
  - `:control_timeout_ms` - Timeout for control decisions (default: 30000)
  - `:pause_between_steps` - Whether to pause between steps (default: false)

  ## Examples

      # Start controller with automatic mode
      {:ok, controller} = ClaudeCodeSDK.StepController.start_link(
        step_stream,
        control_mode: :automatic
      )

      # Get next step
      {:ok, step} = ClaudeCodeSDK.StepController.next_step(controller)

      # Manual control
      {:ok, controller} = ClaudeCodeSDK.StepController.start_link(
        step_stream,
        control_mode: :manual
      )
      
      {:paused, step} = ClaudeCodeSDK.StepController.next_step(controller)
      :ok = ClaudeCodeSDK.StepController.resume(controller, :continue)

  """

  use GenServer
  require Logger

  alias ClaudeCodeSDK.Step

  # Default configuration
  @default_control_mode :automatic
  @default_control_timeout_ms 30_000
  @default_pause_between_steps false

  defstruct [
    # Stream of steps to process
    :step_stream,
    # Current control mode
    :control_mode,
    # Review handler module
    :review_handler,
    # Intervention handler function
    :intervention_handler,
    # Timeout for control decisions
    :control_timeout_ms,
    # Whether to pause between steps
    :pause_between_steps,
    # Current step being processed
    :current_step,
    # Stream state
    :stream_state,
    # Control state
    :control_state,
    # Pending decision
    :pending_decision,
    # Timer reference for timeouts
    :timeout_ref,
    # Controller statistics
    :stats
  ]

  @type control_mode :: :automatic | :manual | :review_required

  @type control_decision ::
          :continue
          | :pause
          | {:intervene, intervention()}
          | :abort
          | :skip

  @type intervention :: %{
          type: :guidance | :correction | :context,
          content: String.t(),
          metadata: map()
        }

  @type control_state ::
          :running
          | :paused
          | :waiting_review
          | :waiting_decision
          | :completed
          | :aborted
          | :error

  @type step_result ::
          {:ok, Step.t()}
          | {:paused, Step.t()}
          | {:waiting_review, Step.t()}
          | :completed
          | {:error, term()}

  @type t :: %__MODULE__{
          step_stream: Enumerable.t(),
          control_mode: control_mode(),
          review_handler: module() | nil,
          intervention_handler: (intervention(), Step.t() -> Step.t()) | nil,
          control_timeout_ms: pos_integer(),
          pause_between_steps: boolean(),
          current_step: Step.t() | nil,
          stream_state: any(),
          control_state: control_state(),
          pending_decision: control_decision() | nil,
          timeout_ref: reference() | nil,
          stats: map()
        }

  ## Public API

  @doc """
  Starts the StepController GenServer.

  ## Parameters

  - `step_stream` - Enumerable of steps to process
  - `opts` - Keyword list of options

  ## Options

  - `:control_mode` - Control mode (:automatic, :manual, :review_required)
  - `:review_handler` - Module implementing review behavior
  - `:intervention_handler` - Function to handle interventions
  - `:control_timeout_ms` - Timeout for control decisions
  - `:pause_between_steps` - Whether to pause between steps
  - `:name` - GenServer name for registration

  ## Examples

      {:ok, controller} = ClaudeCodeSDK.StepController.start_link(
        step_stream,
        control_mode: :manual,
        review_handler: MyApp.StepReviewer
      )

  """
  @spec start_link(Enumerable.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(step_stream, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    init_args = {step_stream, opts}

    if name do
      GenServer.start_link(__MODULE__, init_args, name: name)
    else
      GenServer.start_link(__MODULE__, init_args)
    end
  end

  @doc """
  Gets the next step from the controller.

  Depending on the control mode, this may return immediately with a step,
  or return a paused step that requires a decision to continue.

  ## Parameters

  - `controller` - The controller process PID or name
  - `timeout` - Timeout for the operation (default: 5000ms)

  ## Returns

  - `{:ok, step}` - Step completed successfully
  - `{:paused, step}` - Step paused, waiting for decision
  - `{:waiting_review, step}` - Step waiting for review approval
  - `:completed` - All steps processed
  - `{:error, reason}` - Error occurred

  ## Examples

      case ClaudeCodeSDK.StepController.next_step(controller) do
        {:ok, step} -> 
          IO.puts("Step completed: \#{step.description}")
        {:paused, step} -> 
          IO.puts("Step paused: \#{step.description}")
          # Make decision...
        :completed -> 
          IO.puts("All steps completed")
      end

  """
  @spec next_step(GenServer.server(), timeout()) :: step_result()
  def next_step(controller, timeout \\ 5000) do
    GenServer.call(controller, :next_step, timeout)
  end

  @doc """
  Resumes execution with the given decision.

  Used when a step is paused and requires a decision to continue.

  ## Parameters

  - `controller` - The controller process PID or name
  - `decision` - The control decision to apply

  ## Control Decisions

  - `:continue` - Continue with the current step
  - `:pause` - Keep the step paused
  - `:skip` - Skip the current step and move to next
  - `:abort` - Abort all processing
  - `{:intervene, intervention}` - Apply intervention and continue

  ## Examples

      # Continue normally
      :ok = ClaudeCodeSDK.StepController.resume(controller, :continue)

      # Apply intervention
      intervention = %{
        type: :guidance,
        content: "Be more careful with file operations",
        metadata: %{}
      }
      :ok = ClaudeCodeSDK.StepController.resume(controller, {:intervene, intervention})

  """
  @spec resume(GenServer.server(), control_decision()) :: :ok | {:error, term()}
  def resume(controller, decision \\ :continue) do
    GenServer.call(controller, {:resume, decision})
  end

  @doc """
  Gets the current status of the controller.

  ## Parameters

  - `controller` - The controller process PID or name

  ## Returns

  Map containing controller status information.

  """
  @spec get_status(GenServer.server()) :: map()
  def get_status(controller) do
    GenServer.call(controller, :get_status)
  end

  @doc """
  Stops the controller gracefully.

  ## Parameters

  - `controller` - The controller process PID or name

  ## Returns

  `:ok`

  """
  @spec stop(GenServer.server()) :: :ok
  def stop(controller) do
    GenServer.stop(controller)
  end

  ## GenServer Callbacks

  @impl true
  def init({step_stream, opts}) do
    state = %__MODULE__{
      step_stream: step_stream,
      control_mode: Keyword.get(opts, :control_mode, @default_control_mode),
      review_handler: Keyword.get(opts, :review_handler),
      intervention_handler: Keyword.get(opts, :intervention_handler),
      control_timeout_ms: Keyword.get(opts, :control_timeout_ms, @default_control_timeout_ms),
      pause_between_steps: Keyword.get(opts, :pause_between_steps, @default_pause_between_steps),
      current_step: nil,
      stream_state: nil,
      control_state: :running,
      pending_decision: nil,
      timeout_ref: nil,
      stats: %{
        steps_processed: 0,
        steps_paused: 0,
        steps_reviewed: 0,
        interventions_applied: 0,
        errors: 0,
        started_at: DateTime.utc_now()
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:next_step, from, state) do
    case state.control_state do
      :paused ->
        {:reply, {:paused, state.current_step}, state}

      :waiting_review ->
        {:reply, {:waiting_review, state.current_step}, state}

      :waiting_decision ->
        {:reply, {:paused, state.current_step}, state}

      :completed ->
        {:reply, :completed, state}

      :aborted ->
        {:reply, {:error, :aborted}, state}

      :error ->
        {:reply, {:error, :controller_error}, state}

      :running ->
        # Check if we have a completed current step to return
        case state.current_step do
          %Step{status: status} when status in [:completed, :aborted] ->
            # Return the completed step and prepare for next
            {:reply, {:ok, state.current_step}, %{state | current_step: nil}}

          nil ->
            # No current step, get next from stream
            process_next_step(from, state)

          _ ->
            # Have current step but not completed, process it
            process_next_step(from, state)
        end
    end
  end

  @impl true
  def handle_call({:resume, decision}, _from, state) do
    case apply_control_decision(decision, state) do
      {:ok, new_state} ->
        # If we're now in running state, immediately process the next step
        case new_state.control_state do
          :running ->
            # Process the current step or get next one
            case new_state.current_step do
              %Step{status: :completed} ->
                {:reply, :ok, new_state}

              %Step{status: :aborted} ->
                {:reply, :ok, new_state}

              _ ->
                # Complete the current step and continue
                completed_step = Step.complete(new_state.current_step)
                final_state = %{new_state | current_step: completed_step}
                {:reply, :ok, final_state}
            end

          _ ->
            {:reply, :ok, new_state}
        end

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = build_status(state)
    {:reply, status, state}
  end

  @impl true
  def handle_info(:control_timeout, state) do
    Logger.warning("Control timeout occurred")

    new_state = handle_control_timeout(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:review_result, step_id, result}, state) do
    case state.current_step do
      %Step{id: ^step_id} ->
        new_state = handle_review_result(result, state)
        {:noreply, new_state}

      _ ->
        Logger.warning("Received review result for unknown step: #{step_id}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message received: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("StepController terminating: #{inspect(reason)}")

    # Cancel timeout if active
    if state.timeout_ref do
      Process.cancel_timer(state.timeout_ref)
    end

    :ok
  end

  ## Private Functions

  # Processes the next step from the stream
  defp process_next_step(from, state) do
    case get_next_step_from_stream(state) do
      {:ok, step, new_stream_state} ->
        new_state = %{
          state
          | current_step: step,
            stream_state: new_stream_state,
            stats: update_in(state.stats, [:steps_processed], &(&1 + 1))
        }

        handle_step_control(step, from, new_state)

      :completed ->
        new_state = %{state | control_state: :completed}
        {:reply, :completed, new_state}

      {:error, reason} ->
        Logger.error("Error getting next step: #{inspect(reason)}")

        new_state = %{
          state
          | control_state: :error,
            stats: update_in(state.stats, [:errors], &(&1 + 1))
        }

        {:reply, {:error, reason}, new_state}
    end
  end

  # Gets the next step from the stream
  defp get_next_step_from_stream(state) do
    try do
      case state.stream_state do
        nil ->
          # First time - initialize stream state
          case Enum.take(state.step_stream, 1) do
            [] ->
              :completed

            [step] ->
              remaining_stream = Stream.drop(state.step_stream, 1)
              {:ok, step, remaining_stream}
          end

        stream_state ->
          # Use existing stream state
          case Enum.take(stream_state, 1) do
            [] ->
              :completed

            [step] ->
              remaining_stream = Stream.drop(stream_state, 1)
              {:ok, step, remaining_stream}
          end
      end
    rescue
      error ->
        {:error, error}
    end
  end

  # Handles step control based on mode and configuration
  defp handle_step_control(step, from, state) do
    case state.control_mode do
      :automatic ->
        handle_automatic_mode(step, from, state)

      :manual ->
        handle_manual_mode(step, from, state)

      :review_required ->
        handle_review_required_mode(step, from, state)
    end
  end

  # Handles automatic mode - steps execute without interruption
  defp handle_automatic_mode(step, _from, state) do
    if state.pause_between_steps do
      # Pause for user acknowledgment
      new_state = %{
        state
        | control_state: :paused,
          stats: update_in(state.stats, [:steps_paused], &(&1 + 1))
      }

      {:reply, {:paused, step}, new_state}
    else
      # Execute immediately
      completed_step = Step.complete(step)
      # Clear current step so next call gets next from stream
      new_state = %{state | current_step: nil}
      {:reply, {:ok, completed_step}, new_state}
    end
  end

  # Handles manual mode - pause after each step for user decision
  defp handle_manual_mode(step, _from, state) do
    new_state = %{
      state
      | control_state: :waiting_decision,
        timeout_ref: schedule_control_timeout(state.control_timeout_ms),
        stats: update_in(state.stats, [:steps_paused], &(&1 + 1))
    }

    {:reply, {:paused, step}, new_state}
  end

  # Handles review required mode - pause for external review handler approval
  defp handle_review_required_mode(step, from, state) do
    case state.review_handler do
      nil ->
        Logger.warning("Review required but no review handler configured, defaulting to pause")
        handle_manual_mode(step, from, state)

      review_handler ->
        # Set step to pending review
        review_step = Step.set_review_status(step, :pending)

        # Start async review process
        start_async_review(review_handler, review_step, state)

        new_state = %{
          state
          | current_step: review_step,
            control_state: :waiting_review,
            timeout_ref: schedule_control_timeout(state.control_timeout_ms),
            stats: update_in(state.stats, [:steps_reviewed], &(&1 + 1))
        }

        {:reply, {:waiting_review, review_step}, new_state}
    end
  end

  # Applies a control decision
  defp apply_control_decision(decision, state) do
    # Cancel any active timeout
    if state.timeout_ref do
      Process.cancel_timer(state.timeout_ref)
    end

    case decision do
      :continue ->
        handle_continue_decision(state)

      :pause ->
        handle_pause_decision(state)

      :skip ->
        handle_skip_decision(state)

      :abort ->
        handle_abort_decision(state)

      {:intervene, intervention} ->
        handle_intervention_decision(intervention, state)

      _ ->
        {:error, {:invalid_decision, decision}, state}
    end
  end

  # Handles continue decision
  defp handle_continue_decision(state) do
    case state.current_step do
      nil ->
        {:error, :no_current_step, state}

      step ->
        completed_step = Step.complete(step)

        new_state = %{
          state
          | current_step: completed_step,
            control_state: :running,
            timeout_ref: nil,
            pending_decision: nil
        }

        {:ok, new_state}
    end
  end

  # Handles pause decision
  defp handle_pause_decision(state) do
    new_state = %{state | control_state: :paused, timeout_ref: nil}
    {:ok, new_state}
  end

  # Handles skip decision
  defp handle_skip_decision(state) do
    case state.current_step do
      nil ->
        {:error, :no_current_step, state}

      step ->
        # Mark step as aborted and move to next
        aborted_step = Step.abort(step)

        new_state = %{
          state
          | current_step: aborted_step,
            control_state: :running,
            timeout_ref: nil,
            pending_decision: nil
        }

        {:ok, new_state}
    end
  end

  # Handles abort decision
  defp handle_abort_decision(state) do
    new_state = %{state | control_state: :aborted, timeout_ref: nil}
    {:ok, new_state}
  end

  # Handles intervention decision
  defp handle_intervention_decision(intervention, state) do
    case state.current_step do
      nil ->
        {:error, :no_current_step, state}

      step ->
        # Apply intervention to step
        updated_step = apply_intervention(intervention, step, state)

        new_state = %{
          state
          | current_step: updated_step,
            control_state: :running,
            timeout_ref: nil,
            pending_decision: nil,
            stats: update_in(state.stats, [:interventions_applied], &(&1 + 1))
        }

        {:ok, new_state}
    end
  end

  # Applies an intervention to a step
  defp apply_intervention(intervention, step, state) do
    # Add intervention to step
    step_with_intervention =
      Step.add_intervention(step, Map.put(intervention, :applied_at, DateTime.utc_now()))

    # Apply intervention handler if configured
    case state.intervention_handler do
      nil ->
        step_with_intervention

      handler when is_function(handler, 2) ->
        try do
          handler.(intervention, step_with_intervention)
        rescue
          error ->
            Logger.error("Intervention handler error: #{inspect(error)}")
            step_with_intervention
        end

      _ ->
        Logger.warning("Invalid intervention handler configured")
        step_with_intervention
    end
  end

  # Starts async review process
  defp start_async_review(review_handler, step, _state) do
    controller_pid = self()

    Task.start(fn ->
      try do
        result = review_handler.review_step(step)
        send(controller_pid, {:review_result, step.id, result})
      rescue
        error ->
          Logger.error("Review handler error: #{inspect(error)}")
          send(controller_pid, {:review_result, step.id, {:error, error}})
      end
    end)
  end

  # Handles review result
  defp handle_review_result(result, state) do
    case result do
      :approved ->
        # Continue with approved step - complete it
        approved_step =
          state.current_step
          |> Step.set_review_status(:approved)
          |> Step.complete()

        %{state | current_step: approved_step, control_state: :running, timeout_ref: nil}

      :rejected ->
        # Skip rejected step
        rejected_step =
          state.current_step
          |> Step.set_review_status(:rejected)
          |> Step.abort()

        %{state | current_step: rejected_step, control_state: :running, timeout_ref: nil}

      {:error, error} ->
        Logger.error("Review error: #{inspect(error)}")
        handle_review_error(error, state)

      _ ->
        Logger.warning("Unknown review result: #{inspect(result)}")
        handle_review_error({:unknown_result, result}, state)
    end
  end

  # Handles review errors
  defp handle_review_error(_error, state) do
    # Default to safe behavior based on control mode
    case state.control_mode do
      :review_required ->
        # Pause for manual decision
        %{
          state
          | control_state: :paused,
            timeout_ref: nil,
            stats: update_in(state.stats, [:errors], &(&1 + 1))
        }

      _ ->
        # Continue with error logged
        %{
          state
          | control_state: :running,
            timeout_ref: nil,
            stats: update_in(state.stats, [:errors], &(&1 + 1))
        }
    end
  end

  # Handles control timeout
  defp handle_control_timeout(state) do
    Logger.warning("Control timeout in state: #{state.control_state}")

    case state.control_state do
      :waiting_review ->
        # Default to rejection on review timeout
        handle_review_result(:rejected, state)

      :waiting_decision ->
        # Default to pause on decision timeout
        %{state | control_state: :paused, timeout_ref: nil}

      _ ->
        state
    end
  end

  # Schedules a control timeout
  defp schedule_control_timeout(timeout_ms) do
    Process.send_after(self(), :control_timeout, timeout_ms)
  end

  # Builds status information
  defp build_status(state) do
    %{
      control_mode: state.control_mode,
      control_state: state.control_state,
      current_step_id: if(state.current_step, do: state.current_step.id, else: nil),
      current_step_type: if(state.current_step, do: state.current_step.type, else: nil),
      pending_decision: state.pending_decision,
      has_timeout: not is_nil(state.timeout_ref),
      stats: state.stats,
      uptime_ms: DateTime.diff(DateTime.utc_now(), state.stats.started_at, :millisecond)
    }
  end
end
