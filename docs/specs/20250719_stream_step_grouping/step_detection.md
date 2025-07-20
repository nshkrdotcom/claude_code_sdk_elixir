# Step Detection Patterns

## Overview

This document details the patterns and algorithms used to detect logical step boundaries in Claude's message stream. Accurate step detection is crucial for enabling pause/resume functionality and safety reviews.

## Step Detection Strategies

### 1. Pattern-Based Detection

The primary detection strategy uses pattern matching to identify common step structures.

#### Core Patterns

```elixir
defmodule ClaudeCodeSDK.StepDetector.Patterns do
  @moduledoc """
  Built-in patterns for step detection
  """
  
  # Pattern structure
  @type pattern :: %{
    id: atom(),
    name: String.t(),
    description: String.t(),
    triggers: [trigger()],
    validators: [validator()],
    priority: integer(),
    confidence: float()
  }
  
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
end
```

#### Built-in Pattern Library

##### 1. File Operation Pattern

```elixir
@file_operation_pattern %{
  id: :file_operation,
  name: "File Operation",
  description: "Reading, writing, or analyzing files",
  triggers: [
    {:message_text, ~r/\b(read|check|examine|look at|analyze|open)\s+(\w+\.\w+|file|directory)/i},
    {:tool_use, "read"},
    {:tool_use, "write"},
    {:tool_use, "edit"}
  ],
  validators: [
    {:has_tool_use, true},
    {:has_tool_result, true},
    {:min_messages, 2},
    {:max_messages, 10}
  ],
  priority: 10,
  confidence: 0.9
}
```

Example Detection:
```
✓ "Let me read the config file"          -> STEP START (trigger match)
✓ tool_use: read("config.json")          -> continues step
✓ tool_result: "{...}"                   -> continues step
✓ "The configuration shows..."           -> STEP END (validators pass)
```

##### 2. Code Modification Pattern

```elixir
@code_modification_pattern %{
  id: :code_modification,
  name: "Code Modification",
  description: "Making changes to code files",
  triggers: [
    {:message_text, ~r/\b(fix|update|modify|change|refactor|implement|add|remove)\b.*\b(code|function|method|class)/i},
    {:tool_use, "edit"},
    {:tool_use, "write"}
  ],
  validators: [
    {:has_tool_use, true},
    {:has_tool_result, true},
    {:contains_text, ~r/(updated|fixed|changed|modified|implemented)/i}
  ],
  priority: 15,
  confidence: 0.85
}
```

##### 3. System Command Pattern

```elixir
@system_command_pattern %{
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
}
```

##### 4. Search/Exploration Pattern

```elixir
@exploration_pattern %{
  id: :exploration,
  name: "Search/Exploration",
  description: "Searching for information or exploring code",
  triggers: [
    {:message_text, ~r/\b(search|find|look for|explore|investigate|discover)\b/i},
    {:tool_use, "grep"},
    {:tool_use, "find"},
    {:tool_sequence, ["ls", "read"]}
  ],
  validators: [
    {:min_messages, 2},
    {:max_messages, 20}
  ],
  priority: 8,
  confidence: 0.75
}
```

##### 5. Analysis Pattern

```elixir
@analysis_pattern %{
  id: :analysis,
  name: "Analysis",
  description: "Analyzing code or data",
  triggers: [
    {:message_text, ~r/\b(analyze|examining|understanding|reviewing|checking)\b/i},
    {:message_count, 3}  # Analysis often involves multiple messages
  ],
  validators: [
    {:min_messages, 3},
    {:contains_text, ~r/(found|discovered|appears|seems|shows)/i}
  ],
  priority: 7,
  confidence: 0.7
}
```

### 2. State Machine Detection

A complementary approach using state machines for complex patterns.

```elixir
defmodule ClaudeCodeSDK.StepDetector.StateMachine do
  @moduledoc """
  State machine-based step detection
  """
  
  defstruct [:current_state, :transitions, :step_buffer, :metadata]
  
  @states [:idle, :step_started, :tool_executing, :tool_completed, :step_ending]
  
  def new() do
    %__MODULE__{
      current_state: :idle,
      transitions: build_transitions(),
      step_buffer: [],
      metadata: %{}
    }
  end
  
  defp build_transitions() do
    %{
      idle: [
        {&is_step_start?/1, :step_started}
      ],
      step_started: [
        {&is_tool_use?/1, :tool_executing},
        {&is_explanation?/1, :step_started},
        {&is_completion?/1, :step_ending}
      ],
      tool_executing: [
        {&is_tool_result?/1, :tool_completed}
      ],
      tool_completed: [
        {&is_tool_use?/1, :tool_executing},
        {&is_summary?/1, :step_ending},
        {&is_continuation?/1, :step_started}
      ],
      step_ending: [
        {&always/1, :idle}
      ]
    }
  end
  
  def process_message(machine, message) do
    transitions = machine.transitions[machine.current_state]
    
    new_state = Enum.find_value(transitions, machine.current_state, fn {predicate, next_state} ->
      if predicate.(message), do: next_state
    end)
    
    action = determine_action(machine.current_state, new_state)
    
    {action, %{machine | 
      current_state: new_state,
      step_buffer: update_buffer(machine.step_buffer, message, action)
    }}
  end
  
  defp determine_action(:idle, :step_started), do: :start_step
  defp determine_action(_, :step_ending), do: :end_step
  defp determine_action(_, _), do: :continue
end
```

### 3. Heuristic Detection

Fallback heuristics for edge cases.

```elixir
defmodule ClaudeCodeSDK.StepDetector.Heuristics do
  @moduledoc """
  Heuristic-based detection for edge cases
  """
  
  @doc """
  Time-based grouping when patterns fail
  """
  def detect_by_time_gap(messages, threshold_ms \\ 3000) do
    messages
    |> Enum.chunk_by(fn msg ->
      # Group messages within time threshold
      div(msg.timestamp, threshold_ms)
    end)
    |> Enum.map(&create_step_from_chunk/1)
  end
  
  @doc """
  Tool-based grouping
  """
  def detect_by_tool_usage(messages) do
    messages
    |> Enum.chunk_by(&extract_tool_session/1)
    |> Enum.filter(&has_tool_usage?/1)
    |> Enum.map(&create_step_from_chunk/1)
  end
  
  @doc """
  Length-based grouping for very long outputs
  """
  def detect_by_length(messages, max_messages \\ 20) do
    messages
    |> Enum.chunk_every(max_messages)
    |> Enum.map(&create_step_from_chunk/1)
  end
  
  @doc """
  Semantic similarity grouping
  """
  def detect_by_similarity(messages, threshold \\ 0.7) do
    messages
    |> Enum.reduce([], fn message, groups ->
      case find_similar_group(message, groups, threshold) do
        nil -> groups ++ [[message]]
        index -> List.update_at(groups, index, &(&1 ++ [message]))
      end
    end)
    |> Enum.map(&create_step_from_chunk/1)
  end
end
```

## Advanced Detection Techniques

### 1. Context-Aware Detection

```elixir
defmodule ClaudeCodeSDK.StepDetector.ContextAware do
  @moduledoc """
  Uses conversation context to improve detection
  """
  
  def detect_with_context(message, buffer, context) do
    # Consider the original prompt
    task_type = analyze_task_type(context.original_prompt)
    
    # Adjust patterns based on task
    patterns = select_patterns_for_task(task_type)
    
    # Consider conversation flow
    flow_state = analyze_conversation_flow(buffer)
    
    # Make context-aware decision
    make_detection_decision(message, patterns, flow_state)
  end
  
  defp analyze_task_type(prompt) do
    cond do
      prompt =~ ~r/debug|fix|error/i -> :debugging
      prompt =~ ~r/implement|create|build/i -> :implementation
      prompt =~ ~r/analyze|review|understand/i -> :analysis
      prompt =~ ~r/refactor|optimize|improve/i -> :refactoring
      true -> :general
    end
  end
  
  defp select_patterns_for_task(:debugging) do
    # Prioritize exploration and analysis patterns
    [@exploration_pattern, @analysis_pattern, @code_modification_pattern]
  end
  
  defp select_patterns_for_task(:implementation) do
    # Prioritize file creation and modification
    [@file_operation_pattern, @code_modification_pattern]
  end
end
```

### 2. Machine Learning Detection (Future)

```elixir
defmodule ClaudeCodeSDK.StepDetector.MLBased do
  @moduledoc """
  Machine learning-based detection (placeholder for future implementation)
  """
  
  @doc """
  Uses a trained model to detect step boundaries
  """
  def detect_with_ml(message, buffer, model) do
    # Extract features
    features = extract_features(message, buffer)
    
    # Run inference
    prediction = model.predict(features)
    
    # Convert to detection result
    case prediction do
      %{class: "step_start", confidence: conf} when conf > 0.8 ->
        {:step_start, prediction.step_type}
      %{class: "step_end", confidence: conf} when conf > 0.8 ->
        {:step_end, build_metadata(buffer)}
      _ ->
        {:step_continue, nil}
    end
  end
  
  defp extract_features(message, buffer) do
    %{
      # Message features
      message_type: message.type,
      has_tool_use: has_tool_use?(message),
      text_length: String.length(message.content || ""),
      
      # Buffer features
      buffer_length: length(buffer),
      tools_in_buffer: count_tools(buffer),
      time_since_start: calculate_time_span(buffer),
      
      # Linguistic features
      starts_with_action_verb: starts_with_action_verb?(message),
      contains_completion_words: contains_completion_words?(message),
      sentiment: analyze_sentiment(message)
    }
  end
end
```

## Detection Algorithm Flow

### Main Detection Pipeline

```elixir
defmodule ClaudeCodeSDK.StepDetector do
  def detect(message, buffer, config) do
    # 1. Pre-process message
    processed_message = preprocess(message)
    
    # 2. Run pattern detection
    pattern_result = detect_with_patterns(processed_message, buffer, config.patterns)
    
    # 3. Run state machine detection
    state_result = detect_with_state_machine(processed_message, buffer)
    
    # 4. Combine results
    combined_result = combine_detection_results([pattern_result, state_result])
    
    # 5. Apply confidence threshold
    if combined_result.confidence >= config.confidence_threshold do
      combined_result
    else
      # 6. Fall back to heuristics
      detect_with_heuristics(processed_message, buffer)
    end
  end
  
  defp combine_detection_results(results) do
    # Weighted voting
    weights = %{pattern: 0.6, state_machine: 0.4}
    
    weighted_confidence = Enum.reduce(results, 0.0, fn {type, result}, acc ->
      acc + (weights[type] * result.confidence)
    end)
    
    %{
      decision: majority_decision(results),
      confidence: weighted_confidence,
      metadata: merge_metadata(results)
    }
  end
end
```

## Pattern Configuration

### Custom Pattern Definition

```elixir
# In configuration file or runtime
custom_patterns = [
  %{
    id: :database_operation,
    name: "Database Operation",
    triggers: [
      {:message_text, ~r/\b(query|insert|update|delete|SELECT|INSERT|UPDATE|DELETE)\b/i},
      {:tool_use, "sql"}
    ],
    validators: [
      {:has_tool_result, true},
      {:contains_text, ~r/(rows?|record|result)/i}
    ],
    priority: 10,
    confidence: 0.85
  },
  
  %{
    id: :test_execution,
    name: "Test Execution",
    triggers: [
      {:message_text, ~r/\b(test|testing|run tests|execute tests)\b/i},
      {:tool_use, "bash"},
      {:tool_sequence, ["pytest", "jest", "mix test"]}
    ],
    validators: [
      {:has_tool_result, true},
      {:contains_text, ~r/(passed|failed|test)/i}
    ],
    priority: 12,
    confidence: 0.9
  }
]

config = %{
  detection_strategy: :pattern_based,
  patterns: :default ++ custom_patterns,
  confidence_threshold: 0.7
}
```

### Pattern Tuning

```elixir
defmodule ClaudeCodeSDK.StepDetector.PatternTuner do
  @doc """
  Analyzes detection accuracy and suggests pattern adjustments
  """
  def analyze_accuracy(detected_steps, manual_annotations) do
    metrics = calculate_metrics(detected_steps, manual_annotations)
    
    suggestions = generate_suggestions(metrics)
    
    %{
      accuracy: metrics.accuracy,
      precision: metrics.precision,
      recall: metrics.recall,
      suggestions: suggestions
    }
  end
  
  defp generate_suggestions(metrics) do
    suggestions = []
    
    if metrics.precision < 0.8 do
      suggestions ++ ["Increase confidence thresholds", "Add more validators"]
    end
    
    if metrics.recall < 0.8 do
      suggestions ++ ["Add more trigger patterns", "Lower confidence threshold"]
    end
    
    if metrics.false_positives > 10 do
      suggestions ++ ["Review and refine trigger patterns", "Add negative patterns"]
    end
    
    suggestions
  end
end
```

## Testing Patterns

### Pattern Test Suite

```elixir
defmodule ClaudeCodeSDK.StepDetector.PatternTest do
  use ExUnit.Case
  
  describe "file operation pattern" do
    test "detects simple file read" do
      messages = [
        %Message{content: "Let me read the configuration file"},
        %Message{content: tool_use("read", %{file: "config.json"})},
        %Message{content: tool_result("{...}")},
        %Message{content: "The configuration contains..."}
      ]
      
      result = detect_steps(messages)
      
      assert length(result) == 1
      assert result |> List.first() |> Map.get(:type) == :file_operation
    end
    
    test "detects multi-file operation" do
      messages = [
        %Message{content: "I'll check both configuration files"},
        %Message{content: tool_use("read", %{file: "config.json"})},
        %Message{content: tool_result("{...}")},
        %Message{content: tool_use("read", %{file: "settings.json"})},
        %Message{content: tool_result("{...}")},
        %Message{content: "Both files are properly configured"}
      ]
      
      result = detect_steps(messages)
      
      assert length(result) == 1
      assert result |> List.first() |> Map.get(:tools_used) == ["read", "read"]
    end
  end
  
  describe "edge cases" do
    test "handles interrupted tool usage" do
      messages = [
        %Message{content: "Let me read that file"},
        %Message{content: tool_use("read", %{file: "test.txt"})},
        %Message{content: "Actually, let me check something else first"},
        %Message{content: tool_use("ls", %{})},
        %Message{content: tool_result("file1 file2")}
      ]
      
      result = detect_steps(messages)
      
      # Should detect incomplete step and new step
      assert length(result) == 2
    end
  end
end
```

## Performance Optimization

### Pattern Matching Optimization

```elixir
defmodule ClaudeCodeSDK.StepDetector.Optimizer do
  @doc """
  Optimizes pattern matching for performance
  """
  
  # Pre-compile all regex patterns
  def precompile_patterns(patterns) do
    Enum.map(patterns, fn pattern ->
      %{pattern |
        triggers: precompile_triggers(pattern.triggers),
        validators: precompile_validators(pattern.validators)
      }
    end)
  end
  
  # Use pattern indexes for fast lookup
  def build_pattern_index(patterns) do
    patterns
    |> Enum.reduce(%{}, fn pattern, acc ->
      pattern.triggers
      |> Enum.reduce(acc, fn trigger, acc2 ->
        key = trigger_key(trigger)
        Map.update(acc2, key, [pattern], &[pattern | &1])
      end)
    end)
  end
  
  # Cache detection results
  def with_cache(detector, cache_size \\ 100) do
    cache = :ets.new(:detection_cache, [:set, :public])
    
    fn message, buffer ->
      key = cache_key(message, buffer)
      
      case :ets.lookup(cache, key) do
        [{^key, result}] -> result
        [] ->
          result = detector.(message, buffer)
          :ets.insert(cache, {key, result})
          maintain_cache_size(cache, cache_size)
          result
      end
    end
  end
end
```

## Debugging Support

### Detection Debugger

```elixir
defmodule ClaudeCodeSDK.StepDetector.Debugger do
  @doc """
  Provides detailed debugging information for pattern matching
  """
  def debug_detection(message, buffer, patterns) do
    results = Enum.map(patterns, fn pattern ->
      %{
        pattern: pattern.id,
        triggers_matched: evaluate_triggers(pattern.triggers, message),
        validators_passed: evaluate_validators(pattern.validators, buffer ++ [message]),
        confidence: pattern.confidence,
        would_detect: would_detect?(pattern, message, buffer)
      }
    end)
    
    IO.inspect(results, label: "Detection Debug Results")
    results
  end
  
  def visualize_detection(messages) do
    messages
    |> Enum.with_index()
    |> Enum.each(fn {msg, idx} ->
      IO.puts("Message #{idx}: #{inspect(msg.type)}")
      IO.puts("  Content: #{String.slice(msg.content || "", 0..50)}...")
      IO.puts("  Detection: #{inspect(detect_step_boundary(msg))}")
      IO.puts("")
    end)
  end
end
```