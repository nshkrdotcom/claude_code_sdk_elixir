defmodule ClaudeCodeSDK.StepDetector do
  @moduledoc """
  Detects logical step boundaries in Claude's message stream using pattern-based analysis.

  The StepDetector analyzes incoming messages against configured patterns to identify
  when messages should be grouped together into logical steps. It uses a combination
  of pattern matching, confidence scoring, and heuristic analysis to make detection
  decisions.

  ## Detection Process

  1. **Pattern Matching**: Each message is analyzed against configured patterns
  2. **Confidence Scoring**: Patterns provide confidence scores for matches
  3. **Threshold Filtering**: Only matches above the confidence threshold are considered
  4. **Priority Resolution**: When multiple patterns match, highest priority wins
  5. **Heuristic Fallback**: If no patterns match, heuristic detection is used

  ## Detection Results

  - `{:step_start, step_type, metadata}` - A new step is starting
  - `{:step_continue, nil}` - Current message continues the existing step
  - `{:step_end, step_metadata}` - Current step is ending
  - `{:step_boundary, step_type, metadata}` - Current step ends and new one starts

  ## Examples

      # Create detector with default patterns
      detector = ClaudeCodeSDK.StepDetector.new()

      # Analyze a message
      message = %ClaudeCodeSDK.Message{type: :assistant, data: %{...}}
      result = ClaudeCodeSDK.StepDetector.analyze_message(detector, message, [])

      # Custom detector with specific patterns
      patterns = [file_operation_pattern, code_modification_pattern]
      detector = ClaudeCodeSDK.StepDetector.new(
        patterns: patterns,
        confidence_threshold: 0.8,
        strategy: :pattern_based
      )

  """

  alias ClaudeCodeSDK.{Message, StepPattern, Step}

  defstruct [
    # List of StepPattern structs
    :patterns,
    # Minimum confidence for pattern matches
    :confidence_threshold,
    # Detection strategy (:pattern_based, :heuristic, :hybrid)
    :strategy,
    # Currently detected step type
    :current_step_type,
    # Compiled pattern cache for performance
    :pattern_cache,
    # History of recent detections for context
    :detection_history
  ]

  @type detection_result ::
          {:step_start, Step.step_type(), map()}
          | {:step_continue, nil}
          | {:step_end, map()}
          | {:step_boundary, Step.step_type(), map()}

  @type detection_strategy :: :pattern_based | :heuristic | :hybrid

  @type t :: %__MODULE__{
          patterns: [StepPattern.t()],
          confidence_threshold: float(),
          strategy: detection_strategy(),
          current_step_type: Step.step_type() | nil,
          pattern_cache: map(),
          detection_history: [detection_result()]
        }

  @doc """
  Creates a new StepDetector with the given configuration.

  ## Parameters

  - `opts` - Keyword list of detector options

  ## Options

  - `:patterns` - List of StepPattern structs or `:default` (defaults to `:default`)
  - `:confidence_threshold` - Minimum confidence for matches (defaults to 0.7)
  - `:strategy` - Detection strategy (defaults to `:pattern_based`)
  - `:max_history` - Maximum detection history to keep (defaults to 10)

  ## Examples

      iex> ClaudeCodeSDK.StepDetector.new()
      %ClaudeCodeSDK.StepDetector{
        patterns: [...],
        confidence_threshold: 0.7,
        strategy: :pattern_based
      }

      iex> ClaudeCodeSDK.StepDetector.new(
      ...>   confidence_threshold: 0.8,
      ...>   strategy: :hybrid
      ...> )
      %ClaudeCodeSDK.StepDetector{confidence_threshold: 0.8, strategy: :hybrid}

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    patterns =
      case Keyword.get(opts, :patterns, :default) do
        :default -> StepPattern.default_patterns()
        custom_patterns when is_list(custom_patterns) -> custom_patterns
      end

    detector = %__MODULE__{
      patterns: patterns,
      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.7),
      strategy: Keyword.get(opts, :strategy, :pattern_based),
      current_step_type: nil,
      pattern_cache: %{},
      detection_history: []
    }

    # Pre-compile patterns for performance
    compile_patterns(detector)
  end

  @doc """
  Analyzes a message against configured patterns to detect step boundaries.

  ## Parameters

  - `detector` - The StepDetector instance
  - `message` - The message to analyze
  - `buffer` - List of recent messages for context

  ## Returns

  Detection result tuple indicating the step boundary decision.

  ## Examples

      iex> detector = ClaudeCodeSDK.StepDetector.new()
      iex> message = %ClaudeCodeSDK.Message{type: :assistant}
      iex> ClaudeCodeSDK.StepDetector.analyze_message(detector, message, [])
      {:step_continue, nil}

  """
  @spec analyze_message(t(), Message.t(), [Message.t()]) :: {detection_result(), t()}
  def analyze_message(%__MODULE__{} = detector, %Message{} = message, buffer)
      when is_list(buffer) do
    context = build_analysis_context(message, buffer, detector)

    case detector.strategy do
      :pattern_based -> analyze_with_patterns(detector, context)
      :heuristic -> analyze_with_heuristics(detector, context)
      :hybrid -> analyze_hybrid(detector, context)
    end
  end

  @doc """
  Resets the detector state, clearing current step type and history.

  ## Parameters

  - `detector` - The StepDetector instance

  ## Returns

  Updated detector with cleared state.

  ## Examples

      iex> detector = ClaudeCodeSDK.StepDetector.new()
      iex> reset_detector = ClaudeCodeSDK.StepDetector.reset(detector)
      iex> reset_detector.current_step_type
      nil

  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = detector) do
    %{detector | current_step_type: nil, detection_history: []}
  end

  @doc """
  Updates the detector's patterns and recompiles the pattern cache.

  ## Parameters

  - `detector` - The StepDetector instance
  - `patterns` - New list of StepPattern structs

  ## Returns

  Updated detector with new patterns.

  ## Examples

      iex> detector = ClaudeCodeSDK.StepDetector.new()
      iex> new_patterns = [custom_pattern]
      iex> updated = ClaudeCodeSDK.StepDetector.update_patterns(detector, new_patterns)
      iex> length(updated.patterns)
      1

  """
  @spec update_patterns(t(), [StepPattern.t()]) :: t()
  def update_patterns(%__MODULE__{} = detector, patterns) when is_list(patterns) do
    updated_detector = %{detector | patterns: patterns}
    compile_patterns(updated_detector)
  end

  @doc """
  Gets detection statistics for monitoring and debugging.

  ## Parameters

  - `detector` - The StepDetector instance

  ## Returns

  Map containing detection statistics.

  ## Examples

      iex> detector = ClaudeCodeSDK.StepDetector.new()
      iex> stats = ClaudeCodeSDK.StepDetector.get_stats(detector)
      iex> stats.pattern_count
      6

  """
  @spec get_stats(t()) :: map()
  def get_stats(%__MODULE__{} = detector) do
    %{
      pattern_count: length(detector.patterns),
      confidence_threshold: detector.confidence_threshold,
      strategy: detector.strategy,
      current_step_type: detector.current_step_type,
      history_length: length(detector.detection_history),
      cache_size: map_size(detector.pattern_cache)
    }
  end

  # Private implementation functions

  defp compile_patterns(%__MODULE__{patterns: patterns} = detector) do
    cache =
      Enum.reduce(patterns, %{}, fn pattern, acc ->
        compiled = compile_pattern(pattern)
        Map.put(acc, pattern.id, compiled)
      end)

    %{detector | pattern_cache: cache}
  end

  defp compile_pattern(%StepPattern{} = pattern) do
    compiled_triggers = Enum.map(pattern.triggers, &compile_trigger/1)
    compiled_validators = Enum.map(pattern.validators, &compile_validator/1)

    %{
      pattern: pattern,
      triggers: compiled_triggers,
      validators: compiled_validators
    }
  end

  defp compile_trigger(%{type: :message_content, regex: regex} = trigger)
       when not is_nil(regex) do
    %{trigger | regex: Regex.compile!(Regex.source(regex), Regex.opts(regex))}
  end

  defp compile_trigger(%{type: :tool_usage, tools: tools} = trigger) when is_list(tools) do
    # Convert tools list to MapSet for faster lookups
    %{trigger | tools: MapSet.new(tools)}
  end

  defp compile_trigger(trigger), do: trigger

  defp compile_validator(%{type: :content_regex, regex: regex} = validator)
       when not is_nil(regex) do
    %{validator | regex: Regex.compile!(Regex.source(regex), Regex.opts(regex))}
  end

  defp compile_validator(validator), do: validator

  defp build_analysis_context(message, buffer, detector) do
    %{
      message: message,
      buffer: buffer,
      current_step_type: detector.current_step_type,
      detection_history: detector.detection_history,
      tools_used: extract_tools_from_buffer([message | buffer]),
      content: extract_content_from_message(message)
    }
  end

  defp extract_tools_from_buffer(messages) do
    messages
    |> Enum.flat_map(&extract_tools_from_message/1)
    |> Enum.uniq()
  end

  defp extract_tools_from_message(%Message{
         type: :assistant,
         data: %{message: %{"content" => content}}
       })
       when is_binary(content) do
    # Extract tool names from assistant message content
    # Look for patterns like <function_calls><invoke name="toolName">
    Regex.scan(~r/<invoke name="([^"]+)">/, content, capture: :all_but_first)
    |> List.flatten()
  end

  defp extract_tools_from_message(%Message{type: :assistant, data: %{message: message}})
       when is_map(message) do
    # Handle structured message format
    case message do
      %{"content" => content} when is_list(content) ->
        content
        |> Enum.flat_map(fn
          %{"type" => "tool_use", "name" => name} -> [name]
          _ -> []
        end)

      _ ->
        []
    end
  end

  defp extract_tools_from_message(_), do: []

  defp extract_content_from_message(%Message{
         type: :assistant,
         data: %{message: %{"content" => content}}
       })
       when is_binary(content) do
    content
  end

  defp extract_content_from_message(%Message{type: :assistant, data: %{message: message}})
       when is_map(message) do
    case message do
      %{"content" => content} when is_list(content) ->
        content
        |> Enum.map(fn
          %{"type" => "text", "text" => text} -> text
          %{"text" => text} -> text
          _ -> ""
        end)
        |> Enum.join(" ")

      %{"content" => content} when is_binary(content) ->
        content

      _ ->
        ""
    end
  end

  defp extract_content_from_message(_), do: ""

  defp analyze_with_patterns(detector, context) do
    matches = find_pattern_matches(detector, context)

    case select_best_match(matches, detector.confidence_threshold) do
      {:ok, {pattern, confidence, metadata}} ->
        result = determine_step_boundary(pattern, confidence, metadata, context, detector)
        updated_detector = update_detector_state(detector, result, pattern.id)
        {result, updated_detector}

      :no_match ->
        # Fall back to heuristic analysis
        analyze_with_heuristics(detector, context)
    end
  end

  defp analyze_with_heuristics(detector, context) do
    result = heuristic_analysis(context, detector)
    updated_detector = update_detector_state(detector, result, :heuristic)
    {result, updated_detector}
  end

  defp analyze_hybrid(detector, context) do
    # Try pattern-based first, fall back to heuristics
    case analyze_with_patterns(detector, context) do
      {{:step_continue, nil}, _} = pattern_result ->
        # If patterns suggest continue, double-check with heuristics
        {heuristic_result, _} = analyze_with_heuristics(detector, context)

        case heuristic_result do
          {:step_continue, nil} ->
            pattern_result

          _ ->
            # Heuristics suggest a boundary, use lower confidence
            updated_detector = update_detector_state(detector, heuristic_result, :hybrid)
            {heuristic_result, updated_detector}
        end

      pattern_result ->
        pattern_result
    end
  end

  defp find_pattern_matches(detector, context) do
    detector.patterns
    |> Enum.map(fn pattern ->
      case evaluate_pattern(pattern, context, detector.pattern_cache[pattern.id]) do
        {:match, confidence, metadata} -> {pattern, confidence, metadata}
        :no_match -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp evaluate_pattern(pattern, context, compiled_pattern) do
    with {:ok, trigger_confidence} <- evaluate_triggers(compiled_pattern.triggers, context),
         {:ok, validator_confidence} <- evaluate_validators(compiled_pattern.validators, context) do
      # Combine confidences (weighted average)
      combined_confidence = trigger_confidence * 0.7 + validator_confidence * 0.3
      final_confidence = min(combined_confidence * pattern.confidence, 1.0)

      metadata = %{
        pattern_id: pattern.id,
        trigger_confidence: trigger_confidence,
        validator_confidence: validator_confidence,
        combined_confidence: combined_confidence
      }

      {:match, final_confidence, metadata}
    else
      :no_match -> :no_match
    end
  end

  defp evaluate_triggers(triggers, context) do
    trigger_results = Enum.map(triggers, &evaluate_trigger(&1, context))

    case Enum.filter(trigger_results, &(&1 != :no_match)) do
      [] ->
        :no_match

      matches ->
        confidences = Enum.map(matches, fn {:match, conf} -> conf end)
        avg_confidence = Enum.sum(confidences) / length(confidences)
        {:ok, avg_confidence}
    end
  end

  defp evaluate_trigger(%{type: :message_content, regex: regex}, %{content: content})
       when not is_nil(regex) do
    if Regex.match?(regex, content) do
      {:match, 0.8}
    else
      :no_match
    end
  end

  defp evaluate_trigger(%{type: :tool_usage, tools: tool_set}, %{tools_used: tools_used})
       when is_struct(tool_set, MapSet) do
    matching_tools = MapSet.intersection(tool_set, MapSet.new(tools_used))

    if MapSet.size(matching_tools) > 0 do
      # Confidence based on how many tools match
      confidence = min(MapSet.size(matching_tools) / MapSet.size(tool_set), 1.0) * 0.9
      {:match, confidence}
    else
      :no_match
    end
  end

  defp evaluate_trigger(%{type: :message_sequence, sequence: sequence}, %{buffer: buffer})
       when is_list(sequence) do
    recent_types = Enum.take(buffer, length(sequence)) |> Enum.map(& &1.type) |> Enum.reverse()

    if recent_types == sequence do
      {:match, 0.85}
    else
      :no_match
    end
  end

  defp evaluate_trigger(%{type: :custom_function, function: func}, context)
       when is_function(func, 1) do
    try do
      if func.(context) do
        {:match, 0.7}
      else
        :no_match
      end
    rescue
      _ -> :no_match
    end
  end

  defp evaluate_trigger(_, _), do: :no_match

  defp evaluate_validators([], _context), do: {:ok, 1.0}

  defp evaluate_validators(validators, context) do
    validator_results = Enum.map(validators, &evaluate_validator(&1, context))

    case Enum.filter(validator_results, &(&1 != :no_match)) do
      [] ->
        :no_match

      matches ->
        confidences = Enum.map(matches, fn {:match, conf} -> conf end)
        avg_confidence = Enum.sum(confidences) / length(confidences)
        {:ok, avg_confidence}
    end
  end

  defp evaluate_validator(%{type: :content_regex, regex: regex}, %{content: content})
       when not is_nil(regex) do
    if Regex.match?(regex, content) do
      {:match, 0.9}
    else
      :no_match
    end
  end

  defp evaluate_validator(%{type: :tool_sequence, min_tools: min_tools}, %{tools_used: tools_used})
       when not is_nil(min_tools) do
    if length(tools_used) >= min_tools do
      {:match, 0.8}
    else
      :no_match
    end
  end

  defp evaluate_validator(%{type: :tool_sequence, max_tools: max_tools}, %{tools_used: tools_used})
       when not is_nil(max_tools) do
    if length(tools_used) <= max_tools do
      {:match, 0.8}
    else
      :no_match
    end
  end

  defp evaluate_validator(%{type: :message_count, min_messages: min_messages}, %{buffer: buffer})
       when not is_nil(min_messages) do
    if length(buffer) >= min_messages do
      {:match, 0.7}
    else
      :no_match
    end
  end

  defp evaluate_validator(%{type: :message_count, max_messages: max_messages}, %{buffer: buffer})
       when not is_nil(max_messages) do
    if length(buffer) <= max_messages do
      {:match, 0.7}
    else
      :no_match
    end
  end

  defp evaluate_validator(%{type: :custom_function, function: func}, context)
       when is_function(func, 1) do
    try do
      if func.(context) do
        {:match, 0.8}
      else
        :no_match
      end
    rescue
      _ -> :no_match
    end
  end

  defp evaluate_validator(_, _), do: {:match, 1.0}

  defp select_best_match(matches, threshold) do
    matches
    |> Enum.filter(fn {_pattern, confidence, _metadata} -> confidence >= threshold end)
    |> Enum.sort_by(
      fn {pattern, confidence, _metadata} -> {pattern.priority, confidence} end,
      :desc
    )
    |> case do
      [{pattern, confidence, metadata} | _] -> {:ok, {pattern, confidence, metadata}}
      [] -> :no_match
    end
  end

  defp determine_step_boundary(pattern, confidence, metadata, _context, detector) do
    step_type = pattern.id

    cond do
      # No current step - start new one
      detector.current_step_type == nil ->
        {:step_start, step_type, Map.put(metadata, :confidence, confidence)}

      # Same step type - continue
      detector.current_step_type == step_type ->
        {:step_continue, nil}

      # Different step type - boundary
      detector.current_step_type != step_type ->
        {:step_boundary, step_type, Map.put(metadata, :confidence, confidence)}
    end
  end

  defp heuristic_analysis(context, detector) do
    cond do
      # Message indicates completion
      completion_indicators?(context.content) ->
        {:step_end, %{reason: :completion_detected, confidence: 0.6}}

      # Tool usage suggests new step
      new_tool_category?(context.tools_used, detector.current_step_type) ->
        new_type = infer_step_type_from_tools(context.tools_used)
        metadata = %{reason: :tool_change, confidence: 0.5}

        # Apply same logic as pattern-based detection
        cond do
          detector.current_step_type == nil ->
            {:step_start, new_type, metadata}

          detector.current_step_type == new_type ->
            {:step_continue, nil}

          detector.current_step_type != new_type ->
            {:step_boundary, new_type, metadata}
        end

      # Default to continue
      true ->
        {:step_continue, nil}
    end
  end

  defp completion_indicators?(content) do
    completion_patterns = [
      ~r/completed?/i,
      ~r/finished/i,
      ~r/done/i,
      ~r/successfully/i,
      ~r/ready/i
    ]

    Enum.any?(completion_patterns, &Regex.match?(&1, content))
  end

  defp new_tool_category?(tools_used, current_step_type) do
    inferred_type = infer_step_type_from_tools(tools_used)
    inferred_type != current_step_type and inferred_type != :unknown
  end

  defp infer_step_type_from_tools(tools_used) do
    cond do
      Enum.any?(
        tools_used,
        &(&1 in ["readFile", "fsWrite", "fsAppend", "listDirectory", "deleteFile"])
      ) ->
        :file_operation

      Enum.any?(tools_used, &(&1 in ["strReplace"])) ->
        :code_modification

      Enum.any?(tools_used, &(&1 in ["executePwsh"])) ->
        :system_command

      Enum.any?(tools_used, &(&1 in ["grepSearch", "fileSearch"])) ->
        :exploration

      Enum.any?(tools_used, &(&1 in ["readMultipleFiles"])) ->
        :analysis

      true ->
        :unknown
    end
  end

  defp update_detector_state(detector, result, _pattern_id) do
    new_step_type =
      case result do
        {:step_start, type, _} -> type
        {:step_boundary, type, _} -> type
        {:step_end, _} -> nil
        {:step_continue, nil} -> detector.current_step_type
      end

    new_history = [result | detector.detection_history] |> Enum.take(10)

    %{detector | current_step_type: new_step_type, detection_history: new_history}
  end
end
