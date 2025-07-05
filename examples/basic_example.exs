#!/usr/bin/env elixir

# Basic Example - Simple Claude SDK usage
# Usage: mix run.live examples/basic_example.exs

alias ClaudeCodeSDK.{ContentExtractor, OptionBuilder}

# Check if we're in live mode
if Application.get_env(:claude_code_sdk, :use_mock, false) do
  {:ok, _} = ClaudeCodeSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

defmodule BasicExample do
  def run do
    IO.puts("🚀 Basic Claude SDK Example")
    IO.puts("Asking Claude to write a simple function...")

    # Create simple options for basic usage - use development options for more capability
    options = OptionBuilder.merge(:development, %{max_turns: 10})

    # Make a simple query
    IO.puts("\n📝 Claude's Response:")
    IO.puts("=" |> String.duplicate(60))
    
    ClaudeCodeSDK.query("""
    Write a simple Elixir function that calculates the factorial of a number.
    Include proper documentation and a basic example of how to use it.
    Keep it concise and clear.
    """, options)
    |> stream_response()
    
    IO.puts("\n" <> "=" |> String.duplicate(60))
    IO.puts("✅ Example complete!")
  end

  defp stream_response(stream) do
    stream
    |> Enum.each(fn message ->
      case message do
        %{type: :result, subtype: subtype} when subtype != :success ->
          IO.puts("\n❌ Error (#{subtype}):")
          if Map.has_key?(message.data, :error) do
            IO.puts(message.data.error)
          else
            IO.puts(inspect(message.data))
          end
          System.halt(1)
          
        %{type: :assistant} ->
          text = ContentExtractor.extract_text(message)
          if text, do: IO.write(text)
          
        _ ->
          # Ignore other message types for now
          :ok
      end
    end)
  end
end

# Run the example
BasicExample.run()