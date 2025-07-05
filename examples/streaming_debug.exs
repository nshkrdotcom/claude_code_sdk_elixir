#!/usr/bin/env elixir

# Streaming Debug Example - Shows message timing
# Usage: mix run.live examples/streaming_debug.exs

alias ClaudeCodeSDK.{ContentExtractor, OptionBuilder}

if Application.get_env(:claude_code_sdk, :use_mock, false) do
  {:ok, _} = ClaudeCodeSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end


defmodule StreamingDebug do
  def run do
    IO.puts("🚀 Streaming Debug Example")
    IO.puts("Tracking message arrival times...\n")

    options = OptionBuilder.merge(:development, %{max_turns: 10})
    start_time = System.monotonic_time(:millisecond)

    ClaudeCodeSDK.query("""
    Do these two steps:
    1. Say "one"
    2. Say "two"
    """, options)
    |> Enum.each(fn message ->
      elapsed = System.monotonic_time(:millisecond) - start_time
      
      case message do
        %{type: :assistant} = msg ->
          IO.puts("[#{elapsed}ms] Assistant message arrived")
          IO.puts("Message data: #{inspect(msg, limit: :infinity, pretty: true)}")
          text = ContentExtractor.extract_text(message)
          if text do
            IO.puts("Extracted text: #{inspect(text)}")
            text
            |> String.replace("\\n", "\n")
            |> IO.write()
            IO.puts("")  # Add newline after each message for clarity
          end
          
        %{type: type} ->
          IO.puts("[#{elapsed}ms] #{type} message")
          
        _ ->
          IO.puts("[#{elapsed}ms] Unknown message type")
      end
    end)
    
    IO.puts("\n✅ Done!")
  end
end

StreamingDebug.run()