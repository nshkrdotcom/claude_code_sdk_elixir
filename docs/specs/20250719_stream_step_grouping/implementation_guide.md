# Stream Step Grouping - Implementation Guide

## Overview

This guide provides step-by-step instructions for implementing the Stream Step Grouping feature in the Claude Code SDK.

## Prerequisites

- Elixir 1.14 or higher
- Understanding of GenServer and Stream concepts
- Familiarity with the existing Claude Code SDK architecture

## Implementation Plan

### Phase 1: Core Infrastructure (Week 1)

#### 1.1 Create Base Modules

```bash
# Create directory structure
mkdir -p lib/claude_code_sdk/step_grouping
mkdir -p lib/claude_code_sdk/step_grouping/patterns
mkdir -p lib/claude_code_sdk/step_grouping/detectors
mkdir -p test/step_grouping
```

#### 1.2 Define Core Data Structures

```elixir
# lib/claude_code_sdk/step.ex
defmodule ClaudeCodeSDK.Step do
  @moduledoc """
  Represents a logical step in Claude's execution
  """
  
  defstruct [
    :id,
    :type,
    :description,
    :messages,
    :tools_used,
    :started_at,
    :completed_at,
    :status,
    :metadata,
    :review_status,
    :interventions
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    type: atom(),
    description: String.t(),
    messages: [ClaudeCodeSDK.Message.t()],
    tools_used: [String.t()],
    started_at: DateTime.t(),
    completed_at: DateTime.t() | nil,
    status: atom(),
    metadata: map(),
    review_status: atom() | nil,
    interventions: list()
  }
  
  def new(attrs \\ %{}) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      type: attrs[:type] || :unknown,
      description: attrs[:description] || "",
      messages: attrs[:messages] || [],
      tools_used: attrs[:tools_used] || [],
      started_at: attrs[:started_at] || DateTime.utc_now(),
      completed_at: attrs[:completed_at],
      status: attrs[:status] || :in_progress,
      metadata: attrs[:metadata] || %{},
      review_status: attrs[:review_status],
      interventions: attrs[:interventions] || []
    }
  end
  
  defp generate_id do
    "step_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
  
  @doc "Adds a message to the step"
  def add_message(%__MODULE__{} = step, message) do
    %{step | messages: step.messages ++ [message]}
  end
  
  @doc "Completes the step"
  def complete(%__MODULE__{} = step) do
    %{step | 
      status: :completed,
      completed_at: DateTime.utc_now()
    }
  end
  
  @doc "Extracts tools used from messages"
  def extract_tools(%__MODULE__{messages: messages}) do
    messages
    |> Enum.flat_map(&extract_tools_from_message/1)
    |> Enum.uniq()
  end
  
  defp extract_tools_from_message(%{type: :assistant, content: content}) do
    # Extract tool uses from content
    content
    |> Enum.filter(&match?(%{"type" => "tool_use"}, &1))
    |> Enum.map(&Map.get(&1, "name"))
    |> Enum.filter(&is_binary/1)
  end
  defp extract_tools_from_message(_), do: []
end
```

#### 1.3 Implement Pattern Module

```elixir
# lib/claude_code_sdk/step_grouping/pattern.ex
defmodule ClaudeCodeSDK.StepGrouping.Pattern do
  @moduledoc """
  Defines the structure and behavior of step detection patterns
  """
  
  @type trigger :: 
    {:message_text, Regex.t()} |
    {:tool_use, String.t() | :any} |
    {:tool_sequence, [String.t()]} |
    {:message_count, integer()} |
    {:time_gap, integer()}
    
  @type validator ::
    {:has_tool_use, boolean()} |
    {:has_tool_result, boolean()} |
    {:min_messages, integer()} |
    {:max_messages, integer()} |
    {:contains_text, Regex.t()}
  
  @type t :: %{
    id: atom(),
    name: String.t(),
    description: String.t(),
    triggers: [trigger()],
    validators: [validator()],
    priority: integer(),
    confidence: float()
  }
  
  @doc "Evaluates if a message triggers this pattern"
  def triggers?(pattern, message, buffer) do
    Enum.any?(pattern.triggers, fn trigger ->
      evaluate_trigger(trigger, message, buffer)
    end)
  end
  
  @doc "Validates if the buffered messages form a complete step"
  def validates?(pattern, messages) do
    Enum.all?(pattern.validators, fn validator ->
      evaluate_validator(validator, messages)
    end)
  end
  
  defp evaluate_trigger({:message_text, regex}, message, _buffer) do
    case ClaudeCodeSDK.ContentExtractor.extract_text(message) do
      nil -> false
      text -> Regex.match?(regex, text)
    end
  end
  
  defp evaluate_trigger({:tool_use, tool_name}, message, _buffer) do
    tools = extract_tool_uses(message)
    case tool_name do
      :any -> length(tools) > 0
      name -> name in tools
    end
  end
  
  defp evaluate_trigger({:tool_sequence, sequence}, _message, buffer) do
    buffer_tools = Enum.flat_map(buffer, &extract_tool_uses/1)
    List.starts_with?(buffer_tools, sequence)
  end
  
  defp evaluate_trigger({:message_count, count}, _message, buffer) do
    length(buffer) >= count - 1
  end
  
  defp evaluate_trigger({:time_gap, gap_ms}, message, buffer) do
    case List.last(buffer) do
      nil -> true
      last_msg -> 
        time_diff = DateTime.diff(message.timestamp, last_msg.timestamp, :millisecond)
        time_diff >= gap_ms
    end
  end
  
  defp evaluate_validator({:has_tool_use, expected}, messages) do
    has_tools = Enum.any?(messages, fn msg ->
      length(extract_tool_uses(msg)) > 0
    end)
    has_tools == expected
  end
  
  defp evaluate_validator({:has_tool_result, expected}, messages) do
    has_results = Enum.any?(messages, fn msg ->
      has_tool_results?(msg)
    end)
    has_results == expected
  end
  
  defp evaluate_validator({:min_messages, min}, messages) do
    length(messages) >= min
  end
  
  defp evaluate_validator({:max_messages, max}, messages) do
    length(messages) <= max
  end
  
  defp evaluate_validator({:contains_text, regex}, messages) do
    Enum.any?(messages, fn msg ->
      case ClaudeCodeSDK.ContentExtractor.extract_text(msg) do
        nil -> false
        text -> Regex.match?(regex, text)
      end
    end)
  end
  
  defp extract_tool_uses(%{type: :assistant, content: content}) when is_list(content) do
    content
    |> Enum.filter(&match?(%{"type" => "tool_use"}, &1))
    |> Enum.map(&Map.get(&1, "name"))
    |> Enum.filter(&is_binary/1)
  end
  defp extract_tool_uses(_), do: []
  
  defp has_tool_results?(%{type: :assistant, content: content}) when is_list(content) do
    Enum.any?(content, &match?(%{"type" => "tool_result"}, &1))
  end
  defp has_tool_results?(_), do: false
end
```

### Phase 2: Pattern Detection (Week 2)

#### 2.1 Built-in Patterns

```elixir
# lib/claude_code_sdk/step_grouping/patterns/builtin.ex
defmodule ClaudeCodeSDK.StepGrouping.Patterns.Builtin do
  @moduledoc """
  Built-in step detection patterns
  """
  
  @patterns %{
    file_operation: %{
      id: :file_operation,
      name: "File Operation",
      description: "Reading, writing, or analyzing files",
      triggers: [
        {:message_text, ~r/\b(read|check|examine|look at|analyze|write|create|edit)\s+(\w+\.\w+|file|directory)/i},
        {:tool_use, "read"},
        {:tool_use, "write"},
        {:tool_use, "edit"}
      ],
      validators: [
        {:has_tool_use, true},
        {:min_messages, 2},
        {:max_messages, 15}
      ],
      priority: 10,
      confidence: 0.9
    },
    
    code_modification: %{
      id: :code_modification,
      name: "Code Modification",
      description: "Making changes to code files",
      triggers: [
        {:message_text, ~r/\b(fix|update|modify|change|refactor|implement|add|remove)\b.*\b(code|function|method|class|module)/i},
        {:tool_use, "edit"},
        {:tool_use, "write"}
      ],
      validators: [
        {:has_tool_use, true},
        {:has_tool_result, true},
        {:contains_text, ~r/(updated|fixed|changed|modified|implemented|added|removed)/i}
      ],
      priority: 15,
      confidence: 0.85
    },
    
    system_command: %{
      id: :system_command,
      name: "System Command",
      description: "Executing system commands",
      triggers: [
        {:message_text, ~r/\b(run|execute|running|executing)\b/i},
        {:tool_use, "bash"},
        {:tool_use, "shell"}
      ],
      validators: [
        {:has_tool_use, true},
        {:has_tool_result, true},
        {:min_messages, 2}
      ],
      priority: 12,
      confidence: 0.9
    },
    
    exploration: %{
      id: :exploration,
      name: "Search/Exploration",
      description: "Searching for information or exploring code",
      triggers: [
        {:message_text, ~r/\b(search|find|look for|explore|investigate|discover)\b/i},
        {:tool_use, "grep"},
        {:tool_use, "find"},
        {:tool_use, "ls"}
      ],
      validators: [
        {:min_messages, 2},
        {:max_messages, 25}
      ],
      priority: 8,
      confidence: 0.75
    },
    
    analysis: %{
      id: :analysis,
      name: "Analysis",
      description: "Analyzing code or data",
      triggers: [
        {:message_text, ~r/\b(analyze|examining|understanding|reviewing|studying)\b/i},
        {:message_count, 3}
      ],
      validators: [
        {:min_messages, 3},
        {:contains_text, ~r/(found|discovered|appears|seems|shows|indicates)/i}
      ],
      priority: 7,
      confidence: 0.7
    }
  }
  
  def all_patterns, do: Map.values(@patterns)
  
  def get_pattern(id), do: Map.get(@patterns, id)
  
  def pattern_ids, do: Map.keys(@patterns)
end
```

#### 2.2 Step Detector

```elixir
# lib/claude_code_sdk/step_grouping/detector.ex
defmodule ClaudeCodeSDK.StepGrouping.Detector do
  @moduledoc """
  Detects step boundaries in message streams
  """
  
  require Logger
  
  defstruct [
    :strategy,
    :patterns,
    :confidence_threshold,
    :state
  ]
  
  def new(opts \\ []) do
    %__MODULE__{
      strategy: Keyword.get(opts, :strategy, :pattern_based),
      patterns: load_patterns(Keyword.get(opts, :patterns, :default)),
      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.7),
      state: %{}
    }
  end
  
  @doc """
  Analyzes a message to determine step boundaries
  """
  def analyze(detector, message, buffer) do
    case detector.strategy do
      :pattern_based ->
        analyze_with_patterns(detector, message, buffer)
      :custom ->
        apply(detector.state.custom_analyzer, [message, buffer])
      _ ->
        {:step_continue, nil}
    end
  end
  
  defp analyze_with_patterns(detector, message, buffer) do
    # Check if any pattern triggers
    triggered_patterns = Enum.filter(detector.patterns, fn pattern ->
      ClaudeCodeSDK.StepGrouping.Pattern.triggers?(pattern, message, buffer)
    end)
    
    if Enum.empty?(triggered_patterns) do
      # No triggers, continue current step
      {:step_continue, nil}
    else
      # Check if we should start a new step or end current
      analyze_triggered_patterns(detector, triggered_patterns, message, buffer)
    end
  end
  
  defp analyze_triggered_patterns(detector, patterns, message, buffer) do
    # Sort by priority
    sorted_patterns = Enum.sort_by(patterns, & &1.priority, :desc)
    
    # Try to validate with highest priority pattern
    case find_valid_pattern(sorted_patterns, buffer ++ [message]) do
      {pattern, confidence} when confidence >= detector.confidence_threshold ->
        {:step_end, %{
          pattern_id: pattern.id,
          confidence: confidence,
          pattern_name: pattern.name
        }}
        
      _ ->
        # Check if this is a step start
        if is_step_start?(message, buffer) do
          {:step_start, detect_step_type(message)}
        else
          {:step_continue, nil}
        end
    end
  end
  
  defp find_valid_pattern(patterns, messages) do
    Enum.find_value(patterns, fn pattern ->
      if ClaudeCodeSDK.StepGrouping.Pattern.validates?(pattern, messages) do
        {pattern, pattern.confidence}
      else
        nil
      end
    end)
  end
  
  defp is_step_start?(message, buffer) do
    # Heuristics for step start
    cond do
      # Empty buffer usually means start
      Enum.empty?(buffer) -> true
      
      # Significant time gap
      time_gap?(message, List.last(buffer), 3000) -> true
      
      # Topic change
      topic_changed?(message, buffer) -> true
      
      # Default
      true -> false
    end
  end
  
  defp detect_step_type(message) do
    text = ClaudeCodeSDK.ContentExtractor.extract_text(message) || ""
    
    cond do
      text =~ ~r/read|check|examine/i -> :file_operation
      text =~ ~r/fix|update|modify/i -> :code_modification
      text =~ ~r/run|execute/i -> :system_command
      text =~ ~r/search|find|explore/i -> :exploration
      text =~ ~r/analyze|review/i -> :analysis
      true -> :unknown
    end
  end
  
  defp time_gap?(message1, message2, threshold_ms) do
    case {message1[:timestamp], message2[:timestamp]} do
      {t1, t2} when not is_nil(t1) and not is_nil(t2) ->
        DateTime.diff(t1, t2, :millisecond) >= threshold_ms
      _ ->
        false
    end
  end
  
  defp topic_changed?(_message, _buffer) do
    # TODO: Implement topic change detection
    false
  end
  
  defp load_patterns(:default) do
    ClaudeCodeSDK.StepGrouping.Patterns.Builtin.all_patterns()
  end
  
  defp load_patterns(:all) do
    ClaudeCodeSDK.StepGrouping.Patterns.Builtin.all_patterns()
  end
  
  defp load_patterns(pattern_list) when is_list(pattern_list) do
    # Load specific patterns
    Enum.map(pattern_list, fn
      pattern when is_atom(pattern) ->
        ClaudeCodeSDK.StepGrouping.Patterns.Builtin.get_pattern(pattern)
      pattern when is_map(pattern) ->
        pattern
    end)
    |> Enum.filter(&(not is_nil(&1)))
  end
end
```

### Phase 3: Stream Processing (Week 3)

#### 3.1 Step Buffer

```elixir
# lib/claude_code_sdk/step_grouping/buffer.ex
defmodule ClaudeCodeSDK.StepGrouping.Buffer do
  @moduledoc """
  Buffers messages and emits complete steps
  """
  
  use GenServer
  
  require Logger
  
  defstruct [
    :current_step,
    :message_buffer,
    :detector,
    :timeout_ms,
    :timeout_ref,
    :emit_callback,
    :step_id_counter
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def add_message(buffer, message) do
    GenServer.call(buffer, {:add_message, message})
  end
  
  def flush(buffer) do
    GenServer.call(buffer, :flush)
  end
  
  # Server Callbacks
  
  def init(opts) do
    state = %__MODULE__{
      current_step: nil,
      message_buffer: [],
      detector: Keyword.fetch!(opts, :detector),
      timeout_ms: Keyword.get(opts, :timeout_ms, 5000),
      timeout_ref: nil,
      emit_callback: Keyword.fetch!(opts, :emit_callback),
      step_id_counter: 0
    }
    
    {:ok, state}
  end
  
  def handle_call({:add_message, message}, _from, state) do
    Logger.debug("Buffer received message: #{inspect(message.type)}")
    
    # Cancel existing timeout
    state = cancel_timeout(state)
    
    # Analyze message
    detection = ClaudeCodeSDK.StepGrouping.Detector.analyze(
      state.detector,
      message,
      state.message_buffer
    )
    
    new_state = case detection do
      {:step_start, type} ->
        Logger.debug("Detected step start: #{type}")
        # Emit current step if exists
        state = maybe_emit_current_step(state)
        # Start new step
        start_new_step(state, type, message)
        
      {:step_end, metadata} ->
        Logger.debug("Detected step end: #{inspect(metadata)}")
        # Complete current step
        complete_and_emit_step(state, message, metadata)
        
      {:step_continue, _} ->
        Logger.debug("Continuing current step")
        # Add to buffer
        continue_step(state, message)
    end
    
    # Set timeout for incomplete steps
    new_state = set_timeout(new_state)
    
    {:reply, :ok, new_state}
  end
  
  def handle_call(:flush, _from, state) do
    state = maybe_emit_current_step(state)
    {:reply, :ok, state}
  end
  
  def handle_info(:step_timeout, state) do
    Logger.debug("Step timeout triggered")
    state = timeout_current_step(state)
    {:noreply, state}
  end
  
  # Private Functions
  
  defp start_new_step(state, type, message) do
    step = ClaudeCodeSDK.Step.new(%{
      id: generate_step_id(state),
      type: type,
      description: extract_description(message),
      messages: [message]
    })
    
    %{state |
      current_step: step,
      message_buffer: [message]
    }
  end
  
  defp continue_step(state, message) do
    if state.current_step do
      %{state |
        current_step: ClaudeCodeSDK.Step.add_message(state.current_step, message),
        message_buffer: state.message_buffer ++ [message]
      }
    else
      # No current step, start implicit one
      start_new_step(state, :unknown, message)
    end
  end
  
  defp complete_and_emit_step(state, last_message, metadata) do
    state = continue_step(state, last_message)
    
    if state.current_step do
      completed_step = state.current_step
      |> ClaudeCodeSDK.Step.complete()
      |> Map.put(:metadata, Map.merge(state.current_step.metadata, metadata))
      |> Map.put(:tools_used, ClaudeCodeSDK.Step.extract_tools(state.current_step))
      
      emit_step(completed_step, state.emit_callback)
      
      %{state |
        current_step: nil,
        message_buffer: []
      }
    else
      state
    end
  end
  
  defp maybe_emit_current_step(state) do
    if state.current_step do
      completed_step = ClaudeCodeSDK.Step.complete(state.current_step)
      |> Map.put(:tools_used, ClaudeCodeSDK.Step.extract_tools(state.current_step))
      
      emit_step(completed_step, state.emit_callback)
      
      %{state |
        current_step: nil,
        message_buffer: []
      }
    else
      state
    end
  end
  
  defp timeout_current_step(state) do
    if state.current_step do
      timeout_step = state.current_step
      |> Map.put(:status, :timeout)
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:tools_used, ClaudeCodeSDK.Step.extract_tools(state.current_step))
      
      emit_step(timeout_step, state.emit_callback)
      
      %{state |
        current_step: nil,
        message_buffer: [],
        timeout_ref: nil
      }
    else
      state
    end
  end
  
  defp emit_step(step, callback) do
    Logger.debug("Emitting step: #{step.id} (#{step.type})")
    send(callback, {:step, step})
  end
  
  defp set_timeout(state) do
    if state.current_step && state.timeout_ms > 0 do
      ref = Process.send_after(self(), :step_timeout, state.timeout_ms)
      %{state | timeout_ref: ref}
    else
      state
    end
  end
  
  defp cancel_timeout(%{timeout_ref: nil} = state), do: state
  defp cancel_timeout(%{timeout_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timeout_ref: nil}
  end
  
  defp generate_step_id(state) do
    counter = state.step_id_counter + 1
    "step_#{counter}"
  end
  
  defp extract_description(message) do
    text = ClaudeCodeSDK.ContentExtractor.extract_text(message) || ""
    # Take first sentence or first 100 chars
    text
    |> String.split(~r/[.!?]/, parts: 2)
    |> List.first()
    |> String.slice(0, 100)
    |> String.trim()
  end
end
```

#### 3.2 Step Stream Transformer

```elixir
# lib/claude_code_sdk/step_grouping/stream.ex
defmodule ClaudeCodeSDK.StepGrouping.Stream do
  @moduledoc """
  Transforms message streams into step streams
  """
  
  require Logger
  
  @doc """
  Transforms a message stream into a step stream
  """
  def transform(message_stream, opts \\ []) do
    Stream.resource(
      # Start function
      fn -> init_transformer(message_stream, opts) end,
      
      # Next function
      fn state -> next_step(state) end,
      
      # Cleanup function
      fn state -> cleanup(state) end
    )
  end
  
  defp init_transformer(message_stream, opts) do
    # Create detector
    detector = ClaudeCodeSDK.StepGrouping.Detector.new(opts)
    
    # Start buffer process
    {:ok, buffer} = ClaudeCodeSDK.StepGrouping.Buffer.start_link(
      detector: detector,
      timeout_ms: Keyword.get(opts, :buffer_timeout_ms, 5000),
      emit_callback: self()
    )
    
    %{
      message_stream: message_stream,
      buffer: buffer,
      pending_steps: :queue.new(),
      stream_done: false
    }
  end
  
  defp next_step(state) do
    # Check for pending steps first
    case get_pending_step(state) do
      {:ok, step, new_state} ->
        {[step], new_state}
        
      :empty ->
        # Process more messages
        process_messages(state)
    end
  end
  
  defp get_pending_step(state) do
    # Check message queue for steps
    receive do
      {:step, step} ->
        {:ok, step, state}
    after
      0 ->
        :empty
    end
  end
  
  defp process_messages(%{stream_done: true} = state) do
    # Stream is done, flush buffer and get remaining steps
    ClaudeCodeSDK.StepGrouping.Buffer.flush(state.buffer)
    
    # Collect any remaining steps
    case collect_remaining_steps(state) do
      [] -> {:halt, state}
      steps -> {steps, %{state | stream_done: :finished}}
    end
  end
  
  defp process_messages(state) do
    # Get next message from stream
    case get_next_message(state.message_stream) do
      {:ok, message, new_stream} ->
        # Add to buffer
        :ok = ClaudeCodeSDK.StepGrouping.Buffer.add_message(state.buffer, message)
        
        # Check for emitted steps
        case get_pending_step(state) do
          {:ok, step, new_state} ->
            {[step], %{new_state | message_stream: new_stream}}
            
          :empty ->
            # Continue processing
            process_messages(%{state | message_stream: new_stream})
        end
        
      :done ->
        # Mark stream as done and process remaining
        process_messages(%{state | stream_done: true})
    end
  end
  
  defp get_next_message(stream) do
    case Enum.take(stream, 1) do
      [message] -> {:ok, message, Stream.drop(stream, 1)}
      [] -> :done
    end
  end
  
  defp collect_remaining_steps(state, timeout \\ 1000) do
    collect_steps_until_timeout([], timeout)
  end
  
  defp collect_steps_until_timeout(acc, timeout) do
    receive do
      {:step, step} ->
        collect_steps_until_timeout(acc ++ [step], timeout)
    after
      timeout ->
        acc
    end
  end
  
  defp cleanup(state) do
    if state.buffer do
      GenServer.stop(state.buffer)
    end
  end
end
```

### Phase 4: Integration (Week 4)

#### 4.1 SDK Integration

```elixir
# lib/claude_code_sdk.ex
defmodule ClaudeCodeSDK do
  # Add new function to existing module
  
  @doc """
  Queries Claude and returns a stream of grouped steps
  """
  def query_with_steps(prompt, options \\ []) do
    # Extract step options
    {step_options, claude_options} = Keyword.pop(options, :step_grouping, [])
    
    # Get message stream
    case query_stream(prompt, claude_options) do
      {:ok, message_stream} ->
        # Transform to steps if enabled
        if Keyword.get(step_options, :enabled, true) do
          step_stream = ClaudeCodeSDK.StepGrouping.Stream.transform(
            message_stream,
            step_options
          )
          {:ok, step_stream}
        else
          {:ok, message_stream}
        end
        
      error ->
        error
    end
  end
  
  @doc """
  Queries Claude with step control
  """
  def query_with_control(prompt, options \\ []) do
    # Extract control options
    {control_options, other_options} = Keyword.pop(options, :step_control, [])
    
    # Get step stream
    case query_with_steps(prompt, other_options) do
      {:ok, step_stream} ->
        # Start controller if needed
        if Keyword.get(control_options, :mode, :automatic) != :automatic do
          {:ok, controller} = ClaudeCodeSDK.StepController.start_link(
            step_stream,
            control_options
          )
          {:ok, controller}
        else
          {:ok, step_stream}
        end
        
      error ->
        error
    end
  end
end
```

#### 4.2 Process Integration

```elixir
# Modify ProcessAsync to support step grouping
defmodule ClaudeCodeSDK.ProcessAsync do
  # Add helper for step grouping
  def message_stream_with_steps(erlexec_pid, opts) do
    message_stream = receive_and_parse_messages(erlexec_pid)
    
    if Keyword.get(opts, :group_steps, false) do
      ClaudeCodeSDK.StepGrouping.Stream.transform(
        message_stream,
        Keyword.get(opts, :step_grouping, [])
      )
    else
      message_stream
    end
  end
end
```

### Phase 5: Testing (Week 5)

#### 5.1 Unit Tests

```elixir
# test/step_grouping/detector_test.exs
defmodule ClaudeCodeSDK.StepGrouping.DetectorTest do
  use ExUnit.Case
  
  alias ClaudeCodeSDK.StepGrouping.Detector
  alias ClaudeCodeSDK.Message
  
  describe "pattern detection" do
    test "detects file operation pattern" do
      detector = Detector.new(patterns: [:file_operation])
      
      message1 = %Message{
        type: :assistant,
        content: "Let me read that configuration file"
      }
      
      result = Detector.analyze(detector, message1, [])
      assert {:step_start, :file_operation} = result
    end
    
    test "detects step completion" do
      detector = Detector.new(patterns: [:file_operation])
      
      buffer = [
        %Message{
          type: :assistant,
          content: "Let me read config.json"
        },
        %Message{
          type: :assistant,
          content: [
            %{"type" => "tool_use", "name" => "read", "input" => %{"file" => "config.json"}}
          ]
        }
      ]
      
      message3 = %Message{
        type: :assistant,
        content: [
          %{"type" => "tool_result", "content" => "{}"},
          %{"type" => "text", "text" => "The configuration is empty"}
        ]
      }
      
      result = Detector.analyze(detector, message3, buffer)
      assert {:step_end, %{pattern_id: :file_operation}} = result
    end
  end
end
```

#### 5.2 Integration Tests

```elixir
# test/step_grouping/integration_test.exs
defmodule ClaudeCodeSDK.StepGrouping.IntegrationTest do
  use ExUnit.Case
  
  test "transforms message stream to step stream" do
    messages = [
      %Message{type: :system, content: "Starting"},
      %Message{type: :assistant, content: "I'll help you read that file"},
      %Message{type: :assistant, content: [
        %{"type" => "tool_use", "name" => "read", "input" => %{}}
      ]},
      %Message{type: :assistant, content: [
        %{"type" => "tool_result", "content" => "file contents"}
      ]},
      %Message{type: :assistant, content: "The file contains..."},
      %Message{type: :assistant, content: "Now let me check another file"},
      %Message{type: :assistant, content: [
        %{"type" => "tool_use", "name" => "read", "input" => %{}}
      ]},
      %Message{type: :assistant, content: [
        %{"type" => "tool_result", "content" => "more contents"}
      ]},
      %Message{type: :result, content: "Done"}
    ]
    
    message_stream = Stream.from_enumerable(messages)
    step_stream = ClaudeCodeSDK.StepGrouping.Stream.transform(message_stream)
    
    steps = Enum.to_list(step_stream)
    
    assert length(steps) == 2
    assert steps |> Enum.at(0) |> Map.get(:type) == :file_operation
    assert steps |> Enum.at(0) |> Map.get(:tools_used) == ["read"]
    assert steps |> Enum.at(1) |> Map.get(:type) == :file_operation
    assert steps |> Enum.at(1) |> Map.get(:tools_used) == ["read"]
  end
end
```

## Deployment

### Configuration

```elixir
# config/config.exs
config :claude_code_sdk,
  step_grouping: [
    enabled: true,
    default_strategy: :pattern_based,
    default_patterns: :default,
    default_confidence_threshold: 0.7,
    default_buffer_timeout_ms: 5000
  ]
```

### Documentation

Update the main SDK documentation:

```markdown
# Claude Code SDK

## New Feature: Stream Step Grouping

The SDK now supports grouping Claude's output into logical steps for better control and review.

### Basic Usage

```elixir
# Get steps instead of messages
{:ok, steps} = ClaudeCodeSDK.query_with_steps(
  "Read all configuration files",
  step_grouping: [enabled: true]
)

Enum.each(steps, fn step ->
  IO.puts("Step #{step.id}: #{step.description}")
  IO.puts("Tools: #{Enum.join(step.tools_used, ", ")}")
end)
```

### With Control

```elixir
{:ok, controller} = ClaudeCodeSDK.query_with_control(
  "Refactor the authentication module",
  step_control: [mode: :manual]
)

# Process with manual control
loop do
  case ClaudeCodeSDK.StepController.next_step(controller) do
    {:ok, step} ->
      # Review and continue
      if safe?(step), do: :ok, else: break
      
    {:paused, step} ->
      # Handle pause
      if approve?(step) do
        ClaudeCodeSDK.StepController.resume(controller)
      else
        ClaudeCodeSDK.StepController.resume(controller, :skip)
      end
      
    :completed ->
      break
  end
end
```
```

## Monitoring

### Metrics

Add telemetry events:

```elixir
# In Buffer module
:telemetry.execute(
  [:claude_code_sdk, :step_grouping, :step_emitted],
  %{count: 1, messages: length(step.messages)},
  %{step_type: step.type}
)

# In Detector module  
:telemetry.execute(
  [:claude_code_sdk, :step_grouping, :detection],
  %{duration: detection_time},
  %{result: detection_result}
)
```

### Logging

Configure appropriate log levels:

```elixir
# config/dev.exs
config :logger, level: :debug

# config/prod.exs
config :logger, level: :info
```

## Next Steps

1. Deploy to staging environment
2. Run performance benchmarks
3. Gather user feedback
4. Implement ML-based detection (Phase 2)
5. Add custom pattern support
6. Build pattern library from usage data