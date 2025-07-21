defmodule ClaudeCodeSDK.StateManager.PersistenceBehaviour do
  @moduledoc """
  Behaviour for StateManager persistence adapters.

  Persistence adapters handle the storage and retrieval of conversation state
  and step history. Different adapters can be implemented for various storage
  backends like memory, files, databases, etc.

  ## Callbacks

  - `init/1` - Initialize the persistence adapter with configuration
  - `save_conversation/3` - Save conversation state data
  - `load_conversation/2` - Load conversation state data
  - `delete_conversation/2` - Delete conversation state data
  - `list_conversations/1` - List all stored conversations
  - `cleanup/1` - Perform cleanup operations

  ## Example Implementation

      defmodule MyCustomPersistence do
        @behaviour ClaudeCodeSDK.StateManager.PersistenceBehaviour

        @impl true
        def init(config) do
          # Initialize your storage backend
          {:ok, initial_state}
        end

        @impl true
        def save_conversation(state, conversation_id, data) do
          # Save the conversation data
          :ok
        end

        # ... implement other callbacks
      end

  """

  @type persistence_state :: term()
  @type conversation_id :: String.t()
  @type conversation_data :: map()
  @type config :: map()

  @doc """
  Initialize the persistence adapter with the given configuration.

  ## Parameters

  - `config` - Configuration map for the adapter

  ## Returns

  - `{:ok, state}` - Success with initial adapter state
  - `{:error, reason}` - Initialization failure

  """
  @callback init(config()) :: {:ok, persistence_state()} | {:error, term()}

  @doc """
  Save conversation state data.

  ## Parameters

  - `state` - Current adapter state
  - `conversation_id` - Unique conversation identifier
  - `data` - Conversation data to save

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Save failure

  """
  @callback save_conversation(persistence_state(), conversation_id(), conversation_data()) ::
              :ok | {:error, term()}

  @doc """
  Load conversation state data.

  ## Parameters

  - `state` - Current adapter state
  - `conversation_id` - Unique conversation identifier

  ## Returns

  - `{:ok, data}` - Success with conversation data
  - `{:error, :not_found}` - Conversation not found
  - `{:error, reason}` - Load failure

  """
  @callback load_conversation(persistence_state(), conversation_id()) ::
              {:ok, conversation_data()} | {:error, term()}

  @doc """
  Delete conversation state data.

  ## Parameters

  - `state` - Current adapter state
  - `conversation_id` - Unique conversation identifier

  ## Returns

  - `:ok` - Success (even if conversation didn't exist)
  - `{:error, reason}` - Delete failure

  """
  @callback delete_conversation(persistence_state(), conversation_id()) ::
              :ok | {:error, term()}

  @doc """
  List all stored conversations.

  ## Parameters

  - `state` - Current adapter state

  ## Returns

  - `{:ok, conversation_ids}` - Success with list of conversation IDs
  - `{:error, reason}` - List failure

  """
  @callback list_conversations(persistence_state()) ::
              {:ok, [conversation_id()]} | {:error, term()}

  @doc """
  Perform cleanup operations (optional).

  This callback can be used to clean up old conversations, compact storage,
  or perform other maintenance tasks.

  ## Parameters

  - `state` - Current adapter state

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Cleanup failure

  """
  @callback cleanup(persistence_state()) :: :ok | {:error, term()}

  @optional_callbacks [cleanup: 1]
end
