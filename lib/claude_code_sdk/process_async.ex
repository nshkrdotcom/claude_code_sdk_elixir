defmodule ClaudeCodeSDK.ProcessAsync do
  @moduledoc """
  Async streaming implementation using erlexec for real-time message streaming.

  This module creates a true streaming experience by using erlexec's async mode
  with stdout/stderr redirection to the calling process.
  """

  alias ClaudeCodeSDK.{Message, Options}
  alias ClaudeCodeSDK.Mock.ProcessAsync, as: MockProcessAsync

  @doc """
  Streams messages from Claude Code CLI using erlexec in async mode.

  Unlike the sync mode which collects all output before parsing, this implementation
  parses and yields messages as they arrive from the Claude CLI.
  """
  @spec stream([String.t()], Options.t(), String.t() | nil) ::
          Enumerable.t(ClaudeCodeSDK.Message.t())
  def stream(args, %Options{} = options, stdin_input \\ nil) do
    # Check if we should use mock
    if use_mock?() do
      MockProcessAsync.stream(args, options, stdin_input)
    else
      stream_real(args, options, stdin_input)
    end
  end

  defp use_mock? do
    Application.get_env(:claude_code_sdk, :use_mock, false)
  end

  defp stream_real(args, options, stdin_input) do
    Stream.resource(
      fn -> start_async_claude(args, options, stdin_input) end,
      &receive_and_parse_messages/1,
      &cleanup_process/1
    )
  end

  defp start_async_claude(args, options, stdin_input) do
    # Ensure erlexec is started
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "Failed to start erlexec: #{inspect(reason)}"
    end

    {cmd, _} = build_claude_command(args, options)

    # Debug output if verbose mode is enabled
    if options.verbose do
      IO.puts("\n🔍 [DEBUG] Raw CLI command:")
      IO.puts("   #{cmd}")

      if stdin_input do
        IO.puts("   STDIN: #{inspect(stdin_input, limit: 100)}")
      end

      IO.puts("")
    end

    # Build exec options for async streaming
    # Key differences from sync mode:
    # 1. No :sync option - runs asynchronously
    # 2. stdout/stderr redirect to self() to receive messages
    # 3. :monitor to get process exit notification
    exec_options = build_async_options(options, stdin_input)

    case :exec.run(cmd, exec_options) do
      {:ok, pid, os_pid} ->
        # Send stdin if provided
        if stdin_input do
          :exec.send(pid, stdin_input)
          :exec.send(pid, :eof)
        end

        %{
          exec_pid: pid,
          os_pid: os_pid,
          buffer: "",
          done: false,
          messages_queue: []
        }

      {:error, reason} ->
        error_msg = create_error_message(reason)

        %{
          done: true,
          messages_queue: [error_msg]
        }
    end
  end

  defp build_async_options(options, stdin_input) do
    base_opts = [
      # Redirect stdout to this process
      {:stdout, self()},
      # Redirect stderr to this process
      {:stderr, self()},
      # Monitor the process
      :monitor
    ]

    # Add stdin if we have input
    base_opts = if stdin_input, do: [:stdin | base_opts], else: base_opts

    # Add working directory if specified
    case options.cwd do
      nil -> base_opts
      cwd -> [{:cd, cwd} | base_opts]
    end
  end

  defp receive_and_parse_messages(%{done: true, messages_queue: []}) do
    {:halt, %{done: true}}
  end

  defp receive_and_parse_messages(%{done: true, messages_queue: messages}) do
    {messages, %{done: true, messages_queue: []}}
  end

  defp receive_and_parse_messages(state) do
    # Check if we have queued messages first
    case state.messages_queue do
      [] ->
        # No queued messages, wait for new ones
        receive_new_messages(state)

      messages ->
        # Return queued messages
        {messages, %{state | messages_queue: []}}
    end
  end

  defp receive_new_messages(state) do
    receive do
      # Stdout data from Claude CLI
      {:stdout, os_pid, data} when os_pid == state.os_pid ->
        # Append to buffer and parse JSON lines
        new_buffer = state.buffer <> data
        {messages, remaining_buffer} = parse_json_lines(new_buffer)

        # Check for final message
        if Enum.any?(messages, &final_message?/1) do
          {messages, %{state | done: true, buffer: ""}}
        else
          # Continue receiving
          new_state = %{state | buffer: remaining_buffer, messages_queue: messages}
          receive_and_parse_messages(new_state)
        end

      # Stderr data (usually errors or warnings)
      {:stderr, os_pid, data} when os_pid == state.os_pid ->
        # Log stderr but continue unless it's a fatal error
        if String.contains?(data, "Error:") do
          error_msg = create_stderr_error(data)
          {[error_msg], %{state | done: true}}
        else
          # Just log and continue
          if String.trim(data) != "" do
            IO.warn("Claude stderr: #{String.trim(data)}")
          end

          receive_and_parse_messages(state)
        end

      # Process exit notification
      {:DOWN, _ref, :process, pid, reason} when pid == state.exec_pid ->
        # Process completed - parse any remaining buffer
        {messages, _} = parse_json_lines(state.buffer)

        # Add exit status message if abnormal termination
        exit_messages =
          case reason do
            :normal ->
              messages

            {:exit_status, 0} ->
              messages

            {:exit_status, status} ->
              messages ++ [create_exit_message(status)]

            other ->
              messages ++ [create_error_message(other)]
          end

        {exit_messages, %{state | done: true}}
    after
      # Small timeout to batch messages but still be responsive
      50 ->
        if state.messages_queue == [] do
          # No messages ready, continue waiting
          receive_and_parse_messages(state)
        else
          # Return what we have
          {state.messages_queue, %{state | messages_queue: []}}
        end
    end
  end

  defp parse_json_lines(data) do
    lines = String.split(data, "\n")

    # The last element might be incomplete
    {complete_lines, [last_line]} = Enum.split(lines, -1)

    messages =
      complete_lines
      |> Enum.filter(&(&1 != ""))
      |> Enum.map(&parse_single_json/1)
      |> Enum.filter(&(&1 != nil))

    {messages, last_line}
  end

  defp parse_single_json(line) do
    case Message.from_json(line) do
      {:ok, message} -> message
      {:error, _} -> nil
    end
  end

  defp final_message?(%Message{type: :result}), do: true
  defp final_message?(_), do: false

  defp cleanup_process(%{exec_pid: pid}) do
    :exec.stop(pid)
  catch
    _, _ -> :ok
  end

  defp cleanup_process(_state) do
    :ok
  end

  defp build_claude_command(args, _options) do
    executable = find_executable()

    # Ensure JSON streaming output
    final_args = ensure_json_flags(args)

    # Build command string
    quoted_args = Enum.map(final_args, &shell_escape/1)
    {Enum.join([executable | quoted_args], " "), []}
  end

  defp find_executable do
    case System.find_executable("claude") do
      nil ->
        raise "Claude CLI not found. Please install with: npm install -g @anthropic-ai/claude-code"

      path ->
        path
    end
  end

  defp ensure_json_flags(args) do
    if "--output-format" in args do
      args
    else
      args ++ ["--output-format", "stream-json", "--verbose"]
    end
  end

  defp shell_escape(arg) do
    if String.contains?(arg, [" ", "!", "\"", "'", "$", "`", "\\", "|", "&", ";", "(", ")"]) do
      "\"#{String.replace(arg, "\"", "\\\"")}\""
    else
      arg
    end
  end

  defp create_error_message(reason) do
    %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: format_error(reason),
        session_id: "error",
        is_error: true
      }
    }
  end

  defp create_stderr_error(data) do
    %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: String.trim(data),
        session_id: "error",
        is_error: true
      }
    }
  end

  defp create_exit_message(status) do
    %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: "Process exited with status #{status}",
        exit_status: status,
        session_id: "error",
        is_error: true
      }
    }
  end

  defp format_error(reason) do
    case reason do
      [{:exit_status, status}] -> "Process exited with status #{status}"
      {:exit_status, status} -> "Process exited with status #{status}"
      other -> inspect(other)
    end
  end
end
