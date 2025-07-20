defmodule ClaudeCodeSDK.StepPatternOptimizer do
  @moduledoc """
  Optimizes step patterns for better detection performance and accuracy.

  The optimizer provides pattern pre-compilation, indexing, result caching,
  and performance tuning utilities to improve step detection speed and accuracy.

  ## Features

  - **Pattern Pre-compilation**: Compiles regex patterns and creates lookup indexes
  - **Result Caching**: Caches detection results for repeated message patterns
  - **Performance Indexing**: Creates indexes for fast pattern matching
  - **Accuracy Tuning**: Provides utilities for improving pattern accuracy

  ## Examples

      # Optimize patterns for performance
      patterns = StepPattern.default_patterns()
      optimized = StepPatternOptimizer.optimize_patterns(patterns)

      # Create result cache
      cache = StepPatternOptimizer.new_cache()

      # Cache detection result
      cache = StepPatternOptimizer.cache_result(cache, message_key, result)

      # Get cached result
      case StepPatternOptimizer.get_cached_result(cache, message_key) do
        {:hit, result} -> result
        :miss -> # perform detection
      end

  """

  alias ClaudeCodeSDK.{StepPattern, Message}

  defstruct [
    # Pre-compiled pattern data
    :compiled_patterns,
    # Index of tools to patterns
    :tool_index,
    # Index of content patterns
    :content_index,
    # LRU cache for detection results
    :result_cache,
    # Cache hit/miss statistics
    :cache_stats,
    # Performance tracking data
    :performance_metrics
  ]

  # {message_type, tools, content_hash}
  @type cache_key :: {atom(), [String.t()], String.t()}
  @type cache_result :: {:hit, any()} | :miss
  @type optimization_options :: [
          cache_size: integer(),
          enable_indexing: boolean(),
          enable_caching: boolean(),
          performance_tracking: boolean()
        ]

  @type t :: %__MODULE__{
          compiled_patterns: map(),
          tool_index: map(),
          content_index: map(),
          result_cache: map(),
          cache_stats: map(),
          performance_metrics: map()
        }

  @doc """
  Creates a new pattern optimizer with the given options.

  ## Parameters

  - `opts` - Optimization options

  ## Options

  - `:cache_size` - Maximum number of cached results (default: 1000)
  - `:enable_indexing` - Enable pattern indexing (default: true)
  - `:enable_caching` - Enable result caching (default: true)
  - `:performance_tracking` - Enable performance metrics (default: false)

  ## Examples

      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> optimizer.cache_stats.hits
      0

  """
  @spec new(optimization_options()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      compiled_patterns: %{},
      tool_index: %{},
      content_index: %{},
      result_cache: %{},
      cache_stats: %{
        hits: 0,
        misses: 0,
        evictions: 0,
        max_size: Keyword.get(opts, :cache_size, 1000)
      },
      performance_metrics: %{
        total_detections: 0,
        cache_enabled: Keyword.get(opts, :enable_caching, true),
        indexing_enabled: Keyword.get(opts, :enable_indexing, true),
        tracking_enabled: Keyword.get(opts, :performance_tracking, false)
      }
    }
  end

  @doc """
  Optimizes a list of patterns for better performance.

  ## Parameters

  - `patterns` - List of StepPattern structs to optimize
  - `opts` - Optimization options

  ## Returns

  Optimized pattern data structure.

  ## Examples

      iex> patterns = StepPattern.default_patterns()
      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> optimized = ClaudeCodeSDK.StepPatternOptimizer.optimize_patterns(optimizer, patterns)
      iex> map_size(optimized.compiled_patterns) > 0
      true

  """
  @spec optimize_patterns(t(), [StepPattern.t()]) :: t()
  def optimize_patterns(%__MODULE__{} = optimizer, patterns) when is_list(patterns) do
    start_time =
      if optimizer.performance_metrics.tracking_enabled, do: System.monotonic_time(:microsecond)

    # Compile patterns
    compiled = compile_patterns(patterns)

    # Build indexes if enabled
    {tool_index, content_index} =
      if optimizer.performance_metrics.indexing_enabled do
        build_indexes(patterns)
      else
        {%{}, %{}}
      end

    # Update performance metrics
    updated_metrics =
      if optimizer.performance_metrics.tracking_enabled do
        end_time = System.monotonic_time(:microsecond)
        duration = end_time - start_time

        Map.merge(optimizer.performance_metrics, %{
          last_optimization_time_us: duration,
          patterns_optimized: length(patterns),
          optimization_count: Map.get(optimizer.performance_metrics, :optimization_count, 0) + 1
        })
      else
        optimizer.performance_metrics
      end

    %{
      optimizer
      | compiled_patterns: compiled,
        tool_index: tool_index,
        content_index: content_index,
        performance_metrics: updated_metrics
    }
  end

  @doc """
  Gets a cached detection result if available.

  ## Parameters

  - `optimizer` - The optimizer instance
  - `cache_key` - The cache key for the result

  ## Returns

  `{:hit, result}` if cached, `:miss` if not cached.

  ## Examples

      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> key = {:assistant, ["readFile"], "content_hash"}
      iex> ClaudeCodeSDK.StepPatternOptimizer.get_cached_result(optimizer, key)
      :miss

  """
  @spec get_cached_result(t(), cache_key()) :: {cache_result(), t()}
  def get_cached_result(%__MODULE__{} = optimizer, cache_key) do
    if optimizer.performance_metrics.cache_enabled do
      case Map.get(optimizer.result_cache, cache_key) do
        nil ->
          updated_stats = update_cache_stats(optimizer.cache_stats, :miss)
          {:miss, %{optimizer | cache_stats: updated_stats}}

        {result, _timestamp} ->
          updated_stats = update_cache_stats(optimizer.cache_stats, :hit)
          {{:hit, result}, %{optimizer | cache_stats: updated_stats}}
      end
    else
      {:miss, optimizer}
    end
  end

  @doc """
  Caches a detection result.

  ## Parameters

  - `optimizer` - The optimizer instance
  - `cache_key` - The cache key
  - `result` - The detection result to cache

  ## Returns

  Updated optimizer with cached result.

  ## Examples

      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> key = {:assistant, ["readFile"], "hash"}
      iex> result = {:step_start, :file_operation, %{}}
      iex> updated = ClaudeCodeSDK.StepPatternOptimizer.cache_result(optimizer, key, result)
      iex> {cached, _} = ClaudeCodeSDK.StepPatternOptimizer.get_cached_result(updated, key)
      iex> cached
      {:hit, {:step_start, :file_operation, %{}}}

  """
  @spec cache_result(t(), cache_key(), any()) :: t()
  def cache_result(%__MODULE__{} = optimizer, cache_key, result) do
    if optimizer.performance_metrics.cache_enabled do
      timestamp = System.monotonic_time(:millisecond)

      # Check if cache is full and needs eviction
      {updated_cache, updated_stats} =
        if map_size(optimizer.result_cache) >= optimizer.cache_stats.max_size do
          evict_oldest_entry(optimizer.result_cache, optimizer.cache_stats)
        else
          {optimizer.result_cache, optimizer.cache_stats}
        end

      new_cache = Map.put(updated_cache, cache_key, {result, timestamp})

      %{optimizer | result_cache: new_cache, cache_stats: updated_stats}
    else
      optimizer
    end
  end

  @doc """
  Creates a cache key for a message and context.

  ## Parameters

  - `message` - The message to create a key for
  - `tools_used` - List of tools used
  - `content` - Message content

  ## Returns

  Cache key tuple.

  ## Examples

      iex> message = %ClaudeCodeSDK.Message{type: :assistant}
      iex> key = ClaudeCodeSDK.StepPatternOptimizer.create_cache_key(message, ["readFile"], "content")
      iex> {message_type, tools, content_hash} = key
      iex> message_type
      :assistant

  """
  @spec create_cache_key(Message.t(), [String.t()], String.t()) :: cache_key()
  def create_cache_key(%Message{type: type}, tools_used, content) do
    # Create a hash of the content to keep keys manageable
    content_hash = :crypto.hash(:md5, content) |> Base.encode16(case: :lower)
    {type, Enum.sort(tools_used), content_hash}
  end

  @doc """
  Gets patterns that are likely to match based on tools used.

  ## Parameters

  - `optimizer` - The optimizer instance
  - `tools_used` - List of tools used in the message

  ## Returns

  List of pattern IDs that might match.

  ## Examples

      iex> patterns = StepPattern.default_patterns()
      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> optimized = ClaudeCodeSDK.StepPatternOptimizer.optimize_patterns(optimizer, patterns)
      iex> candidates = ClaudeCodeSDK.StepPatternOptimizer.get_pattern_candidates(optimized, ["readFile"])
      iex> :file_operation in candidates
      true

  """
  @spec get_pattern_candidates(t(), [String.t()]) :: [atom()]
  def get_pattern_candidates(%__MODULE__{} = optimizer, tools_used) when is_list(tools_used) do
    if optimizer.performance_metrics.indexing_enabled and map_size(optimizer.tool_index) > 0 do
      tools_used
      |> Enum.flat_map(fn tool -> Map.get(optimizer.tool_index, tool, []) end)
      |> Enum.uniq()
    else
      # Return all pattern IDs if indexing is disabled
      Map.keys(optimizer.compiled_patterns)
    end
  end

  @doc """
  Gets performance statistics for the optimizer.

  ## Parameters

  - `optimizer` - The optimizer instance

  ## Returns

  Map containing performance statistics.

  ## Examples

      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> stats = ClaudeCodeSDK.StepPatternOptimizer.get_performance_stats(optimizer)
      iex> stats.cache_hit_rate
      0.0

  """
  @spec get_performance_stats(t()) :: map()
  def get_performance_stats(%__MODULE__{} = optimizer) do
    cache_stats = optimizer.cache_stats
    total_requests = cache_stats.hits + cache_stats.misses
    hit_rate = if total_requests > 0, do: cache_stats.hits / total_requests, else: 0.0

    %{
      cache_hit_rate: hit_rate,
      cache_hits: cache_stats.hits,
      cache_misses: cache_stats.misses,
      cache_evictions: cache_stats.evictions,
      cache_size: map_size(optimizer.result_cache),
      cache_max_size: cache_stats.max_size,
      patterns_compiled: map_size(optimizer.compiled_patterns),
      tool_index_size: map_size(optimizer.tool_index),
      content_index_size: map_size(optimizer.content_index),
      performance_metrics: optimizer.performance_metrics
    }
  end

  @doc """
  Clears the result cache.

  ## Parameters

  - `optimizer` - The optimizer instance

  ## Returns

  Optimizer with cleared cache.

  ## Examples

      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> cleared = ClaudeCodeSDK.StepPatternOptimizer.clear_cache(optimizer)
      iex> map_size(cleared.result_cache)
      0

  """
  @spec clear_cache(t()) :: t()
  def clear_cache(%__MODULE__{} = optimizer) do
    %{
      optimizer
      | result_cache: %{},
        cache_stats: %{optimizer.cache_stats | hits: 0, misses: 0, evictions: 0}
    }
  end

  @doc """
  Provides tuning suggestions based on performance metrics.

  ## Parameters

  - `optimizer` - The optimizer instance

  ## Returns

  List of tuning suggestions.

  ## Examples

      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> suggestions = ClaudeCodeSDK.StepPatternOptimizer.get_tuning_suggestions(optimizer)
      iex> is_list(suggestions)
      true

  """
  @spec get_tuning_suggestions(t()) :: [String.t()]
  def get_tuning_suggestions(%__MODULE__{} = optimizer) do
    stats = get_performance_stats(optimizer)
    suggestions = []

    suggestions =
      if stats.cache_hit_rate < 0.3 and stats.cache_hits + stats.cache_misses > 100 do
        [
          "Consider increasing cache size - low hit rate (#{Float.round(stats.cache_hit_rate * 100, 1)}%)"
          | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if stats.cache_evictions > stats.cache_hits do
        ["Cache size may be too small - frequent evictions" | suggestions]
      else
        suggestions
      end

    suggestions =
      if not optimizer.performance_metrics.indexing_enabled and stats.patterns_compiled > 5 do
        [
          "Consider enabling pattern indexing for better performance with #{stats.patterns_compiled} patterns"
          | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if not optimizer.performance_metrics.cache_enabled and
           stats.cache_hits + stats.cache_misses > 50 do
        ["Consider enabling result caching for repeated detections" | suggestions]
      else
        suggestions
      end

    if suggestions == [] do
      ["Performance appears optimal - no suggestions at this time"]
    else
      suggestions
    end
  end

  @doc """
  Analyzes pattern performance and provides detailed accuracy tuning suggestions.

  ## Parameters

  - `optimizer` - The optimizer instance
  - `accuracy_results` - Results from pattern accuracy analysis
  - `performance_results` - Results from performance benchmarks

  ## Returns

  Map containing detailed tuning recommendations.

  ## Examples

      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> accuracy = %{accuracy_percentage: 75.0, false_positives: 5, false_negatives: 3}
      iex> performance = %{avg_time_us: 150.0}
      iex> tuning = ClaudeCodeSDK.StepPatternOptimizer.analyze_pattern_tuning(optimizer, accuracy, performance)
      iex> is_map(tuning)
      true

  """
  @spec analyze_pattern_tuning(t(), map(), map()) :: map()
  def analyze_pattern_tuning(%__MODULE__{} = optimizer, accuracy_results, performance_results) do
    accuracy_suggestions = generate_accuracy_suggestions(accuracy_results)
    performance_suggestions = generate_performance_suggestions(performance_results)
    cache_suggestions = get_tuning_suggestions(optimizer)

    pattern_specific_suggestions = analyze_pattern_specific_issues(optimizer, accuracy_results)

    %{
      overall_score: calculate_overall_score(accuracy_results, performance_results),
      accuracy_suggestions: accuracy_suggestions,
      performance_suggestions: performance_suggestions,
      cache_suggestions: cache_suggestions,
      pattern_suggestions: pattern_specific_suggestions,
      recommended_actions:
        prioritize_recommendations(
          accuracy_suggestions,
          performance_suggestions,
          cache_suggestions
        ),
      tuning_metrics: %{
        accuracy_score: accuracy_results[:accuracy_percentage] || 0.0,
        performance_score: calculate_performance_score(performance_results),
        cache_efficiency: get_performance_stats(optimizer).cache_hit_rate * 100
      }
    }
  end

  @doc """
  Optimizes pattern confidence thresholds based on accuracy analysis.

  ## Parameters

  - `optimizer` - The optimizer instance
  - `accuracy_results` - Results from accuracy testing
  - `target_accuracy` - Target accuracy percentage (default: 85.0)

  ## Returns

  Map containing optimized confidence thresholds for each pattern.

  ## Examples

      iex> optimizer = ClaudeCodeSDK.StepPatternOptimizer.new()
      iex> accuracy = %{detailed_results: []}
      iex> thresholds = ClaudeCodeSDK.StepPatternOptimizer.optimize_confidence_thresholds(optimizer, accuracy)
      iex> is_map(thresholds)
      true

  """
  @spec optimize_confidence_thresholds(t(), map(), float()) :: map()
  def optimize_confidence_thresholds(
        %__MODULE__{} = optimizer,
        accuracy_results,
        target_accuracy \\ 85.0
      ) do
    detailed_results = accuracy_results[:detailed_results] || []

    # Group results by pattern
    pattern_results = group_results_by_pattern(detailed_results)

    # Calculate optimal thresholds for each pattern
    optimized_thresholds =
      Enum.reduce(pattern_results, %{}, fn {pattern_id, results}, acc ->
        optimal_threshold = calculate_optimal_threshold(results, target_accuracy)
        Map.put(acc, pattern_id, optimal_threshold)
      end)

    # Include current patterns that weren't tested
    current_patterns = Map.keys(optimizer.compiled_patterns)

    default_thresholds =
      Enum.reduce(current_patterns, %{}, fn pattern_id, acc ->
        if not Map.has_key?(optimized_thresholds, pattern_id) do
          # Default threshold
          Map.put(acc, pattern_id, 0.7)
        else
          acc
        end
      end)

    Map.merge(default_thresholds, optimized_thresholds)
  end

  @doc """
  Creates an advanced pattern index with multiple indexing strategies.

  ## Parameters

  - `patterns` - List of patterns to index
  - `opts` - Indexing options

  ## Returns

  Map containing multiple index types.

  ## Examples

      iex> patterns = StepPattern.default_patterns()
      iex> index = ClaudeCodeSDK.StepPatternOptimizer.create_advanced_index(patterns)
      iex> Map.has_key?(index, :tool_index)
      true

  """
  @spec create_advanced_index([StepPattern.t()], keyword()) :: map()
  def create_advanced_index(patterns, opts \\ []) do
    enable_ngram = Keyword.get(opts, :enable_ngram, true)
    enable_semantic = Keyword.get(opts, :enable_semantic, false)

    base_indexes = build_indexes(patterns)
    {tool_index, content_index} = base_indexes

    advanced_index = %{
      tool_index: tool_index,
      content_index: content_index,
      priority_index: build_priority_index(patterns),
      confidence_index: build_confidence_index(patterns)
    }

    advanced_index =
      if enable_ngram do
        Map.put(advanced_index, :ngram_index, build_ngram_index(patterns))
      else
        advanced_index
      end

    advanced_index =
      if enable_semantic do
        Map.put(advanced_index, :semantic_index, build_semantic_index(patterns))
      else
        advanced_index
      end

    advanced_index
  end

  # Private helper functions

  defp compile_patterns(patterns) do
    Enum.reduce(patterns, %{}, fn pattern, acc ->
      compiled = compile_single_pattern(pattern)
      Map.put(acc, pattern.id, compiled)
    end)
  end

  defp compile_single_pattern(%StepPattern{} = pattern) do
    compiled_triggers = Enum.map(pattern.triggers, &compile_trigger/1)
    compiled_validators = Enum.map(pattern.validators, &compile_validator/1)

    %{
      pattern: pattern,
      triggers: compiled_triggers,
      validators: compiled_validators,
      compiled_at: System.monotonic_time(:millisecond)
    }
  end

  defp compile_trigger(%{type: :message_content, regex: regex} = trigger)
       when not is_nil(regex) do
    compiled_regex =
      if is_struct(regex, Regex) do
        regex
      else
        Regex.compile!(regex)
      end

    %{trigger | regex: compiled_regex}
  end

  defp compile_trigger(%{type: :tool_usage, tools: tools} = trigger) when is_list(tools) do
    # Convert to MapSet for O(1) lookups
    %{trigger | tools: MapSet.new(tools)}
  end

  defp compile_trigger(trigger), do: trigger

  defp compile_validator(%{type: :content_regex, regex: regex} = validator)
       when not is_nil(regex) do
    compiled_regex =
      if is_struct(regex, Regex) do
        regex
      else
        Regex.compile!(regex)
      end

    %{validator | regex: compiled_regex}
  end

  defp compile_validator(validator), do: validator

  defp build_indexes(patterns) do
    tool_index = build_tool_index(patterns)
    content_index = build_content_index(patterns)
    {tool_index, content_index}
  end

  defp build_tool_index(patterns) do
    Enum.reduce(patterns, %{}, fn pattern, acc ->
      tools = extract_tools_from_pattern(pattern)

      Enum.reduce(tools, acc, fn tool, tool_acc ->
        existing = Map.get(tool_acc, tool, [])
        Map.put(tool_acc, tool, [pattern.id | existing])
      end)
    end)
  end

  defp build_content_index(patterns) do
    Enum.reduce(patterns, %{}, fn pattern, acc ->
      content_patterns = extract_content_patterns_from_pattern(pattern)

      Enum.reduce(content_patterns, acc, fn content_pattern, content_acc ->
        existing = Map.get(content_acc, content_pattern, [])
        Map.put(content_acc, content_pattern, [pattern.id | existing])
      end)
    end)
  end

  defp extract_tools_from_pattern(%StepPattern{triggers: triggers}) do
    triggers
    |> Enum.flat_map(fn
      %{type: :tool_usage, tools: tools} when is_list(tools) -> tools
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp extract_content_patterns_from_pattern(%StepPattern{triggers: triggers}) do
    triggers
    |> Enum.flat_map(fn
      %{type: :message_content, regex: regex} when not is_nil(regex) ->
        # Extract simple keywords from regex for indexing
        source = if is_struct(regex, Regex), do: Regex.source(regex), else: regex
        extract_keywords_from_regex(source)

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp extract_keywords_from_regex(regex_source) do
    # Simple keyword extraction - look for literal words
    regex_source
    |> String.replace(~r/[|()[\]{}*+?^$\\]/, " ")
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.map(&String.downcase/1)
  end

  defp update_cache_stats(stats, :hit) do
    %{stats | hits: stats.hits + 1}
  end

  defp update_cache_stats(stats, :miss) do
    %{stats | misses: stats.misses + 1}
  end

  defp evict_oldest_entry(cache, stats) do
    # Simple LRU eviction - remove entry with oldest timestamp
    {oldest_key, _} =
      cache
      |> Enum.min_by(fn {_key, {_result, timestamp}} -> timestamp end)

    updated_cache = Map.delete(cache, oldest_key)
    updated_stats = %{stats | evictions: stats.evictions + 1}

    {updated_cache, updated_stats}
  end

  # Advanced tuning helper functions

  defp generate_accuracy_suggestions(accuracy_results) do
    suggestions = []
    accuracy = accuracy_results[:accuracy_percentage] || 0.0
    false_positives = accuracy_results[:false_positives] || 0
    false_negatives = accuracy_results[:false_negatives] || 0
    total_cases = accuracy_results[:total_cases] || 0

    suggestions =
      if accuracy < 70.0 and total_cases > 10 do
        [
          "Low accuracy (#{Float.round(accuracy, 1)}%) - consider adjusting pattern triggers and validators"
          | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if false_positives > total_cases * 0.2 and total_cases > 0 do
        fp_rate = false_positives / total_cases * 100

        [
          "High false positive rate (#{Float.round(fp_rate, 1)}%) - tighten pattern validators"
          | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if false_negatives > total_cases * 0.2 and total_cases > 0 do
        fn_rate = false_negatives / total_cases * 100

        [
          "High false negative rate (#{Float.round(fn_rate, 1)}%) - broaden pattern triggers"
          | suggestions
        ]
      else
        suggestions
      end

    if suggestions == [] do
      ["Pattern accuracy appears acceptable"]
    else
      suggestions
    end
  end

  defp generate_performance_suggestions(performance_results) do
    suggestions = []
    avg_time = performance_results[:avg_time_us] || 0.0

    suggestions =
      if avg_time > 1000.0 do
        [
          "High detection time (#{Float.round(avg_time, 1)}μs) - consider pattern optimization"
          | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if avg_time > 500.0 do
        [
          "Moderate detection time (#{Float.round(avg_time, 1)}μs) - enable caching for repeated patterns"
          | suggestions
        ]
      else
        suggestions
      end

    if suggestions == [] do
      ["Detection performance appears optimal"]
    else
      suggestions
    end
  end

  defp analyze_pattern_specific_issues(_optimizer, accuracy_results) do
    detailed_results = accuracy_results[:detailed_results] || []
    pattern_stats = group_results_by_pattern(detailed_results)

    Enum.reduce(pattern_stats, %{}, fn {pattern_id, results}, acc ->
      pattern_accuracy = calculate_pattern_accuracy(results)
      issues = identify_pattern_issues(pattern_id, results, pattern_accuracy)

      if issues != [] do
        Map.put(acc, pattern_id, issues)
      else
        acc
      end
    end)
  end

  defp calculate_overall_score(accuracy_results, performance_results) do
    accuracy_score = accuracy_results[:accuracy_percentage] || 0.0
    performance_score = calculate_performance_score(performance_results)

    # Weighted average: 70% accuracy, 30% performance
    (accuracy_score * 0.7 + performance_score * 0.3) |> Float.round(1)
  end

  defp calculate_performance_score(performance_results) do
    avg_time = performance_results[:avg_time_us] || 0.0

    cond do
      avg_time < 100.0 -> 100.0
      avg_time < 250.0 -> 90.0
      avg_time < 500.0 -> 80.0
      avg_time < 1000.0 -> 70.0
      avg_time < 2000.0 -> 60.0
      true -> 50.0
    end
  end

  defp prioritize_recommendations(
         accuracy_suggestions,
         performance_suggestions,
         cache_suggestions
       ) do
    all_suggestions = accuracy_suggestions ++ performance_suggestions ++ cache_suggestions

    # Prioritize by impact and urgency
    prioritized =
      all_suggestions
      |> Enum.map(&{&1, calculate_suggestion_priority(&1)})
      |> Enum.sort_by(fn {_suggestion, priority} -> priority end, :desc)
      |> Enum.map(fn {suggestion, _priority} -> suggestion end)

    # Top 5 recommendations
    Enum.take(prioritized, 5)
  end

  defp calculate_suggestion_priority(suggestion) do
    cond do
      String.contains?(suggestion, "Low accuracy") -> 10
      String.contains?(suggestion, "High false") -> 9
      String.contains?(suggestion, "High detection time") -> 8
      String.contains?(suggestion, "frequent evictions") -> 7
      String.contains?(suggestion, "low hit rate") -> 6
      String.contains?(suggestion, "Moderate detection") -> 5
      true -> 3
    end
  end

  defp group_results_by_pattern(detailed_results) do
    Enum.group_by(detailed_results, fn result ->
      # Extract pattern ID from result metadata
      case result[:result] do
        {:step_start, pattern_id, _} -> pattern_id
        {:step_boundary, pattern_id, _} -> pattern_id
        _ -> :unknown
      end
    end)
  end

  defp calculate_optimal_threshold(results, target_accuracy) do
    if length(results) < 3 do
      # Default threshold for insufficient data
      0.7
    else
      # Simple threshold optimization - find threshold that achieves target accuracy
      thresholds = [0.5, 0.6, 0.7, 0.8, 0.9]

      best_threshold =
        Enum.find(thresholds, 0.7, fn threshold ->
          simulated_accuracy = simulate_accuracy_with_threshold(results, threshold)
          simulated_accuracy >= target_accuracy
        end)

      best_threshold
    end
  end

  defp simulate_accuracy_with_threshold(results, threshold) do
    # Simulate how accuracy would change with different threshold
    # This is a simplified simulation - in practice, you'd need actual confidence scores
    correct_count = Enum.count(results, & &1[:correct])
    total_count = length(results)

    if total_count > 0 do
      base_accuracy = correct_count / total_count * 100

      # Adjust based on threshold (higher threshold generally means higher precision, lower recall)
      # Simple linear adjustment
      adjustment = (threshold - 0.7) * 10
      max(0.0, min(100.0, base_accuracy + adjustment))
    else
      0.0
    end
  end

  defp calculate_pattern_accuracy(results) do
    if length(results) > 0 do
      correct_count = Enum.count(results, & &1[:correct])
      correct_count / length(results) * 100
    else
      0.0
    end
  end

  defp identify_pattern_issues(pattern_id, results, accuracy) do
    issues = []

    issues =
      if accuracy < 60.0 do
        ["Pattern #{pattern_id} has low accuracy (#{Float.round(accuracy, 1)}%)" | issues]
      else
        issues
      end

    false_positives =
      Enum.count(results, fn result ->
        not result[:correct] and result[:actual] == pattern_id
      end)

    false_negatives =
      Enum.count(results, fn result ->
        not result[:correct] and result[:expected] == pattern_id
      end)

    issues =
      if false_positives > length(results) * 0.3 do
        ["Pattern #{pattern_id} has high false positive rate" | issues]
      else
        issues
      end

    issues =
      if false_negatives > length(results) * 0.3 do
        ["Pattern #{pattern_id} has high false negative rate" | issues]
      else
        issues
      end

    issues
  end

  defp build_priority_index(patterns) do
    Enum.reduce(patterns, %{}, fn pattern, acc ->
      priority_group =
        cond do
          pattern.priority >= 90 -> :critical
          pattern.priority >= 70 -> :high
          pattern.priority >= 50 -> :medium
          true -> :low
        end

      existing = Map.get(acc, priority_group, [])
      Map.put(acc, priority_group, [pattern.id | existing])
    end)
  end

  defp build_confidence_index(patterns) do
    Enum.reduce(patterns, %{}, fn pattern, acc ->
      confidence_group =
        cond do
          pattern.confidence >= 0.9 -> :very_high
          pattern.confidence >= 0.8 -> :high
          pattern.confidence >= 0.7 -> :medium
          pattern.confidence >= 0.6 -> :low
          true -> :very_low
        end

      existing = Map.get(acc, confidence_group, [])
      Map.put(acc, confidence_group, [pattern.id | existing])
    end)
  end

  defp build_ngram_index(patterns) do
    # Build n-gram index for content patterns
    Enum.reduce(patterns, %{}, fn pattern, acc ->
      content_patterns = extract_content_patterns_from_pattern(pattern)

      Enum.reduce(content_patterns, acc, fn content_pattern, content_acc ->
        # Bigrams
        ngrams = generate_ngrams(content_pattern, 2)

        Enum.reduce(ngrams, content_acc, fn ngram, ngram_acc ->
          existing = Map.get(ngram_acc, ngram, [])
          Map.put(ngram_acc, ngram, [pattern.id | existing])
        end)
      end)
    end)
  end

  defp build_semantic_index(_patterns) do
    # Placeholder for semantic indexing - would require NLP libraries
    # For now, return empty index
    %{}
  end

  defp generate_ngrams(text, n) do
    words = String.split(text, ~r/\s+/)

    if length(words) >= n do
      words
      |> Enum.chunk_every(n, 1, :discard)
      |> Enum.map(&Enum.join(&1, " "))
    else
      []
    end
  end
end
