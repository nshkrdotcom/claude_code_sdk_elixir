defmodule ClaudeCodeSDK.StateManager.DatabasePersistence do
  @moduledoc """
  Database persistence adapter for StateManager using ETS.

  This adapter demonstrates how to implement database persistence for conversation
  state. In a production environment, this could be adapted to use PostgreSQL,
  MySQL, or other database systems.

  ## Configuration

  - `:table_name` - ETS table name (default: :claude_conversations)
  - `:table_options` - ETS table options (default: [:set, :public, :named_table])
  - `:auto_cleanup` - Whether to clean up table on init (default: false)

  ## Example

      {:ok, pid} = ClaudeCodeSDK.StateManager.start_link(
        persistence_adapter: ClaudeCodeSDK.StateManager.DatabasePersistence,
        persistence_config: %{
          table_name: :my_conversations,
          auto_cleanup: true
        }
      )

  """

  @behaviour ClaudeCodeSDK.StateManager.PersistenceBehaviour

  require Logger

  defstruct [
    :table_name,
    :table_options,
    :auto_cleanup
  ]

  @type t :: %__MODULE__{
          table_name: atom(),
          table_options: [term()],
          auto_cleanup: boolean()
        }

  @default_table_name :claude_conversations
  @default_table_options [:set, :public, :named_table]

  @impl true
  def init(config) do
    table_name = Map.get(config, :table_name, @default_table_name)
    table_options = Map.get(config, :table_options, @default_table_options)
    auto_cleanup = Map.get(config, :auto_cleanup, false)

    state = %__MODULE__{
      table_name: table_name,
      table_options: table_options,
      auto_cleanup: auto_cleanup
    }

    case ensure_table(state) do
      :ok ->
        Logger.debug("DatabasePersistence initialized with table: #{table_name}")
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def save_conversation(%__MODULE__{table_name: table_name} = _state, conversation_id, data) do
    try do
      # Add timestamp for tracking
      enriched_data = Map.put(data, :persisted_at, DateTime.utc_now())

      # Store in ETS table
      :ets.insert(table_name, {conversation_id, enriched_data})

      Logger.debug("Saved conversation #{conversation_id} to database table #{table_name}")
      :ok
    rescue
      error ->
        Logger.error("Failed to save conversation #{conversation_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @impl true
  def load_conversation(%__MODULE__{table_name: table_name} = _state, conversation_id) do
    try do
      case :ets.lookup(table_name, conversation_id) do
        [{^conversation_id, data}] ->
          Logger.debug("Loaded conversation #{conversation_id} from database table #{table_name}")
          {:ok, data}

        [] ->
          {:error, :not_found}
      end
    rescue
      error ->
        Logger.error("Failed to load conversation #{conversation_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @impl true
  def delete_conversation(%__MODULE__{table_name: table_name} = _state, conversation_id) do
    try do
      :ets.delete(table_name, conversation_id)
      Logger.debug("Deleted conversation #{conversation_id} from database table #{table_name}")
      :ok
    rescue
      error ->
        Logger.error("Failed to delete conversation #{conversation_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @impl true
  def list_conversations(%__MODULE__{table_name: table_name} = _state) do
    try do
      conversation_ids =
        :ets.tab2list(table_name)
        |> Enum.map(fn {conversation_id, _data} -> conversation_id end)

      {:ok, conversation_ids}
    rescue
      error ->
        Logger.error("Failed to list conversations: #{inspect(error)}")
        {:error, error}
    end
  end

  @impl true
  def cleanup(%__MODULE__{table_name: table_name} = _state) do
    try do
      :ets.delete_all_objects(table_name)
      Logger.debug("Cleaned up database table #{table_name}")
      :ok
    rescue
      error ->
        Logger.error("Failed to cleanup database table #{table_name}: #{inspect(error)}")
        {:error, error}
    end
  end

  ## Additional Database-Specific Functions

  @doc """
  Gets statistics about the database table.

  ## Parameters

  - `state` - DatabasePersistence state

  ## Returns

  Map containing table statistics.

  """
  @spec get_table_stats(t()) :: {:ok, map()} | {:error, term()}
  def get_table_stats(%__MODULE__{table_name: table_name} = _state) do
    try do
      info = :ets.info(table_name)

      stats = %{
        table_name: table_name,
        size: Keyword.get(info, :size, 0),
        memory: Keyword.get(info, :memory, 0),
        type: Keyword.get(info, :type, :unknown),
        protection: Keyword.get(info, :protection, :unknown),
        compressed: Keyword.get(info, :compressed, false)
      }

      {:ok, stats}
    rescue
      error ->
        Logger.error("Failed to get table stats: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Performs database maintenance operations.

  This could include compacting, analyzing, or other database-specific
  maintenance tasks. For ETS, this is mostly a no-op.

  ## Parameters

  - `state` - DatabasePersistence state

  ## Returns

  `:ok` on success, `{:error, reason}` on failure.

  """
  @spec maintenance(t()) :: :ok | {:error, term()}
  def maintenance(%__MODULE__{} = _state) do
    # For ETS, no specific maintenance is needed
    # In a real database implementation, this might run VACUUM, ANALYZE, etc.
    Logger.debug("Database maintenance completed")
    :ok
  end

  @doc """
  Backs up conversations to a file.

  ## Parameters

  - `state` - DatabasePersistence state
  - `backup_path` - Path to write backup file

  ## Returns

  `:ok` on success, `{:error, reason}` on failure.

  """
  @spec backup_to_file(t(), String.t()) :: :ok | {:error, term()}
  def backup_to_file(%__MODULE__{table_name: table_name} = _state, backup_path) do
    try do
      # Get all conversations
      conversations = :ets.tab2list(table_name)

      # Convert to a serializable format with string keys
      conversations_map =
        conversations
        |> Enum.map(fn {conversation_id, data} -> {to_string(conversation_id), data} end)
        |> Enum.into(%{})

      backup_data = %{
        backup_created_at: DateTime.utc_now(),
        table_name: table_name,
        conversations: conversations_map
      }

      # Write to file
      case Jason.encode(backup_data, pretty: true) do
        {:ok, json} ->
          case File.write(backup_path, json) do
            :ok ->
              Logger.info("Backed up #{length(conversations)} conversations to #{backup_path}")
              :ok

            {:error, reason} ->
              {:error, reason}
          end

        {:error, encode_error} ->
          {:error, {:encode_error, encode_error}}
      end
    rescue
      error ->
        Logger.error("Failed to backup conversations: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Restores conversations from a backup file.

  ## Parameters

  - `state` - DatabasePersistence state
  - `backup_path` - Path to backup file
  - `opts` - Restore options

  ## Options

  - `:clear_existing` - Whether to clear existing data first (default: false)
  - `:skip_existing` - Whether to skip conversations that already exist (default: true)

  ## Returns

  `{:ok, restored_count}` on success, `{:error, reason}` on failure.

  """
  @spec restore_from_file(t(), String.t(), keyword()) :: {:ok, integer()} | {:error, term()}
  def restore_from_file(%__MODULE__{table_name: table_name} = state, backup_path, opts \\ []) do
    clear_existing = Keyword.get(opts, :clear_existing, false)
    skip_existing = Keyword.get(opts, :skip_existing, true)

    try do
      case File.read(backup_path) do
        {:ok, content} ->
          case Jason.decode(content, keys: :atoms) do
            {:ok, backup_data} ->
              conversations = Map.get(backup_data, :conversations, %{})

              # Clear existing data if requested
              if clear_existing do
                cleanup(state)
              end

              # Restore conversations
              restored_count =
                Enum.reduce(conversations, 0, fn {conversation_id, data}, acc ->
                  # Convert conversation_id to string if it's an atom (from JSON keys)
                  string_conversation_id =
                    if is_atom(conversation_id),
                      do: Atom.to_string(conversation_id),
                      else: conversation_id

                  should_restore =
                    if skip_existing do
                      case :ets.lookup(table_name, string_conversation_id) do
                        [] -> true
                        _ -> false
                      end
                    else
                      true
                    end

                  if should_restore do
                    :ets.insert(table_name, {string_conversation_id, data})
                    acc + 1
                  else
                    acc
                  end
                end)

              Logger.info("Restored #{restored_count} conversations from #{backup_path}")
              {:ok, restored_count}

            {:error, decode_error} ->
              {:error, {:decode_error, decode_error}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Failed to restore conversations: #{inspect(error)}")
        {:error, error}
    end
  end

  ## Private Implementation

  defp ensure_table(%__MODULE__{
         table_name: table_name,
         table_options: table_options,
         auto_cleanup: auto_cleanup
       }) do
    try do
      # Check if table already exists
      case :ets.info(table_name) do
        :undefined ->
          # Create new table
          ^table_name = :ets.new(table_name, table_options)
          :ok

        _info ->
          # Table exists
          if auto_cleanup do
            :ets.delete_all_objects(table_name)
          end

          :ok
      end
    rescue
      error ->
        Logger.error("Failed to ensure table #{table_name}: #{inspect(error)}")
        {:error, error}
    end
  end
end
