#!/usr/bin/env elixir

# Debug Example - Shows raw CLI commands
# Usage: mix run.live examples/debug_example.exs

alias ClaudeCodeSDK.{ContentExtractor, OptionBuilder}

if Application.get_env(:claude_code_sdk, :use_mock, false) do
  {:ok, _} = ClaudeCodeSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

defmodule DebugExample do
  def run do
    IO.puts("🔍 Debug Example - Verbose Mode")
    IO.puts("This will show the raw CLI command being executed\n")

    # Enable verbose mode to see the raw command
    options = %ClaudeCodeSDK.Options{
      verbose: true,
      output_format: :stream_json,
      max_turns: 1
    }

    IO.puts("Executing query with verbose mode enabled...")
    
    ClaudeCodeSDK.query("Say hello", options)
    |> Enum.each(fn message ->
      case message do
        %{type: :assistant} ->
          text = ContentExtractor.extract_text(message)
          if text do
            IO.puts("\n📝 Assistant response:")
            IO.puts(String.replace(text, "\\n", "\n"))
          end
          
        %{type: :result} ->
          IO.puts("\n✅ Query completed")
          
        _ ->
          :ok
      end
    end)
  end
end

DebugExample.run()