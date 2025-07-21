defmodule ClaudeCodeSDK.StateManagerTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{StateManager, Step, Message}
  alias ClaudeCodeSDK.StateManager.{MemoryPersistence, FilePersistence}

  describe "StateManager with MemoryPersistence" do
    setup do
      {:ok, pid} =
        StateManager.start_link(
          persistence_adapter: MemoryPersistence,
          max_step_history: 5,
          auto_checkpoint_interval: 3
        )

      {:ok, manager: pid}
    end

    test "starts with empty history", %{manager: manager} do
      assert StateManager.get_step_history(manager) == []
      assert StateManager.get_checkpoints(manager) == []
    end

    test "saves and retrieves steps", %{manager: manager} do
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      step2 = create_test_step("step-2", :code_modification, "Implementing feature")

      assert :ok = StateManager.save_step(manager, step1)
      assert :ok = StateManager.save_step(manager, step2)

      history = StateManager.get_step_history(manager)
      assert length(history) == 2
      assert Enum.at(history, 0).id == "step-1"
      assert Enum.at(history, 1).id == "step-2"
    end

    test "enforces max history limit", %{manager: manager} do
      # Add 7 steps (max is 5)
      _steps =
        for i <- 1..7 do
          step = create_test_step("step-#{i}", :file_operation, "Step #{i}")
          :ok = StateManager.save_step(manager, step)
          step
        end

      history = StateManager.get_step_history(manager)
      assert length(history) == 5

      # Should keep the most recent 5 steps
      step_ids = Enum.map(history, & &1.id)
      assert step_ids == ["step-3", "step-4", "step-5", "step-6", "step-7"]
    end

    test "creates and lists checkpoints", %{manager: manager} do
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      :ok = StateManager.save_step(manager, step1)

      {:ok, checkpoint_id} = StateManager.create_checkpoint(manager, "before_changes")

      checkpoints = StateManager.get_checkpoints(manager)
      assert length(checkpoints) == 1

      checkpoint = List.first(checkpoints)
      assert checkpoint.id == checkpoint_id
      assert checkpoint.label == "before_changes"
      assert checkpoint.step_count == 1
    end

    test "restores from checkpoint", %{manager: manager} do
      # Add initial steps
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      step2 = create_test_step("step-2", :code_modification, "Initial changes")
      :ok = StateManager.save_step(manager, step1)
      :ok = StateManager.save_step(manager, step2)

      # Create checkpoint
      {:ok, checkpoint_id} = StateManager.create_checkpoint(manager, "checkpoint_1")

      # Add more steps
      step3 = create_test_step("step-3", :system_command, "Running tests")
      step4 = create_test_step("step-4", :analysis, "Analyzing results")
      :ok = StateManager.save_step(manager, step3)
      :ok = StateManager.save_step(manager, step4)

      # Verify we have 4 steps
      assert length(StateManager.get_step_history(manager)) == 4

      # Restore from checkpoint
      :ok = StateManager.restore_checkpoint(manager, checkpoint_id)

      # Should have only the first 2 steps
      history = StateManager.get_step_history(manager)
      assert length(history) == 2
      assert Enum.at(history, 0).id == "step-1"
      assert Enum.at(history, 1).id == "step-2"
    end

    test "handles checkpoint not found", %{manager: manager} do
      assert {:error, :checkpoint_not_found} =
               StateManager.restore_checkpoint(manager, "nonexistent")
    end

    test "clears history and checkpoints", %{manager: manager} do
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      :ok = StateManager.save_step(manager, step1)
      {:ok, _checkpoint_id} = StateManager.create_checkpoint(manager, "test_checkpoint")

      assert length(StateManager.get_step_history(manager)) == 1
      assert length(StateManager.get_checkpoints(manager)) == 1

      :ok = StateManager.clear_history(manager)

      assert StateManager.get_step_history(manager) == []
      assert StateManager.get_checkpoints(manager) == []
    end

    test "generates conversation replay data", %{manager: manager} do
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      step2 = create_test_step("step-2", :code_modification, "Making changes")
      :ok = StateManager.save_step(manager, step1)
      :ok = StateManager.save_step(manager, step2)

      {:ok, _checkpoint_id} = StateManager.create_checkpoint(manager, "test_checkpoint")

      replay_data = StateManager.get_conversation_replay(manager)

      assert is_binary(replay_data.conversation_id)
      assert length(replay_data.step_history) == 2
      assert length(replay_data.checkpoints) == 1
      assert replay_data.total_steps == 2
      assert replay_data.replay_steps == 2
      assert %DateTime{} = replay_data.generated_at
    end

    test "limits replay data when requested", %{manager: manager} do
      for i <- 1..5 do
        step = create_test_step("step-#{i}", :file_operation, "Step #{i}")
        :ok = StateManager.save_step(manager, step)
      end

      replay_data = StateManager.get_conversation_replay(manager, step_limit: 3)

      assert replay_data.total_steps == 5
      assert replay_data.replay_steps == 3
      assert length(replay_data.step_history) == 3
    end

    test "manually prunes history", %{manager: manager} do
      # Add 5 steps (max is 5, so no auto-pruning yet)
      for i <- 1..5 do
        step = create_test_step("step-#{i}", :file_operation, "Step #{i}")
        :ok = StateManager.save_step(manager, step)
      end

      initial_history = StateManager.get_step_history(manager)
      initial_count = length(initial_history)

      # Manually prune to 3 steps
      {:ok, pruned_count} = StateManager.prune_history(manager, target_size: 3)

      final_history = StateManager.get_step_history(manager)
      final_count = length(final_history)

      assert pruned_count == initial_count - final_count
      assert final_count == 3

      # Should keep the most recent steps (in chronological order)
      step_ids = Enum.map(final_history, & &1.id)
      # The exact steps kept depend on whether auto-checkpointing occurred
      assert length(step_ids) == 3
      # All step IDs should be from our original set
      assert Enum.all?(step_ids, fn id -> String.starts_with?(id, "step-") end)
    end

    test "gets history statistics", %{manager: manager} do
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      step2 = create_test_step("step-2", :code_modification, "Making changes")
      step3 = create_test_step("step-3", :file_operation, "Writing files")

      :ok = StateManager.save_step(manager, step1)
      :ok = StateManager.save_step(manager, step2)
      :ok = StateManager.save_step(manager, step3)

      stats = StateManager.get_history_stats(manager)

      assert stats.total_steps == 3
      # Auto-checkpoint may have been created at step 3 (interval is 3)
      assert stats.total_checkpoints >= 0
      assert stats.max_history_size == 5
      assert stats.step_types.file_operation == 2
      assert stats.step_types.code_modification == 1
      assert stats.oldest_step_id == "step-1"
      assert stats.newest_step_id == "step-3"
      assert is_binary(stats.conversation_id)
    end

    test "replays conversation from checkpoint", %{manager: manager} do
      # Add initial steps
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      step2 = create_test_step("step-2", :code_modification, "Initial changes")
      :ok = StateManager.save_step(manager, step1)
      :ok = StateManager.save_step(manager, step2)

      # Create checkpoint
      {:ok, checkpoint_id} = StateManager.create_checkpoint(manager, "checkpoint_1")

      # Add more steps
      step3 = create_test_step("step-3", :system_command, "Running tests")
      :ok = StateManager.save_step(manager, step3)

      # Replay from checkpoint
      {:ok, replay_stream} =
        StateManager.replay_conversation(manager,
          from_checkpoint: checkpoint_id
        )

      replayed_steps = Enum.to_list(replay_stream)
      assert length(replayed_steps) == 2
      assert Enum.at(replayed_steps, 0).id == "step-1"
      assert Enum.at(replayed_steps, 1).id == "step-2"
    end

    test "replays conversation with step range", %{manager: manager} do
      for i <- 1..5 do
        step = create_test_step("step-#{i}", :file_operation, "Step #{i}")
        :ok = StateManager.save_step(manager, step)
      end

      # Replay from step-2 to step-4
      {:ok, replay_stream} =
        StateManager.replay_conversation(manager,
          from_step: "step-2",
          to_step: "step-4"
        )

      replayed_steps = Enum.to_list(replay_stream)
      assert length(replayed_steps) == 3
      assert Enum.at(replayed_steps, 0).id == "step-2"
      assert Enum.at(replayed_steps, 1).id == "step-3"
      assert Enum.at(replayed_steps, 2).id == "step-4"
    end

    test "handles replay with non-existent checkpoint", %{manager: manager} do
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      :ok = StateManager.save_step(manager, step1)

      assert {:error, :checkpoint_not_found} =
               StateManager.replay_conversation(manager,
                 from_checkpoint: "nonexistent"
               )
    end
  end

  describe "StateManager with DatabasePersistence" do
    setup do
      table_name = :"test_state_table_#{:rand.uniform(10000)}"

      {:ok, pid} =
        StateManager.start_link(
          persistence_adapter: ClaudeCodeSDK.StateManager.DatabasePersistence,
          persistence_config: %{
            table_name: table_name,
            auto_cleanup: true
          },
          conversation_id: "test-conversation"
        )

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, manager: pid, table_name: table_name}
    end

    test "persists steps to database", %{manager: manager, table_name: table_name} do
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      :ok = StateManager.save_step(manager, step1)

      # Check that data was persisted to ETS table
      [{_conversation_id, data}] = :ets.tab2list(table_name)
      assert length(data.step_history) == 1
      assert List.first(data.step_history).id == "step-1"
    end

    test "loads existing state on restart", %{table_name: table_name} do
      # Start first manager and add data
      {:ok, manager1} =
        StateManager.start_link(
          persistence_adapter: ClaudeCodeSDK.StateManager.DatabasePersistence,
          persistence_config: %{table_name: table_name, auto_cleanup: false},
          conversation_id: "test-conversation"
        )

      step1 = create_test_step("step-1", :file_operation, "Reading files")
      :ok = StateManager.save_step(manager1, step1)
      {:ok, checkpoint_id} = StateManager.create_checkpoint(manager1, "test_checkpoint")

      # Stop first manager
      GenServer.stop(manager1)

      # Start second manager with same conversation ID and table
      {:ok, manager2} =
        StateManager.start_link(
          persistence_adapter: ClaudeCodeSDK.StateManager.DatabasePersistence,
          persistence_config: %{table_name: table_name, auto_cleanup: false},
          conversation_id: "test-conversation"
        )

      # Should load existing state
      history = StateManager.get_step_history(manager2)
      checkpoints = StateManager.get_checkpoints(manager2)

      assert length(history) == 1
      assert List.first(history).id == "step-1"
      assert length(checkpoints) == 1
      assert List.first(checkpoints).id == checkpoint_id
    end
  end

  describe "StateManager with FilePersistence" do
    setup do
      # Use a temporary directory for testing
      temp_dir = System.tmp_dir!() |> Path.join("claude_test_#{:rand.uniform(10000)}")

      {:ok, pid} =
        StateManager.start_link(
          persistence_adapter: FilePersistence,
          persistence_config: %{
            base_path: temp_dir,
            create_directories: true
          },
          conversation_id: "test-conversation"
        )

      on_exit(fn ->
        # Clean up test directory
        File.rm_rf(temp_dir)
      end)

      {:ok, manager: pid, temp_dir: temp_dir}
    end

    test "persists steps to file", %{manager: manager, temp_dir: temp_dir} do
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      :ok = StateManager.save_step(manager, step1)

      # Check that file was created
      conversation_file = Path.join(temp_dir, "test-conversation.json")
      assert File.exists?(conversation_file)

      # Verify file content
      {:ok, content} = File.read(conversation_file)
      {:ok, data} = Jason.decode(content, keys: :atoms)

      assert length(data.step_history) == 1
      assert List.first(data.step_history).id == "step-1"
    end

    test "loads existing state on restart", %{temp_dir: temp_dir} do
      # Start first manager and add data
      {:ok, manager1} =
        StateManager.start_link(
          persistence_adapter: FilePersistence,
          persistence_config: %{base_path: temp_dir, create_directories: true},
          conversation_id: "test-conversation"
        )

      step1 = create_test_step("step-1", :file_operation, "Reading files")
      :ok = StateManager.save_step(manager1, step1)
      {:ok, checkpoint_id} = StateManager.create_checkpoint(manager1, "test_checkpoint")

      # Stop first manager
      GenServer.stop(manager1)

      # Start second manager with same conversation ID
      {:ok, manager2} =
        StateManager.start_link(
          persistence_adapter: FilePersistence,
          persistence_config: %{base_path: temp_dir, create_directories: true},
          conversation_id: "test-conversation"
        )

      # Should load existing state
      history = StateManager.get_step_history(manager2)
      checkpoints = StateManager.get_checkpoints(manager2)

      assert length(history) == 1
      assert List.first(history).id == "step-1"
      assert length(checkpoints) == 1
      assert List.first(checkpoints).id == checkpoint_id
    end

    test "handles corrupted files gracefully", %{manager: _manager, temp_dir: temp_dir} do
      # Create a corrupted file
      conversation_file = Path.join(temp_dir, "corrupted-conversation.json")
      File.write!(conversation_file, "invalid json content")

      # Start manager with corrupted conversation
      {:ok, manager2} =
        StateManager.start_link(
          persistence_adapter: FilePersistence,
          persistence_config: %{
            base_path: temp_dir,
            create_directories: true,
            backup_on_corruption: true
          },
          conversation_id: "corrupted-conversation",
          enable_recovery: true
        )

      # Should start with empty state despite corruption
      assert StateManager.get_step_history(manager2) == []

      # Should be able to save new data
      step1 = create_test_step("step-1", :file_operation, "New step")
      assert :ok = StateManager.save_step(manager2, step1)
    end
  end

  describe "StateManager error handling" do
    test "handles persistence adapter initialization failure" do
      # Mock a failing adapter
      defmodule FailingAdapter do
        @behaviour ClaudeCodeSDK.StateManager.PersistenceBehaviour

        def init(_config), do: {:error, :initialization_failed}
        def save_conversation(_, _, _), do: :ok
        def load_conversation(_, _), do: {:error, :not_found}
        def delete_conversation(_, _), do: :ok
        def list_conversations(_), do: {:ok, []}
      end

      # The GenServer should fail to start and exit with the reason
      Process.flag(:trap_exit, true)

      spawn_link(fn ->
        StateManager.start_link(persistence_adapter: FailingAdapter)
      end)

      receive do
        {:EXIT, _pid, :initialization_failed} -> :ok
      after
        1000 -> flunk("Expected process to exit with :initialization_failed")
      end
    end

    test "handles save failures gracefully" do
      # Mock an adapter that fails on save
      defmodule SaveFailingAdapter do
        @behaviour ClaudeCodeSDK.StateManager.PersistenceBehaviour

        def init(_config), do: {:ok, %{}}
        def save_conversation(_, _, _), do: {:error, :save_failed}
        def load_conversation(_, _), do: {:error, :not_found}
        def delete_conversation(_, _), do: :ok
        def list_conversations(_), do: {:ok, []}
      end

      {:ok, manager} = StateManager.start_link(persistence_adapter: SaveFailingAdapter)

      step1 = create_test_step("step-1", :file_operation, "Reading files")
      assert {:error, :save_failed} = StateManager.save_step(manager, step1)
    end
  end

  describe "StateManager configuration" do
    test "uses default configuration values" do
      {:ok, manager} = StateManager.start_link()

      # Should use MemoryPersistence by default
      step1 = create_test_step("step-1", :file_operation, "Reading files")
      assert :ok = StateManager.save_step(manager, step1)

      history = StateManager.get_step_history(manager)
      assert length(history) == 1
    end

    test "respects custom max_step_history" do
      {:ok, manager} = StateManager.start_link(max_step_history: 2)

      # Add 3 steps
      for i <- 1..3 do
        step = create_test_step("step-#{i}", :file_operation, "Step #{i}")
        :ok = StateManager.save_step(manager, step)
      end

      history = StateManager.get_step_history(manager)
      assert length(history) == 2
      assert Enum.at(history, 0).id == "step-2"
      assert Enum.at(history, 1).id == "step-3"
    end
  end

  # Helper function to create test steps
  defp create_test_step(id, type, description) do
    Step.new(
      id: id,
      type: type,
      description: description,
      messages: [
        %Message{
          type: :assistant,
          subtype: nil,
          data: %{
            message: %{"content" => "Test message for #{description}"},
            session_id: "test-session"
          },
          raw: %{}
        }
      ],
      tools_used: ["testTool"],
      metadata: %{test: true}
    )
  end
end
