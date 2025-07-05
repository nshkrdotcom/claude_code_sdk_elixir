#!/usr/bin/env elixir

# CLI Streaming Test - Demonstrates real-time streaming with delays
# Usage: mix run.live examples/cli_streaming_test.exs

alias ClaudeCodeSDK.{ContentExtractor, OptionBuilder}

if Application.get_env(:claude_code_sdk, :use_mock, false) do
  {:ok, _} = ClaudeCodeSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

defmodule CLIStreamingTest do
  def run do
    IO.puts("🚀 CLI Streaming Test")
    IO.puts("This example demonstrates real-time streaming with delays")
    IO.puts("Watch as Claude responds, waits, and responds again...\n")

    options = OptionBuilder.merge(:development, %{max_turns: 1})
    
    # Track timing
    start_time = System.monotonic_time(:millisecond)
    last_time = start_time

    # Send the prompt that will cause Claude to output with delays
    ClaudeCodeSDK.query("""
    say hello. then wait 5 second and say that you're waiting. then in a second response say hi
    """, options)
    |> Enum.reduce(last_time, fn message, prev_time ->
      current_time = System.monotonic_time(:millisecond)
      elapsed = current_time - start_time
      delta = current_time - prev_time
      
      case message do
        %{type: :assistant} = msg ->
          IO.puts("\n[+#{elapsed}ms, Δ#{delta}ms] Assistant message received")
          
          # Extract and display text content
          text = ContentExtractor.extract_text(msg)
          if text do
            IO.puts("  Text: #{inspect(text)}")
            IO.write("  >>> ")
            text
            |> String.replace("\\n", "\n")
            |> IO.write()
            IO.puts("")
          end
          
          # Check for tool uses
          if msg.data[:message] && msg.data[:message]["content"] do
            Enum.each(msg.data[:message]["content"], fn
              %{"type" => "tool_use", "name" => name, "input" => input} ->
                IO.puts("  Tool use: #{name}")
                IO.puts("    Input: #{inspect(input)}")
              _ ->
                :ok
            end)
          end
          
        %{type: :user} ->
          IO.puts("\n[+#{elapsed}ms, Δ#{delta}ms] Tool result sent back")
          
        %{type: :system, subtype: subtype} ->
          IO.puts("\n[+#{elapsed}ms, Δ#{delta}ms] System: #{subtype}")
          
        %{type: :result, subtype: :success} = msg ->
          IO.puts("\n[+#{elapsed}ms, Δ#{delta}ms] Final result")
          if msg.data && msg.data["usage"] do
            IO.puts("  Total cost: $#{msg.data["total_cost_usd"]}")
            IO.puts("  Duration: #{msg.data["duration_ms"]}ms")
          end
          
        %{type: :result, subtype: subtype} = msg ->
          IO.puts("\n[+#{elapsed}ms, Δ#{delta}ms] Result: #{subtype}")
          IO.puts("  Details: #{inspect(msg.data)}")
          
        _ ->
          IO.puts("\n[+#{elapsed}ms, Δ#{delta}ms] Unknown message type: #{inspect(message)}")
      end
      
      current_time
    end)
    
    total_elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("\n✅ Done! Total time: #{total_elapsed}ms")
  end
end

CLIStreamingTest.run()