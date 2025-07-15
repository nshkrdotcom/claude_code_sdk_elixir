defmodule ClaudeCodeSDK.OptionsTest do
  use ExUnit.Case

  alias ClaudeCodeSDK.Options

  describe "model CLI args generation" do
    test "generates --model flag for model option" do
      options = %Options{model: "sonnet"}
      args = Options.to_args(options)

      assert "--model" in args
      assert "sonnet" in args
      # Check they are adjacent
      model_index = Enum.find_index(args, &(&1 == "--model"))
      assert Enum.at(args, model_index + 1) == "sonnet"
    end

    test "generates --fallback-model flag for fallback option" do
      options = %Options{fallback_model: "sonnet"}
      args = Options.to_args(options)

      assert "--fallback-model" in args
      assert "sonnet" in args
      # Check they are adjacent
      fallback_index = Enum.find_index(args, &(&1 == "--fallback-model"))
      assert Enum.at(args, fallback_index + 1) == "sonnet"
    end

    test "omits model flags when nil" do
      options = %Options{model: nil, fallback_model: nil}
      args = Options.to_args(options)

      refute "--model" in args
      refute "--fallback-model" in args
    end

    test "handles model shortcuts (sonnet, opus)" do
      sonnet_options = %Options{model: "sonnet"}
      sonnet_args = Options.to_args(sonnet_options)
      assert "--model" in sonnet_args
      assert "sonnet" in sonnet_args

      opus_options = %Options{model: "opus"}
      opus_args = Options.to_args(opus_options)
      assert "--model" in opus_args
      assert "opus" in opus_args
    end

    test "handles both model and fallback model together" do
      options = %Options{model: "opus", fallback_model: "sonnet"}
      args = Options.to_args(options)

      assert "--model" in args
      assert "opus" in args
      assert "--fallback-model" in args
      assert "sonnet" in args

      # Verify correct pairing
      model_index = Enum.find_index(args, &(&1 == "--model"))
      fallback_index = Enum.find_index(args, &(&1 == "--fallback-model"))
      assert Enum.at(args, model_index + 1) == "opus"
      assert Enum.at(args, fallback_index + 1) == "sonnet"
    end

    test "model flags are positioned correctly with other options" do
      options = %Options{
        model: "sonnet",
        max_turns: 5,
        verbose: true,
        fallback_model: "opus"
      }

      args = Options.to_args(options)

      # Should contain all expected flags
      assert "--model" in args
      assert "sonnet" in args
      assert "--fallback-model" in args
      assert "opus" in args
      assert "--max-turns" in args
      assert "5" in args
      assert "--verbose" in args
    end

    test "handles custom model names" do
      options = %Options{model: "claude-custom-model"}
      args = Options.to_args(options)

      assert "--model" in args
      assert "claude-custom-model" in args
    end
  end

  describe "option combinations with model selection" do
    test "model selection works with all other options" do
      options = %Options{
        model: "opus",
        fallback_model: "sonnet",
        max_turns: 10,
        system_prompt: "Test prompt",
        output_format: :stream_json,
        allowed_tools: ["Read", "Write"],
        disallowed_tools: ["Bash"],
        permission_mode: :accept_edits,
        verbose: true
      }

      args = Options.to_args(options)

      # Model flags
      assert "--model" in args
      assert "opus" in args
      assert "--fallback-model" in args
      assert "sonnet" in args

      # Other flags should still work
      assert "--max-turns" in args
      assert "--system-prompt" in args
      assert "--output-format" in args
      assert "--allowedTools" in args
      assert "--disallowedTools" in args
      assert "--permission-mode" in args
      assert "--verbose" in args
    end
  end

  describe "edge cases" do
    test "handles empty string model" do
      options = %Options{model: ""}
      args = Options.to_args(options)

      assert "--model" in args
      assert "" in args
    end

    test "new/1 function sets model fields correctly" do
      options = Options.new(model: "sonnet", fallback_model: "opus")

      assert options.model == "sonnet"
      assert options.fallback_model == "opus"
    end

    test "struct pattern matching works with model fields" do
      options = %Options{model: "opus"}

      assert %Options{model: "opus"} = options
    end
  end
end
