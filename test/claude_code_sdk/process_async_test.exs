defmodule ClaudeCodeSDK.ProcessAsyncTest do
  use ExUnit.Case

  alias ClaudeCodeSDK.{Mock, Options, ProcessAsync}

  setup do
    # Clear any previous mock responses before each test
    Mock.clear_responses()
    :ok
  end

  describe "ProcessAsync.stream/3" do
    test "returns a stream that yields messages asynchronously" do
      # Set up a specific mock response
      Mock.set_response("async test", [
        %{
          "type" => "system",
          "subtype" => "init",
          "session_id" => "async-123",
          "model" => "claude-test",
          "tools" => ["bash", "editor"],
          "cwd" => "/test/async",
          "permissionMode" => "default",
          "apiKeySource" => "test"
        },
        %{
          "type" => "assistant",
          "message" => %{
            "role" => "assistant",
            "content" => "Processing async request..."
          },
          "session_id" => "async-123"
        },
        %{
          "type" => "assistant",
          "message" => %{
            "role" => "assistant",
            "content" => "Async operation complete!"
          },
          "session_id" => "async-123"
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "async-123",
          "total_cost_usd" => 0.002,
          "duration_ms" => 200,
          "duration_api_ms" => 100,
          "num_turns" => 1,
          "is_error" => false
        }
      ])

      options = %Options{output_format: :stream_json}
      messages = ProcessAsync.stream(["async test"], options) |> Enum.to_list()

      assert length(messages) == 4
      assert Enum.at(messages, 0).type == :system
      assert Enum.at(messages, 1).type == :assistant
      assert Enum.at(messages, 2).type == :assistant
      assert Enum.at(messages, 3).type == :result

      # Check system message
      system_msg = Enum.at(messages, 0)
      assert system_msg.data["session_id"] == "async-123"
      assert system_msg.data["tools"] == ["bash", "editor"]

      # Check assistant messages
      first_assistant = Enum.at(messages, 1)
      assert first_assistant.data.message["content"] == "Processing async request..."

      second_assistant = Enum.at(messages, 2)
      assert second_assistant.data.message["content"] == "Async operation complete!"

      # Check result message
      result_msg = Enum.at(messages, 3)
      assert result_msg.subtype == :success
      assert result_msg.data["total_cost_usd"] == 0.002
    end

    test "handles stdin input" do
      Mock.set_response("stdin content", [
        %{
          "type" => "system",
          "subtype" => "init",
          "session_id" => "stdin-async"
        },
        %{
          "type" => "user",
          "message" => %{
            "role" => "user",
            "content" => "stdin content"
          },
          "session_id" => "stdin-async"
        },
        %{
          "type" => "assistant",
          "message" => %{
            "role" => "assistant",
            "content" => "Received stdin input"
          },
          "session_id" => "stdin-async"
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "stdin-async"
        }
      ])

      options = %Options{}
      messages = ProcessAsync.stream([], options, "stdin content") |> Enum.to_list()

      assert length(messages) == 4

      # Check user message
      user_msg = Enum.find(messages, &(&1.type == :user))
      assert user_msg.data.message["content"] == "stdin content"
    end

    test "messages are yielded as they arrive (streaming behavior)" do
      # Set up a response with multiple assistant messages
      Mock.set_response("streaming test", [
        %{
          "type" => "system",
          "subtype" => "init",
          "session_id" => "stream-123"
        },
        %{
          "type" => "assistant",
          "message" => %{"content" => "First chunk..."},
          "session_id" => "stream-123"
        },
        %{
          "type" => "assistant",
          "message" => %{"content" => "Second chunk..."},
          "session_id" => "stream-123"
        },
        %{
          "type" => "assistant",
          "message" => %{"content" => "Third chunk..."},
          "session_id" => "stream-123"
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "stream-123"
        }
      ])

      options = %Options{}
      stream = ProcessAsync.stream(["streaming test"], options)

      # Take messages one by one to verify streaming behavior
      messages = Enum.take(stream, 5)

      assert length(messages) == 5
      assert Enum.count(messages, &(&1.type == :assistant)) == 3
    end

    test "handles error responses" do
      Mock.set_response("error test", [
        %{
          "type" => "system",
          "subtype" => "init",
          "session_id" => "error-123"
        },
        %{
          "type" => "result",
          "subtype" => "error_during_execution",
          "session_id" => "error-123",
          "error" => "Something went wrong",
          "is_error" => true
        }
      ])

      options = %Options{}
      messages = ProcessAsync.stream(["error test"], options) |> Enum.to_list()

      assert length(messages) == 2

      result_msg = Enum.at(messages, 1)
      assert result_msg.type == :result
      assert result_msg.subtype == :error_during_execution
      assert result_msg.data["error"] == "Something went wrong"
      assert result_msg.data["is_error"] == true
    end

    test "properly identifies final messages" do
      Mock.set_response("final test", [
        %{
          "type" => "assistant",
          "message" => %{"content" => "Working..."},
          "session_id" => "final-123"
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "final-123"
        }
      ])

      options = %Options{}
      messages = ProcessAsync.stream(["final test"], options) |> Enum.to_list()

      # The stream should stop after the result message
      assert length(messages) == 2
      assert List.last(messages).type == :result
    end

    test "handles empty responses gracefully" do
      Mock.set_response("empty test", [])

      options = %Options{}
      messages = ProcessAsync.stream(["empty test"], options) |> Enum.to_list()

      assert messages == []
    end

    test "extracts prompt from various argument formats" do
      # Test with flags and prompt
      Mock.set_response("hello world", [
        %{
          "type" => "assistant",
          "message" => %{"content" => "Got: hello world"}
        },
        %{
          "type" => "result",
          "subtype" => "success"
        }
      ])

      options = %Options{}

      messages =
        ProcessAsync.stream(["--output-format", "json", "hello world"], options)
        |> Enum.to_list()

      assistant_msg = Enum.find(messages, &(&1.type == :assistant))
      assert assistant_msg.data.message["content"] == "Got: hello world"
    end

    test "preserves message structure and data" do
      Mock.set_response("structure test", [
        %{
          "type" => "system",
          "subtype" => "tool_use",
          "session_id" => "struct-123",
          "tool" => "bash",
          "command" => "ls -la",
          "output" => "file1.txt\nfile2.txt"
        }
      ])

      options = %Options{}
      messages = ProcessAsync.stream(["structure test"], options) |> Enum.to_list()

      system_msg = Enum.at(messages, 0)
      assert system_msg.type == :system
      assert system_msg.subtype == :tool_use
      assert system_msg.data["tool"] == "bash"
      assert system_msg.data["command"] == "ls -la"
      assert system_msg.data["output"] == "file1.txt\nfile2.txt"
    end

    test "works with custom options" do
      Mock.set_response("options test", [
        %{
          "type" => "system",
          "subtype" => "init",
          "session_id" => "opts-123",
          "max_turns" => 5
        },
        %{
          "type" => "result",
          "subtype" => "success"
        }
      ])

      options = %Options{
        max_turns: 5,
        verbose: true
      }

      messages = ProcessAsync.stream(["options test"], options) |> Enum.to_list()

      system_msg = Enum.find(messages, &(&1.type == :system))
      assert system_msg.data["max_turns"] == 5
    end
  end

  describe "integration with main API" do
    test "works through ClaudeCodeSDK.query with async option" do
      Mock.set_response("integration test", [
        %{
          "type" => "assistant",
          "message" => %{"content" => "Async integration works!"}
        },
        %{
          "type" => "result",
          "subtype" => "success"
        }
      ])

      # Note: This test assumes that ProcessAsync would be used when
      # stream_json output format is specified or when async: true option exists
      options = %Options{output_format: :stream_json}
      messages = ClaudeCodeSDK.query("integration test", options) |> Enum.to_list()

      assistant_msg = Enum.find(messages, &(&1.type == :assistant))
      assert assistant_msg.data.message["content"] == "Async integration works!"
    end
  end
end
