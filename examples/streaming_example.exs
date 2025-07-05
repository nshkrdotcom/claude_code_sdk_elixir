#!/usr/bin/env elixir

# Streaming Example - Shows real-time streaming
# Usage: mix run.live examples/streaming_example.exs

alias ClaudeCodeSDK.{ContentExtractor, OptionBuilder}

if Application.get_env(:claude_code_sdk, :use_mock, false) do
  {:ok, _} = ClaudeCodeSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

defmodule StreamingExample do
  def run do
    IO.puts("🚀 Streaming Example")
    IO.puts("Watch Claude's response stream in real-time...\n")

    options = OptionBuilder.merge(:development, %{max_turns: 10})

    ClaudeCodeSDK.query("""
    Do these two steps:
    1. Say "one"
    2. Say "two"
    """, options)
    |> Enum.each(fn message ->
      case message do
        %{type: :assistant} ->
          text = ContentExtractor.extract_text(message)
          if text do
            # Replace escaped newlines with actual newlines
            text
            |> String.replace("\\n", "\n")
            |> IO.write()
          end
          
        %{type: :result, subtype: subtype} when subtype != :success ->
          IO.puts("\n❌ Error: #{inspect(message.data)}")
          System.halt(1)
          
        _ ->
          :ok
      end
    end)
    
    IO.puts("\n✅ Done!")
  end
end

StreamingExample.run()