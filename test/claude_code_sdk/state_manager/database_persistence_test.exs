defmodule ClaudeCodeSDK.StateManager.DatabasePersistenceTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.StateManager.DatabasePersistence

  describe "DatabasePersistence" do
    setup do
      # Use a unique table name for each test to avoid conflicts
      table_name = :"test_table_#{:rand.uniform(10000)}"

      config = %{
        table_name: table_name,
        auto_cleanup: true
      }

      {:ok, adapter_state} = DatabasePersistence.init(config)

      on_exit(fn ->
        # Clean up the ETS table
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, adapter_state: adapter_state, table_name: table_name}
    end

    test "initializes successfully and creates ETS table", %{
      adapter_state: state,
      table_name: table_name
    } do
      assert %DatabasePersistence{table_name: ^table_name} = state
      assert :ets.info(table_name) != :undefined
    end

    test "saves and loads conversation data", %{adapter_state: state} do
      conversation_id = "test-conversation"

      data = %{
        step_history: [%{id: "step-1", type: :file_operation}],
        checkpoints: [],
        conversation_id: conversation_id,
        updated_at: DateTime.utc_now()
      }

      # Save data
      assert :ok = DatabasePersistence.save_conversation(state, conversation_id, data)

      # Load data
      assert {:ok, loaded_data} = DatabasePersistence.load_conversation(state, conversation_id)
      assert loaded_data.conversation_id == conversation_id
      assert length(loaded_data.step_history) == 1
      assert List.first(loaded_data.step_history).id == "step-1"
      assert %DateTime{} = loaded_data.persisted_at
    end

    test "returns not_found for non-existent conversation", %{adapter_state: state} do
      assert {:error, :not_found} = DatabasePersistence.load_conversation(state, "nonexistent")
    end

    test "deletes conversation data", %{adapter_state: state} do
      conversation_id = "test-conversation"
      data = %{conversation_id: conversation_id}

      # Save and verify it exists
      :ok = DatabasePersistence.save_conversation(state, conversation_id, data)
      assert {:ok, _} = DatabasePersistence.load_conversation(state, conversation_id)

      # Delete and verify it's gone
      assert :ok = DatabasePersistence.delete_conversation(state, conversation_id)
      assert {:error, :not_found} = DatabasePersistence.load_conversation(state, conversation_id)
    end

    test "deleting non-existent conversation succeeds", %{adapter_state: state} do
      assert :ok = DatabasePersistence.delete_conversation(state, "nonexistent")
    end

    test "lists conversations", %{adapter_state: state} do
      # Initially empty
      assert {:ok, []} = DatabasePersistence.list_conversations(state)

      # Add some conversations
      :ok = DatabasePersistence.save_conversation(state, "conv-1", %{id: "conv-1"})
      :ok = DatabasePersistence.save_conversation(state, "conv-2", %{id: "conv-2"})

      # Should list both
      assert {:ok, conversation_ids} = DatabasePersistence.list_conversations(state)
      assert length(conversation_ids) == 2
      assert "conv-1" in conversation_ids
      assert "conv-2" in conversation_ids
    end

    test "cleanup removes all conversations", %{adapter_state: state} do
      # Add some conversations
      :ok = DatabasePersistence.save_conversation(state, "conv-1", %{id: "conv-1"})
      :ok = DatabasePersistence.save_conversation(state, "conv-2", %{id: "conv-2"})

      # Verify they exist
      assert {:ok, [_, _]} = DatabasePersistence.list_conversations(state)

      # Cleanup
      assert :ok = DatabasePersistence.cleanup(state)

      # Should be empty
      assert {:ok, []} = DatabasePersistence.list_conversations(state)
    end

    test "handles multiple conversations independently", %{adapter_state: state} do
      data1 = %{conversation_id: "conv-1", data: "first"}
      data2 = %{conversation_id: "conv-2", data: "second"}

      # Save both
      :ok = DatabasePersistence.save_conversation(state, "conv-1", data1)
      :ok = DatabasePersistence.save_conversation(state, "conv-2", data2)

      # Load both and verify independence
      {:ok, loaded1} = DatabasePersistence.load_conversation(state, "conv-1")
      {:ok, loaded2} = DatabasePersistence.load_conversation(state, "conv-2")

      assert loaded1.data == "first"
      assert loaded2.data == "second"

      # Delete one, other should remain
      :ok = DatabasePersistence.delete_conversation(state, "conv-1")

      assert {:error, :not_found} = DatabasePersistence.load_conversation(state, "conv-1")
      assert {:ok, _} = DatabasePersistence.load_conversation(state, "conv-2")
    end

    test "overwrites existing conversation data", %{adapter_state: state} do
      conversation_id = "test-conversation"

      # Save initial data
      initial_data = %{version: 1, data: "initial"}
      :ok = DatabasePersistence.save_conversation(state, conversation_id, initial_data)

      # Overwrite with new data
      updated_data = %{version: 2, data: "updated"}
      :ok = DatabasePersistence.save_conversation(state, conversation_id, updated_data)

      # Should have updated data
      {:ok, loaded_data} = DatabasePersistence.load_conversation(state, conversation_id)
      assert loaded_data.version == 2
      assert loaded_data.data == "updated"
    end

    test "gets table statistics", %{adapter_state: state} do
      # Add some data
      :ok = DatabasePersistence.save_conversation(state, "conv-1", %{data: "test1"})
      :ok = DatabasePersistence.save_conversation(state, "conv-2", %{data: "test2"})

      {:ok, stats} = DatabasePersistence.get_table_stats(state)

      assert stats.table_name == state.table_name
      assert stats.size == 2
      assert is_integer(stats.memory)
      assert stats.type == :set
    end

    test "performs maintenance operations", %{adapter_state: state} do
      assert :ok = DatabasePersistence.maintenance(state)
    end
  end

  describe "DatabasePersistence backup and restore" do
    setup do
      table_name = :"backup_test_table_#{:rand.uniform(10000)}"

      config = %{
        table_name: table_name,
        auto_cleanup: true
      }

      {:ok, adapter_state} = DatabasePersistence.init(config)

      temp_backup_path =
        System.tmp_dir!()
        |> Path.join("claude_backup_test_#{:rand.uniform(10000)}.json")

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end

        File.rm(temp_backup_path)
      end)

      {:ok, adapter_state: adapter_state, backup_path: temp_backup_path}
    end

    test "backs up and restores conversations", %{adapter_state: state, backup_path: backup_path} do
      # Add some test data
      :ok =
        DatabasePersistence.save_conversation(state, "conv-1", %{
          id: "conv-1",
          data: "first conversation",
          step_history: [%{id: "step-1", type: :file_operation}]
        })

      :ok =
        DatabasePersistence.save_conversation(state, "conv-2", %{
          id: "conv-2",
          data: "second conversation",
          step_history: [%{id: "step-2", type: :code_modification}]
        })

      # Backup to file
      assert :ok = DatabasePersistence.backup_to_file(state, backup_path)
      assert File.exists?(backup_path)

      # Clear the table
      :ok = DatabasePersistence.cleanup(state)
      assert {:ok, []} = DatabasePersistence.list_conversations(state)

      # Restore from backup
      assert {:ok, restored_count} = DatabasePersistence.restore_from_file(state, backup_path)
      assert restored_count == 2

      # Verify data was restored
      {:ok, conversation_ids} = DatabasePersistence.list_conversations(state)
      assert length(conversation_ids) == 2
      assert "conv-1" in conversation_ids
      assert "conv-2" in conversation_ids

      # Verify conversation content
      {:ok, conv1} = DatabasePersistence.load_conversation(state, "conv-1")
      assert conv1.data == "first conversation"
    end

    test "handles backup file errors gracefully", %{adapter_state: state} do
      # Try to backup to invalid path
      invalid_path = "/invalid/path/backup.json"
      assert {:error, _} = DatabasePersistence.backup_to_file(state, invalid_path)

      # Try to restore from non-existent file
      assert {:error, _} =
               DatabasePersistence.restore_from_file(state, "/nonexistent/backup.json")
    end

    test "skips existing conversations during restore", %{
      adapter_state: state,
      backup_path: backup_path
    } do
      # Add initial data and backup
      :ok = DatabasePersistence.save_conversation(state, "conv-1", %{id: "conv-1", version: 1})
      :ok = DatabasePersistence.save_conversation(state, "conv-2", %{id: "conv-2", version: 1})
      :ok = DatabasePersistence.backup_to_file(state, backup_path)

      # Modify existing data
      :ok = DatabasePersistence.save_conversation(state, "conv-1", %{id: "conv-1", version: 2})

      # Restore with skip_existing: true (default)
      {:ok, restored_count} = DatabasePersistence.restore_from_file(state, backup_path)

      # Should skip both conversations since they already exist
      assert restored_count == 0

      # conv-1 should still have version 2 (not overwritten)
      {:ok, conv1} = DatabasePersistence.load_conversation(state, "conv-1")
      assert conv1.version == 2
    end

    test "overwrites existing conversations when skip_existing is false", %{
      adapter_state: state,
      backup_path: backup_path
    } do
      # Add initial data and backup
      :ok = DatabasePersistence.save_conversation(state, "conv-1", %{id: "conv-1", version: 1})
      :ok = DatabasePersistence.backup_to_file(state, backup_path)

      # Modify existing data
      :ok = DatabasePersistence.save_conversation(state, "conv-1", %{id: "conv-1", version: 2})

      # Restore with skip_existing: false
      {:ok, restored_count} =
        DatabasePersistence.restore_from_file(state, backup_path, skip_existing: false)

      assert restored_count == 1

      # conv-1 should have version 1 (overwritten from backup)
      {:ok, conv1} = DatabasePersistence.load_conversation(state, "conv-1")
      assert conv1.version == 1
    end
  end

  describe "DatabasePersistence configuration" do
    test "uses default configuration values" do
      {:ok, state} = DatabasePersistence.init(%{})

      assert state.table_name == :claude_conversations
      assert state.auto_cleanup == false

      # Clean up
      if :ets.info(:claude_conversations) != :undefined do
        :ets.delete(:claude_conversations)
      end
    end

    test "handles custom table options" do
      table_name = :"custom_options_table_#{:rand.uniform(10000)}"

      config = %{
        table_name: table_name,
        table_options: [:set, :public, :named_table, {:read_concurrency, true}]
      }

      {:ok, state} = DatabasePersistence.init(config)

      assert state.table_name == table_name
      info = :ets.info(table_name)
      assert Keyword.get(info, :read_concurrency) == true

      # Clean up
      :ets.delete(table_name)
    end
  end

  describe "DatabasePersistence error handling" do
    test "handles table deletion gracefully" do
      table_name = :"error_test_table_#{:rand.uniform(10000)}"

      config = %{table_name: table_name}
      {:ok, state} = DatabasePersistence.init(config)

      # Delete the table externally
      :ets.delete(table_name)

      # Operations should fail gracefully
      assert {:error, _} = DatabasePersistence.save_conversation(state, "test", %{})
      assert {:error, _} = DatabasePersistence.load_conversation(state, "test")
      assert {:error, _} = DatabasePersistence.list_conversations(state)
    end
  end
end
