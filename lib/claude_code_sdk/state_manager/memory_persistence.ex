defmodule ClaudeCodeSDK.StateManager.MemoryPersistence do
  @moduledoc """
  In-memory persistence adapter for StateManager.

  This adapter stores conversation state in memory using an Agent process.
  Data is lost when the process terminates, making it suitable for testing
  and temporary storage scenarios.

  ## Configuration

  No configuration options are required for memory persistence.

  ## Example

      {:ok, pid} = ClaudeCodeSDK.StateManager.start_link(
        persistence_adapter: ClaudeCodeSDK.StateManager.MemoryPersistence
      )

  """

  @behaviour ClaudeCodeSDK.StateManager.PersistenceBehaviour

  require Logger

  defstruct [:agent_pid]

  @type t :: %__MODULE__{
          agent_pid: pid()
        }

  @impl true
  def init(_config) do
    case Agent.start_link(fn -> %{} end) do
      {:ok, pid} ->
        Logger.debug("MemoryPersistence initialized")
        {:ok, %__MODULE__{agent_pid: pid}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def save_conversation(%__MODULE__{agent_pid: pid}, conversation_id, data) do
    try do
      Agent.update(pid, fn state ->
        Map.put(state, conversation_id, data)
      end)

      Logger.debug("Saved conversation #{conversation_id} to memory")
      :ok
    rescue
      error ->
        Logger.error("Failed to save conversation #{conversation_id}: #{inspect(error)}")
        {:error, error}
    catch
      :exit, reason ->
        Logger.error("Failed to save conversation #{conversation_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def load_conversation(%__MODULE__{agent_pid: pid}, conversation_id) do
    try do
      case Agent.get(pid, fn state -> Map.get(state, conversation_id) end) do
        nil ->
          {:error, :not_found}

        data ->
          Logger.debug("Loaded conversation #{conversation_id} from memory")
          {:ok, data}
      end
    rescue
      error ->
        Logger.error("Failed to load conversation #{conversation_id}: #{inspect(error)}")
        {:error, error}
    catch
      :exit, reason ->
        Logger.error("Failed to load conversation #{conversation_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete_conversation(%__MODULE__{agent_pid: pid}, conversation_id) do
    try do
      Agent.update(pid, fn state ->
        Map.delete(state, conversation_id)
      end)

      Logger.debug("Deleted conversation #{conversation_id} from memory")
      :ok
    rescue
      error ->
        Logger.error("Failed to delete conversation #{conversation_id}: #{inspect(error)}")
        {:error, error}
    catch
      :exit, reason ->
        Logger.error("Failed to delete conversation #{conversation_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def list_conversations(%__MODULE__{agent_pid: pid}) do
    try do
      conversation_ids =
        Agent.get(pid, fn state ->
          Map.keys(state)
        end)

      {:ok, conversation_ids}
    rescue
      error ->
        Logger.error("Failed to list conversations: #{inspect(error)}")
        {:error, error}
    catch
      :exit, reason ->
        Logger.error("Failed to list conversations: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def cleanup(%__MODULE__{agent_pid: pid}) do
    try do
      Agent.update(pid, fn _state -> %{} end)
      Logger.debug("Cleaned up memory persistence")
      :ok
    rescue
      error ->
        Logger.error("Failed to cleanup memory persistence: #{inspect(error)}")
        {:error, error}
    catch
      :exit, reason ->
        Logger.error("Failed to cleanup memory persistence: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
