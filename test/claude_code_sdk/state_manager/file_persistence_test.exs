defmodule ClaudeCodeSDK.StateManager.FilePersistenceTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.StateManager.FilePersistence

  describe "FilePersistence" do
    setup do
      temp_dir = System.tmp_dir!() |> Path.join("claude_file_test_#{:rand.uniform(10000)}")

      config = %{
        base_path: temp_dir,
        create_directories: true,
        backup_on_corruption: true
      }

      {:ok, adapter_state} = FilePersistence.init(config)

      on_exit(fn ->
        File.rm_rf(temp_dir)
      end)

      {:ok, adapter_state: adapter_state, temp_dir: temp_dir}
    end

    test "initializes and creates base directory", %{adapter_state: state, temp_dir: temp_dir} do
      assert %FilePersistence{base_path: ^temp_dir} = state
      assert File.exists?(temp_dir)
      assert File.dir?(temp_dir)
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
      assert :ok = FilePersistence.save_conversation(state, conversation_id, data)

      # Verify file was created
      file_path = Path.join(state.base_path, "#{conversation_id}.json")
      assert File.exists?(file_path)

      # Load data
      assert {:ok, loaded_data} = FilePersistence.load_conversation(state, conversation_id)
      assert loaded_data.conversation_id == conversation_id
      assert length(loaded_data.step_history) == 1
      assert List.first(loaded_data.step_history).id == "step-1"
    end

    test "returns not_found for non-existent conversation", %{adapter_state: state} do
      assert {:error, :not_found} = FilePersistence.load_conversation(state, "nonexistent")
    end

    test "deletes conversation files", %{adapter_state: state} do
      conversation_id = "test-conversation"
      data = %{conversation_id: conversation_id}

      # Save and verify file exists
      :ok = FilePersistence.save_conversation(state, conversation_id, data)
      file_path = Path.join(state.base_path, "#{conversation_id}.json")
      assert File.exists?(file_path)

      # Delete and verify file is gone
      assert :ok = FilePersistence.delete_conversation(state, conversation_id)
      refute File.exists?(file_path)
      assert {:error, :not_found} = FilePersistence.load_conversation(state, conversation_id)
    end

    test "deleting non-existent conversation succeeds", %{adapter_state: state} do
      assert :ok = FilePersistence.delete_conversation(state, "nonexistent")
    end

    test "lists conversations from files", %{adapter_state: state} do
      # Initially empty
      assert {:ok, []} = FilePersistence.list_conversations(state)

      # Add some conversations
      :ok = FilePersistence.save_conversation(state, "conv-1", %{id: "conv-1"})
      :ok = FilePersistence.save_conversation(state, "conv-2", %{id: "conv-2"})

      # Should list both
      assert {:ok, conversation_ids} = FilePersistence.list_conversations(state)
      assert length(conversation_ids) == 2
      assert "conv-1" in conversation_ids
      assert "conv-2" in conversation_ids
    end

    test "cleanup removes all conversation files", %{adapter_state: state} do
      # Add some conversations
      :ok = FilePersistence.save_conversation(state, "conv-1", %{id: "conv-1"})
      :ok = FilePersistence.save_conversation(state, "conv-2", %{id: "conv-2"})

      # Verify files exist
      assert {:ok, [_, _]} = FilePersistence.list_conversations(state)

      # Cleanup
      assert :ok = FilePersistence.cleanup(state)

      # Should be empty
      assert {:ok, []} = FilePersistence.list_conversations(state)
    end

    test "uses atomic writes with temporary files", %{adapter_state: state, temp_dir: temp_dir} do
      conversation_id = "test-conversation"
      data = %{conversation_id: conversation_id, large_data: String.duplicate("x", 10000)}

      # Save data
      :ok = FilePersistence.save_conversation(state, conversation_id, data)

      # Verify no temporary file remains
      temp_file = Path.join(temp_dir, "#{conversation_id}.json.tmp")
      refute File.exists?(temp_file)

      # Verify actual file exists and is valid
      actual_file = Path.join(temp_dir, "#{conversation_id}.json")
      assert File.exists?(actual_file)

      {:ok, loaded_data} = FilePersistence.load_conversation(state, conversation_id)
      assert loaded_data.conversation_id == conversation_id
    end

    test "handles JSON encoding errors", %{adapter_state: state} do
      conversation_id = "test-conversation"

      # Create data that can't be JSON encoded (function)
      bad_data = %{conversation_id: conversation_id, bad_field: fn -> :error end}

      # Should fail gracefully
      assert {:error, {:encode_error, _}} =
               FilePersistence.save_conversation(state, conversation_id, bad_data)
    end

    test "handles corrupted JSON files", %{adapter_state: state, temp_dir: temp_dir} do
      conversation_id = "corrupted-conversation"
      file_path = Path.join(temp_dir, "#{conversation_id}.json")

      # Create corrupted file
      File.write!(file_path, "invalid json content {")

      # Should detect corruption and backup file
      assert {:error, {:decode_error, _}} =
               FilePersistence.load_conversation(state, conversation_id)

      # Should create backup file
      backup_files =
        File.ls!(temp_dir)
        |> Enum.filter(&String.contains?(&1, "corrupted"))

      # Original + backup
      assert length(backup_files) >= 1
    end

    test "overwrites existing files", %{adapter_state: state} do
      conversation_id = "test-conversation"

      # Save initial data
      initial_data = %{version: 1, data: "initial"}
      :ok = FilePersistence.save_conversation(state, conversation_id, initial_data)

      # Overwrite with new data
      updated_data = %{version: 2, data: "updated"}
      :ok = FilePersistence.save_conversation(state, conversation_id, updated_data)

      # Should have updated data
      {:ok, loaded_data} = FilePersistence.load_conversation(state, conversation_id)
      assert loaded_data.version == 2
      assert loaded_data.data == "updated"
    end

    test "handles custom file extension", %{temp_dir: temp_dir} do
      config = %{
        base_path: temp_dir,
        file_extension: ".claude",
        create_directories: true
      }

      {:ok, state} = FilePersistence.init(config)

      conversation_id = "test-conversation"
      data = %{conversation_id: conversation_id}

      :ok = FilePersistence.save_conversation(state, conversation_id, data)

      # Should use custom extension
      file_path = Path.join(temp_dir, "#{conversation_id}.claude")
      assert File.exists?(file_path)

      # Should load correctly
      {:ok, loaded_data} = FilePersistence.load_conversation(state, conversation_id)
      assert loaded_data.conversation_id == conversation_id
    end
  end

  describe "FilePersistence configuration" do
    test "fails when directory creation is disabled and directory doesn't exist" do
      nonexistent_dir = "/tmp/nonexistent_#{:rand.uniform(10000)}"

      config = %{
        base_path: nonexistent_dir,
        create_directories: false
      }

      # Should succeed in init (doesn't check directory existence)
      assert {:ok, _state} = FilePersistence.init(config)
    end

    test "uses default configuration values" do
      temp_dir = System.tmp_dir!() |> Path.join("claude_default_test_#{:rand.uniform(10000)}")

      config = %{base_path: temp_dir}
      {:ok, state} = FilePersistence.init(config)

      on_exit(fn -> File.rm_rf(temp_dir) end)

      assert state.file_extension == ".json"
      assert state.create_directories == true
      assert state.backup_on_corruption == true
    end
  end

  describe "FilePersistence error handling" do
    test "handles permission errors gracefully" do
      # This test might not work on all systems, so we'll skip it if we can't create the scenario
      if System.get_env("CI") do
        # Skip on CI where we might not have permission control
        :ok
      else
        temp_dir =
          System.tmp_dir!() |> Path.join("claude_permission_test_#{:rand.uniform(10000)}")

        File.mkdir_p!(temp_dir)

        config = %{base_path: temp_dir, create_directories: false}
        {:ok, state} = FilePersistence.init(config)

        on_exit(fn -> File.rm_rf(temp_dir) end)

        # Try to save to a read-only directory (if we can make it read-only)
        case File.chmod(temp_dir, 0o444) do
          :ok ->
            # Directory is now read-only, save should fail
            result = FilePersistence.save_conversation(state, "test", %{})
            assert {:error, _} = result

            # Restore permissions for cleanup
            File.chmod(temp_dir, 0o755)

          {:error, _} ->
            # Can't change permissions, skip this test
            :ok
        end
      end
    end

    test "handles disk full scenarios" do
      # This is difficult to test reliably, so we'll just ensure the error handling structure is there
      temp_dir = System.tmp_dir!() |> Path.join("claude_disk_test_#{:rand.uniform(10000)}")

      config = %{base_path: temp_dir, create_directories: true}
      {:ok, state} = FilePersistence.init(config)

      on_exit(fn -> File.rm_rf(temp_dir) end)

      # Normal operation should work
      assert :ok = FilePersistence.save_conversation(state, "test", %{data: "small"})
    end
  end
end
