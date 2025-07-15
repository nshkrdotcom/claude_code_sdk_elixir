defmodule ClaudeCodeSDKTest do
  use ExUnit.Case
  doctest ClaudeCodeSDK

  alias ClaudeCodeSDK.{Mock, Options}

  setup do
    # Clear any previous mock responses before each test
    Mock.clear_responses()
    :ok
  end

  describe "query/2" do
    test "returns a stream with mocked responses" do
      # Set up a specific mock response
      Mock.set_response("test prompt", [
        %{
          "type" => "system",
          "subtype" => "init",
          "session_id" => "test-123",
          "model" => "claude-test",
          "tools" => [],
          "cwd" => "/test",
          "permissionMode" => "default",
          "apiKeySource" => "test"
        },
        %{
          "type" => "assistant",
          "message" => %{
            "role" => "assistant",
            "content" => "Test response"
          },
          "session_id" => "test-123"
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "test-123",
          "total_cost_usd" => 0.001,
          "duration_ms" => 100,
          "duration_api_ms" => 50,
          "num_turns" => 1,
          "is_error" => false
        }
      ])

      messages = ClaudeCodeSDK.query("test prompt") |> Enum.to_list()

      assert length(messages) == 3
      assert Enum.at(messages, 0).type == :system
      assert Enum.at(messages, 1).type == :assistant
      assert Enum.at(messages, 2).type == :result

      # Check assistant message content
      assistant_msg = Enum.at(messages, 1)
      assert assistant_msg.data.message["content"] == "Test response"
    end

    test "accepts options" do
      opts = %Options{max_turns: 3, output_format: :json}
      messages = ClaudeCodeSDK.query("test prompt", opts) |> Enum.to_list()

      assert length(messages) > 0
      assert Enum.any?(messages, &(&1.type == :assistant))
    end
  end

  describe "continue/2" do
    test "continues without prompt" do
      result = ClaudeCodeSDK.continue()
      assert is_function(result, 2)
    end

    test "continues with prompt" do
      result = ClaudeCodeSDK.continue("additional prompt")
      assert is_function(result, 2)
    end
  end

  describe "resume/3" do
    test "resumes with session ID" do
      result = ClaudeCodeSDK.resume("test-session-id")
      assert is_function(result, 2)
    end

    test "resumes with session ID and prompt" do
      result = ClaudeCodeSDK.resume("test-session-id", "additional prompt")
      assert is_function(result, 2)
    end
  end

  describe "model selection integration" do
    test "query with sonnet model (mock mode)" do
      Mock.set_response("test sonnet", [
        %{
          "type" => "assistant",
          "message" => %{"content" => "Hello from Sonnet!"}
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "total_cost_usd" => 0.01,
          "duration_ms" => 100,
          "duration_api_ms" => 50,
          "num_turns" => 1,
          "is_error" => false,
          "session_id" => "test-123"
        }
      ])

      options = %Options{model: "sonnet"}
      messages = ClaudeCodeSDK.query("test sonnet", options) |> Enum.to_list()

      # Should receive mock response
      assert length(messages) >= 1
      assistant_msg = Enum.find(messages, &(&1.type == :assistant))
      result_msg = Enum.find(messages, &(&1.type == :result))

      assert assistant_msg != nil
      assert result_msg != nil
      assert result_msg.subtype == :success
    end

    test "query with opus model (mock mode)" do
      Mock.set_response("test opus", [
        %{
          "type" => "assistant",
          "message" => %{"content" => "Hello from Opus!"}
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "total_cost_usd" => 0.26,
          "duration_ms" => 200,
          "duration_api_ms" => 100,
          "num_turns" => 1,
          "is_error" => false,
          "session_id" => "test-456"
        }
      ])

      options = %Options{model: "opus"}
      messages = ClaudeCodeSDK.query("test opus", options) |> Enum.to_list()

      # Should receive mock response
      assert length(messages) >= 1
      assistant_msg = Enum.find(messages, &(&1.type == :assistant))
      result_msg = Enum.find(messages, &(&1.type == :result))

      assert assistant_msg != nil
      assert result_msg != nil
      assert result_msg.subtype == :success
    end

    test "preset options include correct models" do
      alias ClaudeCodeSDK.OptionBuilder

      # Development should use sonnet
      dev_options = OptionBuilder.build_development_options()
      assert dev_options.model == "sonnet"

      # Production should use opus with sonnet fallback
      prod_options = OptionBuilder.build_production_options()
      assert prod_options.model == "opus"
      assert prod_options.fallback_model == "sonnet"

      # Analysis should use opus
      analysis_options = OptionBuilder.build_analysis_options()
      assert analysis_options.model == "opus"
    end

    test "model selection preserves other options" do
      options = %Options{
        model: "sonnet",
        max_turns: 5,
        verbose: true,
        system_prompt: "Test"
      }

      # Model selection shouldn't affect other fields
      assert options.max_turns == 5
      assert options.verbose == true
      assert options.system_prompt == "Test"
      assert options.model == "sonnet"
    end
  end
end
