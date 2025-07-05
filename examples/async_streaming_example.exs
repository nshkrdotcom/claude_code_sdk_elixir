#!/usr/bin/env elixir

# Async Streaming Example
# This example demonstrates the async streaming functionality of ClaudeCodeSDK.
# It shows how messages are streamed in real-time as they arrive from the Claude CLI.

Mix.install([
  {:claude_code_sdk, path: ".."}
])

defmodule AsyncStreamingExample do
  def run do
    IO.puts("ClaudeCodeSDK Async Streaming Example")
    IO.puts("=====================================\n")

    # Example 1: Basic async streaming with stream_json format
    IO.puts("Example 1: Basic async streaming")
    IO.puts("--------------------------------")
    
    options = %ClaudeCodeSDK.Options{
      output_format: :stream_json,  # This triggers async mode
      verbose: true
    }
    
    ClaudeCodeSDK.query("Write a function to calculate factorial", options)
    |> Stream.each(fn message ->
      IO.puts("Received #{message.type} message")
      
      case message.type do
        :assistant ->
          IO.puts("Assistant: #{message.data.message["content"]}")
          
        :system ->
          IO.puts("System: #{message.subtype || "init"}")
          
        :result ->
          IO.puts("Result: #{message.subtype || "complete"}")
          if message.data["total_cost_usd"] do
            IO.puts("Cost: $#{message.data["total_cost_usd"]}")
          end
          
        _ ->
          IO.puts("Data: #{inspect(message.data)}")
      end
      
      IO.puts("")
    end)
    |> Enum.to_list()
    
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    # Example 2: Force async mode with the async option
    IO.puts("Example 2: Force async mode")
    IO.puts("---------------------------")
    
    options = %ClaudeCodeSDK.Options{
      async: true,  # Force async streaming
      max_turns: 3
    }
    
    start_time = System.monotonic_time(:millisecond)
    message_count = 0
    
    messages = ClaudeCodeSDK.query("Explain how async/await works in JavaScript", options)
    |> Stream.map(fn message ->
      elapsed = System.monotonic_time(:millisecond) - start_time
      IO.puts("[#{elapsed}ms] Received: #{message.type}")
      message
    end)
    |> Enum.to_list()
    
    IO.puts("\nTotal messages received: #{length(messages)}")
    
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    # Example 3: Compare sync vs async timing
    IO.puts("Example 3: Sync vs Async comparison")
    IO.puts("-----------------------------------")
    
    prompt = "List 3 programming languages"
    
    # Sync mode
    IO.puts("Running in SYNC mode...")
    sync_start = System.monotonic_time(:millisecond)
    
    sync_options = %ClaudeCodeSDK.Options{
      output_format: :json  # Regular JSON triggers sync mode
    }
    
    sync_messages = ClaudeCodeSDK.query(prompt, sync_options) |> Enum.to_list()
    sync_duration = System.monotonic_time(:millisecond) - sync_start
    
    IO.puts("Sync mode completed in #{sync_duration}ms")
    IO.puts("Messages received: #{length(sync_messages)}")
    
    IO.puts("\nRunning in ASYNC mode...")
    async_start = System.monotonic_time(:millisecond)
    first_message_time = nil
    
    async_options = %ClaudeCodeSDK.Options{
      async: true
    }
    
    async_messages = ClaudeCodeSDK.query(prompt, async_options)
    |> Stream.map(fn message ->
      if is_nil(first_message_time) do
        first_message_time = System.monotonic_time(:millisecond) - async_start
        IO.puts("First message received after #{first_message_time}ms")
      end
      message
    end)
    |> Enum.to_list()
    
    async_duration = System.monotonic_time(:millisecond) - async_start
    
    IO.puts("Async mode completed in #{async_duration}ms")
    IO.puts("Messages received: #{length(async_messages)}")
    
    IO.puts("\n" <> String.duplicate("=", 50) <> "\n")

    # Example 4: Handling streaming with early termination
    IO.puts("Example 4: Early termination")
    IO.puts("----------------------------")
    
    options = %ClaudeCodeSDK.Options{
      async: true
    }
    
    # Take only the first 3 messages
    messages = ClaudeCodeSDK.query("Write a long essay about Elixir", options)
    |> Stream.take_while(fn message ->
      # Stop after receiving the first assistant message
      message.type != :assistant
    end)
    |> Enum.to_list()
    
    IO.puts("Stopped after #{length(messages)} messages")
    IO.puts("Message types: #{Enum.map(messages, & &1.type) |> inspect()}")
    
    IO.puts("\nAsync streaming examples completed!")
  end
end

# Run the example
AsyncStreamingExample.run()