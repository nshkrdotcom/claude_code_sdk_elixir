defmodule ClaudeCodeSDK.ModelSelectionLiveTest do
  use ExUnit.Case

  alias ClaudeCodeSDK.Options

  # These tests only run with mix test.live
  @moduletag :live

  setup do
    # Disable mocking for live tests
    Application.put_env(:claude_code_sdk, :use_mock, false)
    :ok
  end

  describe "real API model selection" do
    @tag timeout: 30_000
    test "sonnet model returns lower cost" do
      if System.get_env("LIVE_TESTS") != "true" do
        ExUnit.configure(exclude: [:live])
        {:skip, "Live tests disabled"}
      end

      options = %Options{
        model: "sonnet",
        verbose: true,
        output_format: :stream_json
      }

      messages = ClaudeCodeSDK.query("Say exactly: Test Sonnet", options) |> Enum.to_list()

      result_msg = Enum.find(messages, &(&1.type == :result))
      assert result_msg != nil
      assert result_msg.subtype == :success

      # Sonnet should be relatively cheap (under $0.05)
      assert result_msg.data.total_cost_usd < 0.05

      IO.puts("✅ Sonnet cost: $#{result_msg.data.total_cost_usd}")
    end

    @tag timeout: 30_000
    test "opus model returns higher cost" do
      if System.get_env("LIVE_TESTS") != "true" do
        ExUnit.configure(exclude: [:live])
        {:skip, "Live tests disabled"}
      end

      options = %Options{
        model: "opus",
        verbose: true,
        output_format: :stream_json
      }

      messages = ClaudeCodeSDK.query("Say exactly: Test Opus", options) |> Enum.to_list()

      result_msg = Enum.find(messages, &(&1.type == :result))
      assert result_msg != nil
      assert result_msg.subtype == :success

      # Opus should be more expensive than Sonnet (expect > $0.01)
      assert result_msg.data.total_cost_usd > 0.01

      IO.puts("✅ Opus cost: $#{result_msg.data.total_cost_usd}")
    end

    @tag timeout: 30_000
    test "cost difference between models" do
      if System.get_env("LIVE_TESTS") != "true" do
        ExUnit.configure(exclude: [:live])
        {:skip, "Live tests disabled"}
      end

      # Test sonnet
      sonnet_options = %Options{
        model: "sonnet",
        verbose: true,
        output_format: :stream_json
      }

      sonnet_messages =
        ClaudeCodeSDK.query("Say exactly: Cost test", sonnet_options) |> Enum.to_list()

      sonnet_result = Enum.find(sonnet_messages, &(&1.type == :result))

      # Test opus
      opus_options = %Options{
        model: "opus",
        verbose: true,
        output_format: :stream_json
      }

      opus_messages =
        ClaudeCodeSDK.query("Say exactly: Cost test", opus_options) |> Enum.to_list()

      opus_result = Enum.find(opus_messages, &(&1.type == :result))

      assert sonnet_result != nil
      assert opus_result != nil
      assert sonnet_result.subtype == :success
      assert opus_result.subtype == :success

      sonnet_cost = sonnet_result.data.total_cost_usd
      opus_cost = opus_result.data.total_cost_usd

      # Opus should be significantly more expensive than Sonnet
      assert opus_cost > sonnet_cost

      ratio = opus_cost / sonnet_cost
      # Opus should be at least 2x more expensive
      assert ratio > 2.0

      IO.puts("✅ Cost comparison:")
      IO.puts("   Sonnet: $#{Float.round(sonnet_cost, 4)}")
      IO.puts("   Opus:   $#{Float.round(opus_cost, 4)}")
      IO.puts("   Ratio:  #{Float.round(ratio, 1)}x")
    end

    @tag timeout: 30_000
    test "fallback model configuration works" do
      if System.get_env("LIVE_TESTS") != "true" do
        ExUnit.configure(exclude: [:live])
        {:skip, "Live tests disabled"}
      end

      options = %Options{
        model: "opus",
        fallback_model: "sonnet",
        verbose: true,
        output_format: :stream_json
      }

      messages = ClaudeCodeSDK.query("Say exactly: Fallback test", options) |> Enum.to_list()

      result_msg = Enum.find(messages, &(&1.type == :result))
      assert result_msg != nil
      assert result_msg.subtype == :success

      # Should succeed with either model
      assert result_msg.data.total_cost_usd > 0

      IO.puts("✅ Fallback test cost: $#{result_msg.data.total_cost_usd}")
    end

    @tag timeout: 30_000
    test "preset options work with live API" do
      if System.get_env("LIVE_TESTS") != "true" do
        ExUnit.configure(exclude: [:live])
        {:skip, "Live tests disabled"}
      end

      alias ClaudeCodeSDK.OptionBuilder

      # Test development preset (sonnet)
      dev_options = OptionBuilder.build_development_options()
      dev_messages = ClaudeCodeSDK.query("Say exactly: Dev test", dev_options) |> Enum.to_list()
      dev_result = Enum.find(dev_messages, &(&1.type == :result))

      assert dev_result != nil
      assert dev_result.subtype == :success
      # Should be cheap (sonnet)
      assert dev_result.data.total_cost_usd < 0.05

      IO.puts("✅ Development preset cost: $#{dev_result.data.total_cost_usd}")
    end
  end
end
