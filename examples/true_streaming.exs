#!/usr/bin/env elixir

# True Streaming Example - Forces longer output to see streaming
# Usage: mix run.live examples/true_streaming.exs

alias ClaudeCodeSDK.{ContentExtractor, OptionBuilder}

if Application.get_env(:claude_code_sdk, :use_mock, false) do
  {:ok, _} = ClaudeCodeSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

defmodule TrueStreaming do
  def run do
    IO.puts("🚀 True Streaming Example")
    IO.puts("Requesting longer output to see real streaming...\n")

    options = OptionBuilder.merge(:development, %{max_turns: 10})
    start_time = System.monotonic_time(:millisecond)
    last_time = start_time
    message_count = 0

    ClaudeCodeSDK.query("""
    Count from 1 to 20, with each number on its own line.
    """, options)
    |> Stream.each(fn message ->
      current_time = System.monotonic_time(:millisecond)
      elapsed = current_time - start_time
      delta = current_time - last_time
      
      case message do
        %{type: :assistant} ->
          message_count = message_count + 1
          if message_count == 1 do
            IO.puts("\n[#{elapsed}ms, +#{delta}ms] First assistant message:")
          end
          
          text = ContentExtractor.extract_text(message)
          if text do
            text
            |> String.replace("\\n", "\n")
            |> IO.write()
          end
          
        %{type: :result} ->
          IO.puts("\n[#{elapsed}ms, +#{delta}ms] Result message")
          
        _ ->
          :ok
      end
      
      last_time = current_time
    end)
    |> Stream.run()
    
    IO.puts("\n✅ Done!")
  end
end

TrueStreaming.run()