defmodule ClaudeCodeSDK.StateManager.MemoryPersistenceTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.StateManager.MemoryPersistence

  describe "MemoryPersistence" do
    setup do
      {:ok, adapter_state} = MemoryPersistence.init(%{})
      {:ok, adapter_state: adapter_state}
    end

    test "initializes successfully", %{adapter_state: state} do
      assert %MemoryPersistence{agent_pid: pid} = state
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "saves and loads conversation data", %{adapter_state: state} do
      conversation_id = "test-conversation"

      data = %{
        step_history: [],
        checkpoints: [],
        conversation_id: conversation_id,
        updated_at: DateTime.utc_now()
      }

      # Save data
      assert :ok = MemoryPersistence.save_conversation(state, conversation_id, data)

      # Load data
      assert {:ok, loaded_data} = MemoryPersistence.load_conversation(state, conversation_id)
      assert loaded_data.conversation_id == conversation_id
      assert loaded_data.step_history == []
      assert loaded_data.checkpoints == []
    end

    test "returns not_found for non-existent conversation", %{adapter_state: state} do
      assert {:error, :not_found} = MemoryPersistence.load_conversation(state, "nonexistent")
    end

    test "deletes conversation data", %{adapter_state: state} do
      conversation_id = "test-conversation"
      data = %{conversation_id: conversation_id}

      # Save and verify it exists
      :ok = MemoryPersistence.save_conversation(state, conversation_id, data)
      assert {:ok, _} = MemoryPersistence.load_conversation(state, conversation_id)

      # Delete and verify it's gone
      assert :ok = MemoryPersistence.delete_conversation(state, conversation_id)
      assert {:error, :not_found} = MemoryPersistence.load_conversation(state, conversation_id)
    end

    test "deleting non-existent conversation succeeds", %{adapter_state: state} do
      assert :ok = MemoryPersistence.delete_conversation(state, "nonexistent")
    end

    test "lists conversations", %{adapter_state: state} do
      # Initially empty
      assert {:ok, []} = MemoryPersistence.list_conversations(state)

      # Add some conversations
      :ok = MemoryPersistence.save_conversation(state, "conv-1", %{id: "conv-1"})
      :ok = MemoryPersistence.save_conversation(state, "conv-2", %{id: "conv-2"})

      # Should list both
      assert {:ok, conversation_ids} = MemoryPersistence.list_conversations(state)
      assert length(conversation_ids) == 2
      assert "conv-1" in conversation_ids
      assert "conv-2" in conversation_ids
    end

    test "cleanup removes all conversations", %{adapter_state: state} do
      # Add some conversations
      :ok = MemoryPersistence.save_conversation(state, "conv-1", %{id: "conv-1"})
      :ok = MemoryPersistence.save_conversation(state, "conv-2", %{id: "conv-2"})

      # Verify they exist
      assert {:ok, [_, _]} = MemoryPersistence.list_conversations(state)

      # Cleanup
      assert :ok = MemoryPersistence.cleanup(state)

      # Should be empty
      assert {:ok, []} = MemoryPersistence.list_conversations(state)
    end

    test "handles multiple conversations independently", %{adapter_state: state} do
      data1 = %{conversation_id: "conv-1", data: "first"}
      data2 = %{conversation_id: "conv-2", data: "second"}

      # Save both
      :ok = MemoryPersistence.save_conversation(state, "conv-1", data1)
      :ok = MemoryPersistence.save_conversation(state, "conv-2", data2)

      # Load both and verify independence
      {:ok, loaded1} = MemoryPersistence.load_conversation(state, "conv-1")
      {:ok, loaded2} = MemoryPersistence.load_conversation(state, "conv-2")

      assert loaded1.data == "first"
      assert loaded2.data == "second"

      # Delete one, other should remain
      :ok = MemoryPersistence.delete_conversation(state, "conv-1")

      assert {:error, :not_found} = MemoryPersistence.load_conversation(state, "conv-1")
      assert {:ok, _} = MemoryPersistence.load_conversation(state, "conv-2")
    end

    test "overwrites existing conversation data", %{adapter_state: state} do
      conversation_id = "test-conversation"

      # Save initial data
      initial_data = %{version: 1, data: "initial"}
      :ok = MemoryPersistence.save_conversation(state, conversation_id, initial_data)

      # Overwrite with new data
      updated_data = %{version: 2, data: "updated"}
      :ok = MemoryPersistence.save_conversation(state, conversation_id, updated_data)

      # Should have updated data
      {:ok, loaded_data} = MemoryPersistence.load_conversation(state, conversation_id)
      assert loaded_data.version == 2
      assert loaded_data.data == "updated"
    end
  end

  describe "MemoryPersistence error handling" do
    test "handles agent process termination gracefully" do
      {:ok, state} = MemoryPersistence.init(%{})

      # Terminate the agent process
      Agent.stop(state.agent_pid)

      # Give the process time to fully terminate
      Process.sleep(100)

      # Operations should fail gracefully (they catch exceptions and return errors)
      assert {:error, _} = MemoryPersistence.save_conversation(state, "test", %{})
      assert {:error, _} = MemoryPersistence.load_conversation(state, "test")
      assert {:error, _} = MemoryPersistence.delete_conversation(state, "test")
      assert {:error, _} = MemoryPersistence.list_conversations(state)
      assert {:error, _} = MemoryPersistence.cleanup(state)
    end
  end
end
