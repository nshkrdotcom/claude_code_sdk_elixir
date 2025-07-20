defmodule ClaudeCodeSDK.StepTestHelpers do
  @moduledoc """
  Test helpers for step creation and validation.

  This module provides utilities for creating test steps, mock step streams,
  and validation helpers for testing step detection and control logic.

  ## Usage

  This module is intended for use in tests and development environments.
  It provides convenient functions for creating test data and asserting
  step behavior.

  ## Examples

      # In your test file
      use ClaudeCodeSDK.StepTestHelpers

      test "step detection works correctly" do
        messages = create_test_messages(:file_operation)
        step = create_test_step(:file_operation, messages: messages)
        
        assert_step_type(step, :file_operation)
        assert_step_completed(step)
      end

  """

  alias ClaudeCodeSDK.{Step, Message, StepPattern, StepConfig}

  @doc """
  Creates a test step with the given type and options.

  ## Parameters

  - `type` - Step type atom
  - `opts` - Additional options for step creation

  ## Options

  - `:messages` - List of messages (defaults to generated messages)
  - `:tools_used` - List of tools used (defaults to type-appropriate tools)
  - `:status` - Step status (defaults to `:completed`)
  - `:description` - Step description (defaults to generated description)

  ## Examples

      iex> step = ClaudeCodeSDK.StepTestHelpers.create_test_step(:file_operation)
      iex> step.type
      :file_operation

      iex> step = ClaudeCodeSDK.StepTestHelpers.create_test_step(
      ...>   :code_modification,
      ...>   tools_used: ["strReplace"],
      ...>   status: :in_progress
      ...> )
      iex> step.tools_used
      ["strReplace"]

  """
  @spec create_test_step(Step.step_type(), keyword()) :: Step.t()
  def create_test_step(type, opts \\ []) do
    messages = Keyword.get(opts, :messages, create_test_messages(type))
    tools_used = Keyword.get(opts, :tools_used, default_tools_for_type(type))
    status = Keyword.get(opts, :status, :completed)
    description = Keyword.get(opts, :description, default_description_for_type(type))

    Step.new(
      [
        type: type,
        description: description,
        messages: messages,
        tools_used: tools_used,
        status: status
      ] ++ Keyword.drop(opts, [:messages, :tools_used, :status, :description])
    )
  end

  @doc """
  Creates test messages for a given step type.

  ## Parameters

  - `type` - Step type to create messages for
  - `count` - Number of messages to create (defaults to 3)

  ## Returns

  List of test messages appropriate for the step type.

  ## Examples

      iex> messages = ClaudeCodeSDK.StepTestHelpers.create_test_messages(:file_operation)
      iex> length(messages)
      3

      iex> messages = ClaudeCodeSDK.StepTestHelpers.create_test_messages(:analysis, 5)
      iex> length(messages)
      5

  """
  @spec create_test_messages(Step.step_type(), integer()) :: [Message.t()]
  def create_test_messages(type, count \\ 3) do
    1..count
    |> Enum.map(fn i -> create_message_for_type(type, i) end)
  end

  @doc """
  Creates a mock step stream with predefined scenarios.

  ## Parameters

  - `scenarios` - List of step scenarios to include in the stream

  ## Scenario Options

  - `{:step_type, count}` - Create `count` steps of the given type
  - `{:step_type, count, opts}` - Create steps with additional options
  - `step` - Include a specific step in the stream

  ## Examples

      iex> stream = ClaudeCodeSDK.StepTestHelpers.create_mock_step_stream([
      ...>   {:file_operation, 2},
      ...>   {:code_modification, 1, status: :in_progress}
      ...> ])
      iex> steps = Enum.to_list(stream)
      iex> length(steps)
      3

  """
  @spec create_mock_step_stream([term()]) :: Enumerable.t()
  def create_mock_step_stream(scenarios) do
    scenarios
    |> Enum.flat_map(&scenario_to_steps/1)
  end

  @doc """
  Creates a test configuration with the given options.

  ## Parameters

  - `opts` - Configuration options

  ## Examples

      iex> config = ClaudeCodeSDK.StepTestHelpers.create_test_config(
      ...>   step_grouping: %{enabled: true},
      ...>   step_control: %{mode: :manual}
      ...> )
      iex> config.step_grouping.enabled
      true

  """
  @spec create_test_config(keyword()) :: StepConfig.t()
  def create_test_config(opts \\ []) do
    StepConfig.new(opts)
  end

  @doc """
  Creates test patterns for step detection testing.

  ## Parameters

  - `types` - List of pattern types to create (defaults to all types)

  ## Returns

  List of test patterns.

  ## Examples

      iex> patterns = ClaudeCodeSDK.StepTestHelpers.create_test_patterns()
      iex> length(patterns) > 0
      true

      iex> patterns = ClaudeCodeSDK.StepTestHelpers.create_test_patterns([:file_operation])
      iex> hd(patterns).id
      :file_operation

  """
  @spec create_test_patterns([atom()]) :: [StepPattern.t()]
  def create_test_patterns(types \\ [:file_operation, :code_modification, :analysis]) do
    Enum.map(types, &create_test_pattern/1)
  end

  @doc """
  Asserts that a step has the expected type.

  ## Parameters

  - `step` - The step to check
  - `expected_type` - The expected step type

  ## Examples

      iex> step = ClaudeCodeSDK.StepTestHelpers.create_test_step(:file_operation)
      iex> ClaudeCodeSDK.StepTestHelpers.assert_step_type(step, :file_operation)
      :ok

  """
  @spec assert_step_type(Step.t(), Step.step_type()) :: :ok | no_return()
  def assert_step_type(%Step{type: actual_type}, expected_type) do
    if actual_type == expected_type do
      :ok
    else
      raise "Expected step type #{inspect(expected_type)}, got #{inspect(actual_type)}"
    end
  end

  @doc """
  Asserts that a step is completed.

  ## Parameters

  - `step` - The step to check

  ## Examples

      iex> step = ClaudeCodeSDK.StepTestHelpers.create_test_step(:file_operation, status: :completed)
      iex> ClaudeCodeSDK.StepTestHelpers.assert_step_completed(step)
      :ok

  """
  @spec assert_step_completed(Step.t()) :: :ok | no_return()
  def assert_step_completed(%Step{} = step) do
    if Step.completed?(step) do
      :ok
    else
      raise "Expected step to be completed, got status #{inspect(step.status)}"
    end
  end

  @doc """
  Asserts that a step has the expected tools.

  ## Parameters

  - `step` - The step to check
  - `expected_tools` - List of expected tool names

  ## Examples

      iex> step = ClaudeCodeSDK.StepTestHelpers.create_test_step(:file_operation)
      iex> ClaudeCodeSDK.StepTestHelpers.assert_step_tools(step, ["readFile"])
      :ok

  """
  @spec assert_step_tools(Step.t(), [String.t()]) :: :ok | no_return()
  def assert_step_tools(%Step{tools_used: actual_tools}, expected_tools) do
    missing_tools = expected_tools -- actual_tools

    if Enum.empty?(missing_tools) do
      :ok
    else
      raise "Expected step to use tools #{inspect(expected_tools)}, missing: #{inspect(missing_tools)}"
    end
  end

  @doc """
  Asserts that a step has the expected number of messages.

  ## Parameters

  - `step` - The step to check
  - `expected_count` - Expected number of messages

  ## Examples

      iex> step = ClaudeCodeSDK.StepTestHelpers.create_test_step(:file_operation)
      iex> ClaudeCodeSDK.StepTestHelpers.assert_step_message_count(step, 3)
      :ok

  """
  @spec assert_step_message_count(Step.t(), integer()) :: :ok | no_return()
  def assert_step_message_count(%Step{messages: messages}, expected_count) do
    actual_count = length(messages)

    if actual_count == expected_count do
      :ok
    else
      raise "Expected step to have #{expected_count} messages, got #{actual_count}"
    end
  end

  @doc """
  Asserts that a step has a valid structure.

  ## Parameters

  - `step` - The step to validate

  ## Examples

      iex> step = ClaudeCodeSDK.StepTestHelpers.create_test_step(:file_operation)
      iex> ClaudeCodeSDK.StepTestHelpers.assert_valid_step(step)
      :ok

  """
  @spec assert_valid_step(Step.t()) :: :ok | no_return()
  def assert_valid_step(%Step{} = step) do
    cond do
      is_nil(step.id) or step.id == "" ->
        raise "Step must have a non-empty ID"

      not is_atom(step.type) ->
        raise "Step type must be an atom"

      not is_binary(step.description) ->
        raise "Step description must be a string"

      not is_list(step.messages) ->
        raise "Step messages must be a list"

      not is_list(step.tools_used) ->
        raise "Step tools_used must be a list"

      not is_atom(step.status) ->
        raise "Step status must be an atom"

      not is_map(step.metadata) ->
        raise "Step metadata must be a map"

      not is_list(step.interventions) ->
        raise "Step interventions must be a list"

      true ->
        :ok
    end
  end

  # Private helper functions

  defp default_tools_for_type(:file_operation), do: ["readFile", "fsWrite", "listDirectory"]
  defp default_tools_for_type(:code_modification), do: ["strReplace", "fsWrite"]
  defp default_tools_for_type(:system_command), do: ["executePwsh"]
  defp default_tools_for_type(:exploration), do: ["grepSearch", "fileSearch"]
  defp default_tools_for_type(:analysis), do: ["readFile", "readMultipleFiles"]
  defp default_tools_for_type(:communication), do: []
  defp default_tools_for_type(_), do: []

  defp default_description_for_type(:file_operation), do: "Performing file operations"
  defp default_description_for_type(:code_modification), do: "Modifying code"
  defp default_description_for_type(:system_command), do: "Executing system command"
  defp default_description_for_type(:exploration), do: "Exploring codebase"
  defp default_description_for_type(:analysis), do: "Analyzing code"
  defp default_description_for_type(:communication), do: "Communicating with user"
  defp default_description_for_type(_), do: "Unknown operation"

  defp create_message_for_type(type, index) do
    content = message_content_for_type(type, index)

    %Message{
      type: :assistant,
      data: %{
        message: %{"content" => content},
        session_id: "test-session-#{index}"
      },
      raw: %{
        "type" => "assistant",
        "message" => %{"content" => content},
        "session_id" => "test-session-#{index}"
      }
    }
  end

  defp message_content_for_type(:file_operation, index) do
    case index do
      1 -> "I'll read the configuration file to understand the current setup."
      2 -> "Now I'll write the updated configuration to the file."
      _ -> "File operation completed successfully."
    end
  end

  defp message_content_for_type(:code_modification, index) do
    case index do
      1 -> "I need to implement the authentication function."
      2 -> "Let me refactor this code to improve readability."
      _ -> "Code modification completed."
    end
  end

  defp message_content_for_type(:system_command, index) do
    case index do
      1 -> "I'll run the test suite to check the current status."
      2 -> "Executing the build command now."
      _ -> "Command executed successfully."
    end
  end

  defp message_content_for_type(:exploration, index) do
    case index do
      1 -> "Let me search for similar implementations in the codebase."
      2 -> "I'll explore the directory structure to understand the layout."
      _ -> "Exploration completed."
    end
  end

  defp message_content_for_type(:analysis, index) do
    case index do
      1 -> "I need to analyze this code to understand its purpose."
      2 -> "Let me review the implementation for potential issues."
      _ -> "Analysis completed."
    end
  end

  defp message_content_for_type(:communication, index) do
    case index do
      1 -> "Let me explain how this feature works."
      2 -> "Here's what I found in the codebase."
      _ -> "I hope this explanation helps!"
    end
  end

  defp message_content_for_type(_, index) do
    "Test message #{index} for unknown step type."
  end

  defp scenario_to_steps({type, count}) when is_atom(type) and is_integer(count) do
    1..count |> Enum.map(fn _ -> create_test_step(type) end)
  end

  defp scenario_to_steps({type, count, opts}) when is_atom(type) and is_integer(count) do
    1..count |> Enum.map(fn _ -> create_test_step(type, opts) end)
  end

  defp scenario_to_steps(%Step{} = step) do
    [step]
  end

  defp scenario_to_steps(steps) when is_list(steps) do
    steps
  end

  defp create_test_pattern(:file_operation) do
    StepPattern.new(
      id: :file_operation,
      name: "Test File Operations",
      description: "Test pattern for file operations",
      triggers: [
        StepPattern.tool_trigger(["readFile", "fsWrite", "listDirectory"])
      ],
      validators: [
        StepPattern.tool_validator(min_tools: 1)
      ],
      priority: 90,
      confidence: 0.95
    )
  end

  defp create_test_pattern(:code_modification) do
    StepPattern.new(
      id: :code_modification,
      name: "Test Code Modifications",
      description: "Test pattern for code modifications",
      triggers: [
        StepPattern.tool_trigger(["strReplace"]),
        StepPattern.content_trigger(~r/implement|refactor/i)
      ],
      validators: [
        StepPattern.tool_validator(min_tools: 1)
      ],
      priority: 85,
      confidence: 0.9
    )
  end

  defp create_test_pattern(:analysis) do
    StepPattern.new(
      id: :analysis,
      name: "Test Analysis",
      description: "Test pattern for code analysis",
      triggers: [
        StepPattern.tool_trigger(["readFile", "readMultipleFiles"]),
        StepPattern.content_trigger(~r/analyze|review/i)
      ],
      validators: [
        StepPattern.message_validator(min_messages: 1)
      ],
      priority: 60,
      confidence: 0.8
    )
  end

  defp create_test_pattern(type) do
    StepPattern.new(
      id: type,
      name: "Test #{type}",
      description: "Test pattern for #{type}",
      triggers: [
        StepPattern.content_trigger(~r/test/i)
      ],
      validators: [],
      priority: 50,
      confidence: 0.5
    )
  end
end
