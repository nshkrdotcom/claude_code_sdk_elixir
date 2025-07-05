defmodule ClaudeCodeSDK.Mock.ProcessAsync do
  @moduledoc """
  Mock async process implementation that simulates streaming responses.

  This module provides a drop-in replacement for `ClaudeCodeSDK.ProcessAsync` when
  the mock system is enabled. It simulates the async streaming behavior by sending
  mock messages to the calling process in a similar way to the real async implementation.
  """

  alias ClaudeCodeSDK.{Message, Mock, Options}

  @spec stream([String.t()], Options.t(), String.t() | nil) :: Enumerable.t()
  @doc """
  Streams mock messages asynchronously, simulating the real CLI behavior.
  """
  def stream(args, %Options{} = _options, stdin_input \\ nil) do
    Stream.resource(
      fn -> start_mock_async(args, stdin_input) end,
      &receive_mock_messages/1,
      &cleanup_mock/1
    )
  end

  defp start_mock_async(args, stdin_input) do
    # Extract the prompt from args or use stdin_input
    prompt = stdin_input || extract_prompt(args)

    # Get mock response
    messages = Mock.get_response(prompt)

    # Spawn a process to send messages asynchronously
    parent = self()

    sender_pid =
      spawn(fn ->
        # Send each message with a small delay to simulate streaming
        Enum.each(messages, fn msg ->
          converted = convert_to_message(msg)
          send(parent, {:mock_message, converted})
          # Small delay to simulate network/processing time
          Process.sleep(10)
        end)

        # Send completion signal
        send(parent, {:mock_done, :normal})
      end)

    %{
      sender_pid: sender_pid,
      done: false,
      messages_queue: []
    }
  end

  defp receive_mock_messages(%{done: true, messages_queue: []}) do
    {:halt, %{done: true}}
  end

  defp receive_mock_messages(%{done: true, messages_queue: messages}) do
    {messages, %{done: true, messages_queue: []}}
  end

  defp receive_mock_messages(state) do
    # Check if we have queued messages first
    case state.messages_queue do
      [] ->
        # No queued messages, wait for new ones
        receive_new_mock_messages(state)

      messages ->
        # Return queued messages
        {messages, %{state | messages_queue: []}}
    end
  end

  defp receive_new_mock_messages(state) do
    receive do
      {:mock_message, message} ->
        # Check if this is a final message
        if is_final_message?(message) do
          {[message], %{state | done: true}}
        else
          # Queue the message and continue
          new_state = %{state | messages_queue: [message]}
          receive_mock_messages(new_state)
        end

      {:mock_done, _reason} ->
        # Process completed
        {state.messages_queue, %{state | done: true}}
    after
      50 ->
        if state.messages_queue == [] do
          # No messages ready, continue waiting
          receive_mock_messages(state)
        else
          # Return what we have
          {state.messages_queue, %{state | messages_queue: []}}
        end
    end
  end

  defp cleanup_mock(%{sender_pid: pid}) when is_pid(pid) do
    # Ensure the sender process is stopped
    Process.exit(pid, :kill)
    :ok
  end

  defp cleanup_mock(_state) do
    :ok
  end

  defp extract_prompt(args) do
    # The prompt is typically the last non-flag argument
    args
    |> Enum.reverse()
    |> Enum.find(fn arg ->
      not String.starts_with?(arg, "-") and arg not in ["continue", "resume"]
    end)
    |> Kernel.||("")
  end

  defp convert_to_message(raw_message) do
    # The message is already a map, parse it directly
    type = String.to_atom(raw_message["type"])

    message = %Message{
      type: type,
      raw: raw_message
    }

    case type do
      :assistant ->
        %{
          message
          | data: %{message: raw_message["message"], session_id: raw_message["session_id"]}
        }

      :user ->
        %{
          message
          | data: %{message: raw_message["message"], session_id: raw_message["session_id"]}
        }

      :result ->
        subtype = if raw_message["subtype"], do: String.to_atom(raw_message["subtype"])
        %{message | subtype: subtype, data: Map.drop(raw_message, ["type", "subtype"])}

      :system ->
        subtype = if raw_message["subtype"], do: String.to_atom(raw_message["subtype"])
        %{message | subtype: subtype, data: Map.drop(raw_message, ["type", "subtype"])}

      _ ->
        %{message | data: raw_message}
    end
  end

  defp is_final_message?(%Message{type: :result}), do: true
  defp is_final_message?(_), do: false
end
