defmodule ClaudeCodeSDK.StateManager.FilePersistence do
  @moduledoc """
  File-based persistence adapter for StateManager.

  This adapter stores conversation state in JSON files on the filesystem.
  Each conversation is stored in a separate file for better performance
  and isolation.

  ## Configuration

  - `:base_path` - Base directory for storing conversation files (default: "/tmp/claude_conversations")
  - `:file_extension` - File extension for conversation files (default: ".json")
  - `:create_directories` - Whether to create directories if they don't exist (default: true)
  - `:backup_on_corruption` - Whether to backup corrupted files (default: true)

  ## Example

      {:ok, pid} = ClaudeCodeSDK.StateManager.start_link(
        persistence_adapter: ClaudeCodeSDK.StateManager.FilePersistence,
        persistence_config: %{
          base_path: "/var/lib/claude/conversations",
          create_directories: true
        }
      )

  """

  @behaviour ClaudeCodeSDK.StateManager.PersistenceBehaviour

  require Logger

  defstruct [
    :base_path,
    :file_extension,
    :create_directories,
    :backup_on_corruption
  ]

  @type t :: %__MODULE__{
          base_path: String.t(),
          file_extension: String.t(),
          create_directories: boolean(),
          backup_on_corruption: boolean()
        }

  @default_base_path "/tmp/claude_conversations"
  @default_file_extension ".json"

  @impl true
  def init(config) do
    base_path = Map.get(config, :base_path, @default_base_path)
    file_extension = Map.get(config, :file_extension, @default_file_extension)
    create_directories = Map.get(config, :create_directories, true)
    backup_on_corruption = Map.get(config, :backup_on_corruption, true)

    state = %__MODULE__{
      base_path: base_path,
      file_extension: file_extension,
      create_directories: create_directories,
      backup_on_corruption: backup_on_corruption
    }

    case ensure_base_directory(state) do
      :ok ->
        Logger.debug("FilePersistence initialized with base_path: #{base_path}")
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def save_conversation(%__MODULE__{} = state, conversation_id, data) do
    file_path = conversation_file_path(state, conversation_id)

    # Ensure directory exists
    case ensure_directory(Path.dirname(file_path), state) do
      :ok ->
        case encode_and_write(file_path, data) do
          :ok ->
            Logger.debug("Saved conversation #{conversation_id} to #{file_path}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to save conversation #{conversation_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def load_conversation(%__MODULE__{} = state, conversation_id) do
    file_path = conversation_file_path(state, conversation_id)

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, data} ->
            Logger.debug("Loaded conversation #{conversation_id} from #{file_path}")
            {:ok, data}

          {:error, decode_error} ->
            Logger.error(
              "Failed to decode conversation #{conversation_id}: #{inspect(decode_error)}"
            )

            if state.backup_on_corruption do
              backup_corrupted_file(file_path)
            end

            {:error, {:decode_error, decode_error}}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Failed to read conversation file #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete_conversation(%__MODULE__{} = state, conversation_id) do
    file_path = conversation_file_path(state, conversation_id)

    case File.rm(file_path) do
      :ok ->
        Logger.debug("Deleted conversation #{conversation_id} from #{file_path}")
        :ok

      {:error, :enoent} ->
        # File doesn't exist, consider it successfully deleted
        :ok

      {:error, reason} ->
        Logger.error("Failed to delete conversation file #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def list_conversations(%__MODULE__{} = state) do
    case File.ls(state.base_path) do
      {:ok, files} ->
        conversation_ids =
          files
          |> Enum.filter(&String.ends_with?(&1, state.file_extension))
          |> Enum.map(&String.replace_suffix(&1, state.file_extension, ""))

        {:ok, conversation_ids}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        Logger.error("Failed to list conversations: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def cleanup(%__MODULE__{} = state) do
    case list_conversations(state) do
      {:ok, conversation_ids} ->
        results =
          Enum.map(conversation_ids, fn id ->
            delete_conversation(state, id)
          end)

        case Enum.find(results, &match?({:error, _}, &1)) do
          nil ->
            Logger.debug("Cleaned up #{length(conversation_ids)} conversations")
            :ok

          {:error, reason} ->
            Logger.error("Cleanup partially failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Implementation

  defp conversation_file_path(%__MODULE__{} = state, conversation_id) do
    filename = conversation_id <> state.file_extension
    Path.join(state.base_path, filename)
  end

  defp ensure_base_directory(%__MODULE__{create_directories: false}), do: :ok

  defp ensure_base_directory(%__MODULE__{base_path: base_path, create_directories: true}) do
    case File.mkdir_p(base_path) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to create base directory #{base_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_directory(_path, %__MODULE__{create_directories: false}), do: :ok

  defp ensure_directory(path, %__MODULE__{create_directories: true}) do
    case File.mkdir_p(path) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to create directory #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp encode_and_write(file_path, data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        # Write atomically using a temporary file
        temp_path = file_path <> ".tmp"

        case File.write(temp_path, json) do
          :ok ->
            case File.rename(temp_path, file_path) do
              :ok ->
                :ok

              {:error, reason} ->
                # Clean up temp file
                File.rm(temp_path)
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, encode_error} ->
        Logger.error("Failed to encode conversation data: #{inspect(encode_error)}")
        {:error, {:encode_error, encode_error}}
    end
  end

  defp backup_corrupted_file(file_path) do
    backup_path = file_path <> ".corrupted." <> Integer.to_string(System.system_time(:second))

    case File.copy(file_path, backup_path) do
      {:ok, _bytes} ->
        Logger.info("Backed up corrupted file to #{backup_path}")

      {:error, reason} ->
        Logger.warning("Failed to backup corrupted file: #{inspect(reason)}")
    end
  end
end
