defmodule ClaudeCodeSDK.StateManager do
  @moduledoc """
  GenServer for managing conversation state and step history with persistence.

  The StateManager provides:
  - Step history tracking and persistence
  - Checkpoint creation and restoration
  - Configurable persistence adapters (memory, file, database)
  - State corruption detection and recovery
  - Conversation replay capabilities

  ## Usage

      # Start with default memory persistence
      {:ok, pid} = ClaudeCodeSDK.StateManager.start_link()

      # Start with file persistence
      {:ok, pid} = ClaudeCodeSDK.StateManager.start_link(
        persistence_adapter: ClaudeCodeSDK.StateManager.FilePersistence,
        persistence_config: %{file_path: "/tmp/conversation_state.json"}
      )

      # Save a step
      :ok = ClaudeCodeSDK.StateManager.save_step(pid, step)

      # Create a checkpoint
      {:ok, checkpoint_id} = ClaudeCodeSDK.StateManager.create_checkpoint(pid, "before_refactor")

      # Restore from checkpoint
      :ok = ClaudeCodeSDK.StateManager.restore_checkpoint(pid, checkpoint_id)

  ## Configuration

  - `:persistence_adapter` - Module implementing persistence behavior (default: MemoryPersistence)
  - `:persistence_config` - Configuration passed to the persistence adapter
  - `:max_step_history` - Maximum number of steps to keep in history (default: 100)
  - `:auto_checkpoint_interval` - Automatic checkpoint interval in steps (default: 10)
  - `:enable_recovery` - Enable automatic recovery on corruption (default: true)

  """

  use GenServer
  require Logger

  alias ClaudeCodeSDK.Step
  alias ClaudeCodeSDK.StateManager.MemoryPersistence

  @default_max_history 100
  @default_checkpoint_interval 10

  defstruct [
    :persistence_adapter,
    :persistence_config,
    :persistence_state,
    :step_history,
    :checkpoints,
    :conversation_id,
    :max_step_history,
    :auto_checkpoint_interval,
    :step_count_since_checkpoint,
    :enable_recovery
  ]

  @type checkpoint :: %{
          id: String.t(),
          label: String.t(),
          created_at: DateTime.t(),
          step_count: integer(),
          conversation_state: map()
        }

  @type state :: %__MODULE__{
          persistence_adapter: module(),
          persistence_config: map(),
          persistence_state: term(),
          step_history: [Step.t()],
          checkpoints: [checkpoint()],
          conversation_id: String.t(),
          max_step_history: integer(),
          auto_checkpoint_interval: integer(),
          step_count_since_checkpoint: integer(),
          enable_recovery: boolean()
        }

  ## Public API

  @doc """
  Starts the StateManager GenServer.

  ## Options

  - `:name` - Process name for registration
  - `:persistence_adapter` - Persistence adapter module
  - `:persistence_config` - Configuration for persistence adapter
  - `:max_step_history` - Maximum steps to keep in history
  - `:auto_checkpoint_interval` - Steps between automatic checkpoints
  - `:enable_recovery` - Enable automatic recovery on corruption
  - `:conversation_id` - Unique conversation identifier

  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Saves a step to the history and triggers persistence.

  ## Parameters

  - `manager` - StateManager process pid or name
  - `step` - Step struct to save

  ## Returns

  `:ok` on success, `{:error, reason}` on failure.

  """
  @spec save_step(pid() | atom(), Step.t()) :: :ok | {:error, term()}
  def save_step(manager, %Step{} = step) do
    GenServer.call(manager, {:save_step, step})
  end

  @doc """
  Creates a checkpoint with the current state.

  ## Parameters

  - `manager` - StateManager process pid or name
  - `label` - Human-readable checkpoint label

  ## Returns

  `{:ok, checkpoint_id}` on success, `{:error, reason}` on failure.

  """
  @spec create_checkpoint(pid() | atom(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def create_checkpoint(manager, label) when is_binary(label) do
    GenServer.call(manager, {:create_checkpoint, label})
  end

  @doc """
  Restores state from a checkpoint.

  ## Parameters

  - `manager` - StateManager process pid or name
  - `checkpoint_id` - ID of the checkpoint to restore

  ## Returns

  `:ok` on success, `{:error, reason}` on failure.

  """
  @spec restore_checkpoint(pid() | atom(), String.t()) :: :ok | {:error, term()}
  def restore_checkpoint(manager, checkpoint_id) when is_binary(checkpoint_id) do
    GenServer.call(manager, {:restore_checkpoint, checkpoint_id})
  end

  @doc """
  Gets the current step history.

  ## Parameters

  - `manager` - StateManager process pid or name

  ## Returns

  List of steps in chronological order.

  """
  @spec get_step_history(pid() | atom()) :: [Step.t()]
  def get_step_history(manager) do
    GenServer.call(manager, :get_step_history)
  end

  @doc """
  Gets all available checkpoints.

  ## Parameters

  - `manager` - StateManager process pid or name

  ## Returns

  List of checkpoint metadata.

  """
  @spec get_checkpoints(pid() | atom()) :: [checkpoint()]
  def get_checkpoints(manager) do
    GenServer.call(manager, :get_checkpoints)
  end

  @doc """
  Clears all history and checkpoints.

  ## Parameters

  - `manager` - StateManager process pid or name

  ## Returns

  `:ok` on success.

  """
  @spec clear_history(pid() | atom()) :: :ok
  def clear_history(manager) do
    GenServer.call(manager, :clear_history)
  end

  @doc """
  Gets conversation replay data for debugging.

  ## Parameters

  - `manager` - StateManager process pid or name
  - `opts` - Replay options

  ## Options

  - `:from_checkpoint` - Start replay from specific checkpoint
  - `:step_limit` - Maximum number of steps to include

  ## Returns

  Map containing replay data.

  """
  @spec get_conversation_replay(pid() | atom(), keyword()) :: map()
  def get_conversation_replay(manager, opts \\ []) do
    GenServer.call(manager, {:get_conversation_replay, opts})
  end

  @doc """
  Manually triggers history pruning.

  ## Parameters

  - `manager` - StateManager process pid or name
  - `opts` - Pruning options

  ## Options

  - `:preserve_checkpoints` - Whether to preserve steps referenced by checkpoints (default: true)
  - `:target_size` - Target history size after pruning (default: max_step_history / 2)

  ## Returns

  `{:ok, pruned_count}` on success, `{:error, reason}` on failure.

  """
  @spec prune_history(pid() | atom(), keyword()) :: {:ok, integer()} | {:error, term()}
  def prune_history(manager, opts \\ []) do
    GenServer.call(manager, {:prune_history, opts})
  end

  @doc """
  Gets history statistics.

  ## Parameters

  - `manager` - StateManager process pid or name

  ## Returns

  Map containing history statistics.

  """
  @spec get_history_stats(pid() | atom()) :: map()
  def get_history_stats(manager) do
    GenServer.call(manager, :get_history_stats)
  end

  @doc """
  Replays conversation from a specific checkpoint or step.

  ## Parameters

  - `manager` - StateManager process pid or name
  - `opts` - Replay options

  ## Options

  - `:from_checkpoint` - Checkpoint ID to start replay from
  - `:from_step` - Step ID to start replay from
  - `:to_step` - Step ID to end replay at
  - `:include_metadata` - Whether to include step metadata (default: false)

  ## Returns

  `{:ok, replay_stream}` on success, `{:error, reason}` on failure.

  """
  @spec replay_conversation(pid() | atom(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def replay_conversation(manager, opts \\ []) do
    GenServer.call(manager, {:replay_conversation, opts})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    adapter = Keyword.get(opts, :persistence_adapter, MemoryPersistence)
    config = Keyword.get(opts, :persistence_config, %{})
    conversation_id = Keyword.get(opts, :conversation_id, generate_conversation_id())

    state = %__MODULE__{
      persistence_adapter: adapter,
      persistence_config: config,
      step_history: [],
      checkpoints: [],
      conversation_id: conversation_id,
      max_step_history: Keyword.get(opts, :max_step_history, @default_max_history),
      auto_checkpoint_interval:
        Keyword.get(opts, :auto_checkpoint_interval, @default_checkpoint_interval),
      step_count_since_checkpoint: 0,
      enable_recovery: Keyword.get(opts, :enable_recovery, true)
    }

    case initialize_persistence(state) do
      {:ok, new_state} ->
        Logger.info("StateManager started for conversation #{conversation_id}")
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to initialize StateManager persistence: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:save_step, step}, _from, state) do
    case do_save_step(step, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to save step #{step.id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:create_checkpoint, label}, _from, state) do
    case do_create_checkpoint(label, state) do
      {:ok, checkpoint_id, new_state} ->
        {:reply, {:ok, checkpoint_id}, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to create checkpoint '#{label}': #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:restore_checkpoint, checkpoint_id}, _from, state) do
    case do_restore_checkpoint(checkpoint_id, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to restore checkpoint #{checkpoint_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call(:get_step_history, _from, state) do
    {:reply, state.step_history, state}
  end

  def handle_call(:get_checkpoints, _from, state) do
    {:reply, state.checkpoints, state}
  end

  def handle_call(:clear_history, _from, state) do
    case do_clear_history(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to clear history: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_conversation_replay, opts}, _from, state) do
    replay_data = build_conversation_replay(state, opts)
    {:reply, replay_data, state}
  end

  def handle_call({:prune_history, opts}, _from, state) do
    case do_prune_history(state, opts) do
      {:ok, pruned_count, new_state} ->
        {:reply, {:ok, pruned_count}, new_state}

      {:error, reason} ->
        Logger.error("Failed to prune history: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_history_stats, _from, state) do
    stats = build_history_stats(state)
    {:reply, stats, state}
  end

  def handle_call({:replay_conversation, opts}, _from, state) do
    case build_conversation_replay_stream(state, opts) do
      {:ok, replay_stream} ->
        {:reply, {:ok, replay_stream}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:auto_checkpoint, state) do
    case do_create_checkpoint("auto_checkpoint_#{System.system_time(:second)}", state) do
      {:ok, _checkpoint_id, new_state} ->
        schedule_auto_checkpoint(new_state)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Auto checkpoint failed: #{inspect(reason)}")
        schedule_auto_checkpoint(state)
        {:noreply, state}
    end
  end

  ## Private Implementation

  defp initialize_persistence(state) do
    adapter = state.persistence_adapter
    config = state.persistence_config

    case adapter.init(config) do
      {:ok, persistence_state} ->
        new_state = %{state | persistence_state: persistence_state}

        # Try to load existing state
        case load_existing_state(new_state) do
          {:ok, loaded_state} ->
            {:ok, loaded_state}

          {:error, :not_found} ->
            {:ok, new_state}

          {:error, reason} when state.enable_recovery ->
            Logger.warning("State corruption detected, starting fresh: #{inspect(reason)}")
            {:ok, new_state}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_existing_state(state) do
    adapter = state.persistence_adapter
    conversation_id = state.conversation_id

    case adapter.load_conversation(state.persistence_state, conversation_id) do
      {:ok, data} ->
        {:ok, restore_state_from_data(state, data)}

      error ->
        error
    end
  end

  defp restore_state_from_data(state, data) do
    %{
      state
      | step_history: Map.get(data, :step_history, []),
        checkpoints: Map.get(data, :checkpoints, []),
        step_count_since_checkpoint: Map.get(data, :step_count_since_checkpoint, 0)
    }
  end

  defp do_save_step(step, state) do
    # Add step to history
    new_history = add_step_to_history(step, state.step_history, state.max_step_history)
    new_step_count = state.step_count_since_checkpoint + 1

    new_state = %{state | step_history: new_history, step_count_since_checkpoint: new_step_count}

    # Persist the updated state
    case persist_state(new_state) do
      :ok ->
        # Check if auto checkpoint is needed
        final_state = maybe_schedule_auto_checkpoint(new_state)
        {:ok, final_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_step_to_history(step, history, max_history) do
    new_history = history ++ [step]

    if length(new_history) > max_history do
      # Trigger automatic pruning
      {:ok, pruned_history} = prune_history_internal(new_history, max_history, [], true)
      pruned_history
    else
      new_history
    end
  end

  defp do_prune_history(state, opts) do
    preserve_checkpoints = Keyword.get(opts, :preserve_checkpoints, true)
    target_size = Keyword.get(opts, :target_size, div(state.max_step_history, 2))

    current_size = length(state.step_history)

    if current_size <= target_size do
      {:ok, 0, state}
    else
      {:ok, pruned_history} =
        prune_history_internal(
          state.step_history,
          target_size,
          state.checkpoints,
          preserve_checkpoints
        )

      pruned_count = current_size - length(pruned_history)
      new_state = %{state | step_history: pruned_history}

      case persist_state(new_state) do
        :ok ->
          Logger.info("Pruned #{pruned_count} steps from history")
          {:ok, pruned_count, new_state}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp prune_history_internal(
         history,
         target_size,
         checkpoints,
         preserve_checkpoints
       ) do
    current_size = length(history)

    if current_size <= target_size do
      {:ok, history}
    else
      to_remove_count = current_size - target_size

      if preserve_checkpoints and length(checkpoints) > 0 do
        # Get step IDs that are referenced by checkpoints
        checkpoint_step_ids = get_checkpoint_step_ids(checkpoints)

        # Separate steps into checkpoint-referenced and regular steps
        {checkpoint_steps, regular_steps} =
          Enum.split_with(history, fn step ->
            step.id in checkpoint_step_ids
          end)

        # Remove from regular steps first (oldest first)
        regular_to_remove = min(to_remove_count, length(regular_steps))
        remaining_regular = Enum.drop(regular_steps, regular_to_remove)

        # If we still need to remove more, remove from checkpoint steps (oldest first)
        remaining_to_remove = to_remove_count - regular_to_remove

        if remaining_to_remove > 0 do
          remaining_checkpoint = Enum.drop(checkpoint_steps, remaining_to_remove)
          # Maintain chronological order by sorting by started_at
          final_history =
            (remaining_checkpoint ++ remaining_regular)
            |> Enum.sort_by(& &1.started_at, DateTime)

          {:ok, final_history}
        else
          # Maintain chronological order by sorting by started_at
          final_history =
            (checkpoint_steps ++ remaining_regular)
            |> Enum.sort_by(& &1.started_at, DateTime)

          {:ok, final_history}
        end
      else
        # Simple pruning - remove oldest steps
        {:ok, Enum.drop(history, to_remove_count)}
      end
    end
  end

  defp get_checkpoint_step_ids(checkpoints) do
    checkpoints
    |> Enum.flat_map(fn checkpoint ->
      checkpoint.conversation_state
      |> Map.get(:step_history, [])
      |> Enum.map(& &1.id)
    end)
    |> MapSet.new()
  end

  defp build_history_stats(state) do
    history = state.step_history
    checkpoints = state.checkpoints

    step_types = Enum.group_by(history, & &1.type)
    step_statuses = Enum.group_by(history, & &1.status)

    oldest_step = List.first(history)
    newest_step = List.last(history)

    %{
      total_steps: length(history),
      total_checkpoints: length(checkpoints),
      max_history_size: state.max_step_history,
      step_types: Map.new(step_types, fn {type, steps} -> {type, length(steps)} end),
      step_statuses: Map.new(step_statuses, fn {status, steps} -> {status, length(steps)} end),
      oldest_step_id: if(oldest_step, do: oldest_step.id),
      newest_step_id: if(newest_step, do: newest_step.id),
      oldest_step_timestamp: if(oldest_step, do: oldest_step.started_at),
      newest_step_timestamp: if(newest_step, do: newest_step.started_at),
      conversation_id: state.conversation_id,
      steps_since_last_checkpoint: state.step_count_since_checkpoint,
      auto_checkpoint_interval: state.auto_checkpoint_interval
    }
  end

  defp build_conversation_replay_stream(state, opts) do
    from_checkpoint = Keyword.get(opts, :from_checkpoint)
    from_step = Keyword.get(opts, :from_step)
    to_step = Keyword.get(opts, :to_step)
    include_metadata = Keyword.get(opts, :include_metadata, false)

    # Determine starting history
    starting_history =
      case from_checkpoint do
        nil ->
          state.step_history

        checkpoint_id ->
          case Enum.find(state.checkpoints, &(&1.id == checkpoint_id)) do
            nil ->
              {:error, :checkpoint_not_found}

            checkpoint ->
              checkpoint.conversation_state
              |> Map.get(:step_history, [])
          end
      end

    case starting_history do
      {:error, reason} ->
        {:error, reason}

      history ->
        # Filter by step range if specified
        filtered_history =
          history
          |> filter_from_step(from_step)
          |> filter_to_step(to_step)

        # Create replay stream
        replay_stream =
          filtered_history
          |> Stream.map(fn step ->
            if include_metadata do
              step
            else
              %{
                id: step.id,
                type: step.type,
                description: step.description,
                started_at: step.started_at,
                completed_at: step.completed_at,
                status: step.status,
                tools_used: step.tools_used
              }
            end
          end)

        {:ok, replay_stream}
    end
  end

  defp filter_from_step(history, nil), do: history

  defp filter_from_step(history, from_step_id) do
    case Enum.find_index(history, &(&1.id == from_step_id)) do
      nil -> history
      index -> Enum.drop(history, index)
    end
  end

  defp filter_to_step(history, nil), do: history

  defp filter_to_step(history, to_step_id) do
    case Enum.find_index(history, &(&1.id == to_step_id)) do
      nil -> history
      index -> Enum.take(history, index + 1)
    end
  end

  defp do_create_checkpoint(label, state) do
    checkpoint_id = generate_checkpoint_id()
    now = DateTime.utc_now()

    checkpoint = %{
      id: checkpoint_id,
      label: label,
      created_at: now,
      step_count: length(state.step_history),
      conversation_state: %{
        step_history: state.step_history,
        conversation_id: state.conversation_id
      }
    }

    new_checkpoints = state.checkpoints ++ [checkpoint]
    new_state = %{state | checkpoints: new_checkpoints, step_count_since_checkpoint: 0}

    case persist_state(new_state) do
      :ok ->
        Logger.info("Created checkpoint '#{label}' (#{checkpoint_id})")
        {:ok, checkpoint_id, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_restore_checkpoint(checkpoint_id, state) do
    case Enum.find(state.checkpoints, &(&1.id == checkpoint_id)) do
      nil ->
        {:error, :checkpoint_not_found}

      checkpoint ->
        conversation_state = checkpoint.conversation_state
        restored_history = Map.get(conversation_state, :step_history, [])

        new_state = %{state | step_history: restored_history, step_count_since_checkpoint: 0}

        case persist_state(new_state) do
          :ok ->
            Logger.info("Restored from checkpoint #{checkpoint_id}")
            {:ok, new_state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp do_clear_history(state) do
    new_state = %{state | step_history: [], checkpoints: [], step_count_since_checkpoint: 0}

    case persist_state(new_state) do
      :ok ->
        Logger.info("Cleared conversation history")
        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_state(state) do
    adapter = state.persistence_adapter
    conversation_id = state.conversation_id

    data = %{
      step_history: state.step_history,
      checkpoints: state.checkpoints,
      step_count_since_checkpoint: state.step_count_since_checkpoint,
      conversation_id: conversation_id,
      updated_at: DateTime.utc_now()
    }

    adapter.save_conversation(state.persistence_state, conversation_id, data)
  end

  defp maybe_schedule_auto_checkpoint(state) do
    if state.step_count_since_checkpoint >= state.auto_checkpoint_interval do
      send(self(), :auto_checkpoint)
    end

    state
  end

  defp schedule_auto_checkpoint(_state) do
    # Could implement periodic auto-checkpointing here
    :ok
  end

  defp build_conversation_replay(state, opts) do
    from_checkpoint = Keyword.get(opts, :from_checkpoint)
    step_limit = Keyword.get(opts, :step_limit)

    history =
      case from_checkpoint do
        nil ->
          state.step_history

        checkpoint_id ->
          case Enum.find(state.checkpoints, &(&1.id == checkpoint_id)) do
            nil ->
              state.step_history

            checkpoint ->
              checkpoint.conversation_state
              |> Map.get(:step_history, [])
          end
      end

    limited_history =
      case step_limit do
        nil -> history
        limit -> Enum.take(history, limit)
      end

    %{
      conversation_id: state.conversation_id,
      step_history: limited_history,
      checkpoints: state.checkpoints,
      total_steps: length(state.step_history),
      replay_steps: length(limited_history),
      generated_at: DateTime.utc_now()
    }
  end

  defp generate_conversation_id do
    "conv-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_checkpoint_id do
    "checkpoint-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
