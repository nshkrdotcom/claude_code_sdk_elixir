defmodule ClaudeCodeSDK.StepPatternOptimizerTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{StepPatternOptimizer, StepPattern, Message}

  describe "new/1" do
    test "creates optimizer with default options" do
      optimizer = StepPatternOptimizer.new()

      assert %StepPatternOptimizer{} = optimizer
      assert optimizer.compiled_patterns == %{}
      assert optimizer.tool_index == %{}
      assert optimizer.content_index == %{}
      assert optimizer.result_cache == %{}
      assert optimizer.cache_stats.hits == 0
      assert optimizer.cache_stats.misses == 0
      assert optimizer.cache_stats.max_size == 1000
      assert optimizer.performance_metrics.cache_enabled == true
      assert optimizer.performance_metrics.indexing_enabled == true
    end

    test "creates optimizer with custom options" do
      optimizer =
        StepPatternOptimizer.new(
          cache_size: 500,
          enable_caching: false,
          enable_indexing: false,
          performance_tracking: true
        )

      assert optimizer.cache_stats.max_size == 500
      assert optimizer.performance_metrics.cache_enabled == false
      assert optimizer.performance_metrics.indexing_enabled == false
      assert optimizer.performance_metrics.tracking_enabled == true
    end
  end

  describe "optimize_patterns/2" do
    test "compiles patterns and builds indexes" do
      patterns = StepPattern.default_patterns()
      optimizer = StepPatternOptimizer.new()

      optimized = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

      # Check compiled patterns
      assert map_size(optimized.compiled_patterns) == length(patterns)

      for pattern <- patterns do
        assert Map.has_key?(optimized.compiled_patterns, pattern.id)
        compiled = optimized.compiled_patterns[pattern.id]
        assert Map.has_key?(compiled, :pattern)
        assert Map.has_key?(compiled, :triggers)
        assert Map.has_key?(compiled, :validators)
        assert Map.has_key?(compiled, :compiled_at)
      end

      # Check tool index
      assert map_size(optimized.tool_index) > 0
      assert Map.has_key?(optimized.tool_index, "readFile")
      assert :file_operation in optimized.tool_index["readFile"]

      # Check content index
      assert map_size(optimized.content_index) > 0
    end

    test "tracks performance metrics when enabled" do
      patterns = StepPattern.default_patterns()
      optimizer = StepPatternOptimizer.new(performance_tracking: true)

      optimized = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

      assert Map.has_key?(optimized.performance_metrics, :last_optimization_time_us)
      assert Map.has_key?(optimized.performance_metrics, :patterns_optimized)
      assert Map.has_key?(optimized.performance_metrics, :optimization_count)
      assert optimized.performance_metrics.patterns_optimized == length(patterns)
      assert optimized.performance_metrics.optimization_count == 1
    end

    test "skips indexing when disabled" do
      patterns = StepPattern.default_patterns()
      optimizer = StepPatternOptimizer.new(enable_indexing: false)

      optimized = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

      assert optimized.tool_index == %{}
      assert optimized.content_index == %{}
      assert map_size(optimized.compiled_patterns) == length(patterns)
    end
  end

  describe "caching functionality" do
    setup do
      optimizer = StepPatternOptimizer.new()
      message = create_test_message(["readFile"], "test content")
      cache_key = StepPatternOptimizer.create_cache_key(message, ["readFile"], "test content")
      result = {:step_start, :file_operation, %{confidence: 0.9}}

      {:ok, optimizer: optimizer, cache_key: cache_key, result: result, message: message}
    end

    test "cache miss on empty cache", %{optimizer: optimizer, cache_key: cache_key} do
      {cache_result, updated_optimizer} =
        StepPatternOptimizer.get_cached_result(optimizer, cache_key)

      assert cache_result == :miss
      assert updated_optimizer.cache_stats.misses == 1
      assert updated_optimizer.cache_stats.hits == 0
    end

    test "cache hit after storing result", %{
      optimizer: optimizer,
      cache_key: cache_key,
      result: result
    } do
      # Store result
      optimizer_with_result = StepPatternOptimizer.cache_result(optimizer, cache_key, result)

      # Retrieve result
      {cache_result, updated_optimizer} =
        StepPatternOptimizer.get_cached_result(optimizer_with_result, cache_key)

      assert {:hit, ^result} = cache_result
      assert updated_optimizer.cache_stats.hits == 1
      assert updated_optimizer.cache_stats.misses == 0
    end

    test "cache eviction when full", %{optimizer: _optimizer, result: result} do
      # Create optimizer with small cache
      small_cache_optimizer = StepPatternOptimizer.new(cache_size: 2)

      # Fill cache beyond capacity
      key1 = {:assistant, ["tool1"], "hash1"}
      key2 = {:assistant, ["tool2"], "hash2"}
      key3 = {:assistant, ["tool3"], "hash3"}

      optimizer_with_results =
        small_cache_optimizer
        |> StepPatternOptimizer.cache_result(key1, result)
        |> StepPatternOptimizer.cache_result(key2, result)
        # Should trigger eviction
        |> StepPatternOptimizer.cache_result(key3, result)

      assert optimizer_with_results.cache_stats.evictions == 1
      assert map_size(optimizer_with_results.result_cache) == 2
    end

    test "caching disabled when cache_enabled is false" do
      optimizer = StepPatternOptimizer.new(enable_caching: false)
      cache_key = {:assistant, ["readFile"], "hash"}
      result = {:step_start, :file_operation, %{}}

      # Try to cache result
      optimizer_after_cache = StepPatternOptimizer.cache_result(optimizer, cache_key, result)

      # Should not cache anything
      assert optimizer_after_cache.result_cache == %{}

      # Try to get cached result
      {cache_result, _} = StepPatternOptimizer.get_cached_result(optimizer_after_cache, cache_key)

      assert cache_result == :miss
    end
  end

  describe "create_cache_key/3" do
    test "creates consistent cache keys" do
      message = create_test_message(["readFile"], "test content")
      tools = ["readFile"]
      content = "test content"

      key1 = StepPatternOptimizer.create_cache_key(message, tools, content)
      key2 = StepPatternOptimizer.create_cache_key(message, tools, content)

      assert key1 == key2
    end

    test "creates different keys for different inputs" do
      message1 = create_test_message(["readFile"], "content1")
      message2 = create_test_message(["fsWrite"], "content2")

      key1 = StepPatternOptimizer.create_cache_key(message1, ["readFile"], "content1")
      key2 = StepPatternOptimizer.create_cache_key(message2, ["fsWrite"], "content2")

      assert key1 != key2
    end

    test "sorts tools for consistent keys" do
      message = create_test_message(["readFile", "fsWrite"], "content")

      key1 = StepPatternOptimizer.create_cache_key(message, ["readFile", "fsWrite"], "content")
      key2 = StepPatternOptimizer.create_cache_key(message, ["fsWrite", "readFile"], "content")

      assert key1 == key2
    end
  end

  describe "get_pattern_candidates/2" do
    test "returns pattern candidates based on tools" do
      patterns = StepPattern.default_patterns()
      optimizer = StepPatternOptimizer.new()
      optimized = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

      candidates = StepPatternOptimizer.get_pattern_candidates(optimized, ["readFile"])

      assert :file_operation in candidates
      # readFile might also match analysis pattern
      assert length(candidates) >= 1
    end

    test "returns all patterns when indexing disabled" do
      patterns = StepPattern.default_patterns()
      optimizer = StepPatternOptimizer.new(enable_indexing: false)
      optimized = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

      candidates = StepPatternOptimizer.get_pattern_candidates(optimized, ["readFile"])

      # Should return all pattern IDs
      pattern_ids = Enum.map(patterns, & &1.id)
      assert Enum.sort(candidates) == Enum.sort(pattern_ids)
    end

    test "handles empty tools list" do
      patterns = StepPattern.default_patterns()
      optimizer = StepPatternOptimizer.new()
      optimized = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

      candidates = StepPatternOptimizer.get_pattern_candidates(optimized, [])

      assert candidates == []
    end
  end

  describe "get_performance_stats/1" do
    test "returns comprehensive performance statistics" do
      patterns = StepPattern.default_patterns()
      optimizer = StepPatternOptimizer.new()
      optimized = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

      stats = StepPatternOptimizer.get_performance_stats(optimized)

      assert is_map(stats)
      assert Map.has_key?(stats, :cache_hit_rate)
      assert Map.has_key?(stats, :cache_hits)
      assert Map.has_key?(stats, :cache_misses)
      assert Map.has_key?(stats, :cache_size)
      assert Map.has_key?(stats, :patterns_compiled)
      assert Map.has_key?(stats, :tool_index_size)
      assert Map.has_key?(stats, :content_index_size)

      # No cache activity yet
      assert stats.cache_hit_rate == 0.0
      assert stats.patterns_compiled == length(patterns)
      assert stats.tool_index_size > 0
      assert stats.content_index_size > 0
    end

    test "calculates correct hit rate" do
      optimizer = StepPatternOptimizer.new()
      cache_key = {:assistant, ["readFile"], "hash"}
      result = {:step_start, :file_operation, %{}}

      # Cache a result
      optimizer_with_cache = StepPatternOptimizer.cache_result(optimizer, cache_key, result)

      # Get hit
      {_, optimizer_after_hit} =
        StepPatternOptimizer.get_cached_result(optimizer_with_cache, cache_key)

      # Get miss
      other_key = {:assistant, ["fsWrite"], "other_hash"}

      {_, optimizer_after_miss} =
        StepPatternOptimizer.get_cached_result(optimizer_after_hit, other_key)

      stats = StepPatternOptimizer.get_performance_stats(optimizer_after_miss)

      assert stats.cache_hits == 1
      assert stats.cache_misses == 1
      assert stats.cache_hit_rate == 0.5
    end
  end

  describe "clear_cache/1" do
    test "clears cache and resets stats" do
      optimizer = StepPatternOptimizer.new()
      cache_key = {:assistant, ["readFile"], "hash"}
      result = {:step_start, :file_operation, %{}}

      # Add some cache data
      optimizer_with_cache = StepPatternOptimizer.cache_result(optimizer, cache_key, result)

      {_, optimizer_with_stats} =
        StepPatternOptimizer.get_cached_result(optimizer_with_cache, cache_key)

      # Verify cache has data
      assert map_size(optimizer_with_stats.result_cache) == 1
      assert optimizer_with_stats.cache_stats.hits == 1

      # Clear cache
      cleared_optimizer = StepPatternOptimizer.clear_cache(optimizer_with_stats)

      assert map_size(cleared_optimizer.result_cache) == 0
      assert cleared_optimizer.cache_stats.hits == 0
      assert cleared_optimizer.cache_stats.misses == 0
      assert cleared_optimizer.cache_stats.evictions == 0
    end
  end

  describe "get_tuning_suggestions/1" do
    test "provides suggestions for low hit rate" do
      optimizer = StepPatternOptimizer.new()

      # Simulate low hit rate scenario with enough requests to trigger suggestion
      optimizer_with_low_hit_rate = %{
        optimizer
        | # 11.8% hit rate, >100 total
          cache_stats: %{optimizer.cache_stats | hits: 20, misses: 150}
      }

      suggestions = StepPatternOptimizer.get_tuning_suggestions(optimizer_with_low_hit_rate)

      assert is_list(suggestions)
      assert length(suggestions) > 0

      # Should suggest increasing cache size due to low hit rate
      low_hit_rate_suggestion = Enum.find(suggestions, &String.contains?(&1, "low hit rate"))
      assert low_hit_rate_suggestion != nil
    end

    test "provides suggestions for frequent evictions" do
      optimizer = StepPatternOptimizer.new()

      # Simulate frequent evictions
      optimizer_with_evictions = %{
        optimizer
        | cache_stats: %{optimizer.cache_stats | hits: 10, evictions: 20}
      }

      suggestions = StepPatternOptimizer.get_tuning_suggestions(optimizer_with_evictions)

      eviction_suggestion = Enum.find(suggestions, &String.contains?(&1, "frequent evictions"))
      assert eviction_suggestion != nil
    end

    test "suggests enabling indexing for many patterns" do
      optimizer = StepPatternOptimizer.new(enable_indexing: false)
      patterns = StepPattern.default_patterns()
      optimized = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

      suggestions = StepPatternOptimizer.get_tuning_suggestions(optimized)

      indexing_suggestion = Enum.find(suggestions, &String.contains?(&1, "pattern indexing"))
      assert indexing_suggestion != nil
    end

    test "returns optimal message when no issues found" do
      optimizer = StepPatternOptimizer.new()

      suggestions = StepPatternOptimizer.get_tuning_suggestions(optimizer)

      assert suggestions == ["Performance appears optimal - no suggestions at this time"]
    end
  end

  describe "analyze_pattern_tuning/3" do
    test "provides comprehensive tuning analysis" do
      optimizer = StepPatternOptimizer.new()

      accuracy_results = %{
        accuracy_percentage: 75.0,
        false_positives: 5,
        false_negatives: 3,
        total_cases: 20,
        detailed_results: []
      }

      performance_results = %{avg_time_us: 150.0}

      tuning =
        StepPatternOptimizer.analyze_pattern_tuning(
          optimizer,
          accuracy_results,
          performance_results
        )

      assert is_map(tuning)
      assert Map.has_key?(tuning, :overall_score)
      assert Map.has_key?(tuning, :accuracy_suggestions)
      assert Map.has_key?(tuning, :performance_suggestions)
      assert Map.has_key?(tuning, :cache_suggestions)
      assert Map.has_key?(tuning, :pattern_suggestions)
      assert Map.has_key?(tuning, :recommended_actions)
      assert Map.has_key?(tuning, :tuning_metrics)

      assert is_number(tuning.overall_score)
      assert is_list(tuning.accuracy_suggestions)
      assert is_list(tuning.performance_suggestions)
      assert is_list(tuning.cache_suggestions)
      assert is_map(tuning.pattern_suggestions)
      assert is_list(tuning.recommended_actions)
      assert is_map(tuning.tuning_metrics)
    end

    test "identifies low accuracy issues" do
      optimizer = StepPatternOptimizer.new()

      accuracy_results = %{
        # Low accuracy
        accuracy_percentage: 45.0,
        false_positives: 8,
        false_negatives: 12,
        total_cases: 30,
        detailed_results: []
      }

      performance_results = %{avg_time_us: 100.0}

      tuning =
        StepPatternOptimizer.analyze_pattern_tuning(
          optimizer,
          accuracy_results,
          performance_results
        )

      # Should identify accuracy issues
      accuracy_suggestion =
        Enum.find(tuning.accuracy_suggestions, &String.contains?(&1, "Low accuracy"))

      assert accuracy_suggestion != nil

      # Should have lower overall score
      assert tuning.overall_score < 70.0
    end
  end

  describe "optimize_confidence_thresholds/3" do
    test "optimizes thresholds based on accuracy results" do
      patterns = StepPattern.default_patterns()
      optimizer = StepPatternOptimizer.new()
      optimized = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

      accuracy_results = %{
        detailed_results: [
          %{
            expected: :file_operation,
            actual: :file_operation,
            correct: true,
            result: {:step_start, :file_operation, %{}}
          },
          %{
            expected: :file_operation,
            actual: :analysis,
            correct: false,
            result: {:step_start, :analysis, %{}}
          }
        ]
      }

      thresholds =
        StepPatternOptimizer.optimize_confidence_thresholds(optimized, accuracy_results, 90.0)

      assert is_map(thresholds)
      assert map_size(thresholds) > 0

      # Should include thresholds for all patterns
      for pattern <- patterns do
        assert Map.has_key?(thresholds, pattern.id)
        threshold = thresholds[pattern.id]
        assert is_number(threshold)
        assert threshold >= 0.0 and threshold <= 1.0
      end
    end

    test "uses default threshold for patterns without data" do
      optimizer = StepPatternOptimizer.new()
      accuracy_results = %{detailed_results: []}

      thresholds =
        StepPatternOptimizer.optimize_confidence_thresholds(optimizer, accuracy_results)

      # Should return empty map since no patterns are compiled
      assert thresholds == %{}
    end
  end

  describe "create_advanced_index/2" do
    test "creates comprehensive index with multiple strategies" do
      patterns = StepPattern.default_patterns()

      index = StepPatternOptimizer.create_advanced_index(patterns)

      assert is_map(index)
      assert Map.has_key?(index, :tool_index)
      assert Map.has_key?(index, :content_index)
      assert Map.has_key?(index, :priority_index)
      assert Map.has_key?(index, :confidence_index)
      assert Map.has_key?(index, :ngram_index)

      # Check priority index structure
      priority_index = index.priority_index
      assert is_map(priority_index)

      # Should have priority groups
      priority_groups = [:critical, :high, :medium, :low]

      for group <- priority_groups do
        if Map.has_key?(priority_index, group) do
          assert is_list(priority_index[group])
        end
      end

      # Check confidence index structure
      confidence_index = index.confidence_index
      assert is_map(confidence_index)

      # Should have confidence groups
      confidence_groups = [:very_high, :high, :medium, :low, :very_low]

      for group <- confidence_groups do
        if Map.has_key?(confidence_index, group) do
          assert is_list(confidence_index[group])
        end
      end
    end

    test "respects indexing options" do
      patterns = StepPattern.default_patterns()

      # Disable n-gram indexing
      index = StepPatternOptimizer.create_advanced_index(patterns, enable_ngram: false)

      refute Map.has_key?(index, :ngram_index)
      # Disabled by default
      refute Map.has_key?(index, :semantic_index)

      # Enable semantic indexing (placeholder)
      index_with_semantic =
        StepPatternOptimizer.create_advanced_index(patterns, enable_semantic: true)

      assert Map.has_key?(index_with_semantic, :semantic_index)
      # Placeholder implementation
      assert index_with_semantic.semantic_index == %{}
    end
  end

  # Helper functions
  defp create_test_message(tools, content) do
    tool_calls =
      Enum.map(tools, fn tool ->
        "<invoke name=\"#{tool}\"></invoke>"
      end)
      |> Enum.join("")

    full_content = "<function_calls>#{tool_calls}</function_calls> #{content}"

    %Message{
      type: :assistant,
      data: %{
        message: %{"content" => full_content},
        session_id: "test-session"
      }
    }
  end
end
