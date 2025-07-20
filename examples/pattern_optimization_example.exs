#!/usr/bin/env elixir

# Pattern Optimization and Caching Example
# This example demonstrates the enhanced pattern optimization and caching features
# implemented in task 2.3 of the stream-step-grouping specification.

Mix.install([
  {:claude_code_sdk, path: "."}
])

alias ClaudeCodeSDK.{StepPattern, StepPatternOptimizer, StepDetectionBenchmark}

IO.puts("=== Pattern Optimization and Caching Example ===\n")

# 1. Create and optimize patterns
IO.puts("1. Creating and optimizing patterns...")
patterns = StepPattern.default_patterns()
IO.puts("   - Created #{length(patterns)} default patterns")

optimizer = StepPatternOptimizer.new(
  cache_size: 500,
  enable_caching: true,
  enable_indexing: true,
  performance_tracking: true
)

optimized_optimizer = StepPatternOptimizer.optimize_patterns(optimizer, patterns)
IO.puts("   - Optimized patterns with caching and indexing enabled")

# 2. Show performance statistics
IO.puts("\n2. Performance statistics:")
stats = StepPatternOptimizer.get_performance_stats(optimized_optimizer)
IO.puts("   - Patterns compiled: #{stats.patterns_compiled}")
IO.puts("   - Tool index size: #{stats.tool_index_size}")
IO.puts("   - Content index size: #{stats.content_index_size}")
IO.puts("   - Cache max size: #{stats.cache_max_size}")

# 3. Demonstrate pattern candidates optimization
IO.puts("\n3. Pattern candidate optimization:")
file_tools = ["readFile", "fsWrite"]
candidates = StepPatternOptimizer.get_pattern_candidates(optimized_optimizer, file_tools)
IO.puts("   - Tools: #{inspect(file_tools)}")
IO.puts("   - Pattern candidates: #{inspect(candidates)}")

# 4. Create test messages for caching demonstration
IO.puts("\n4. Demonstrating result caching:")
test_message = %ClaudeCodeSDK.Message{
  type: :assistant,
  subtype: nil,
  data: %{
    message: %{"content" => "<function_calls><invoke name=\"readFile\"></invoke></function_calls>Reading configuration file"},
    session_id: "example-session"
  },
  raw: %{}
}

tools = ["readFile"]
content = "Reading configuration file"
cache_key = StepPatternOptimizer.create_cache_key(test_message, tools, content)

# First access - cache miss
{result1, optimizer_after_miss} = StepPatternOptimizer.get_cached_result(optimized_optimizer, cache_key)
IO.puts("   - First access: #{inspect(result1)}")

# Cache the result
detection_result = {:step_start, :file_operation, %{confidence: 0.95}}
optimizer_with_cache = StepPatternOptimizer.cache_result(optimizer_after_miss, cache_key, detection_result)

# Second access - cache hit
{result2, optimizer_after_hit} = StepPatternOptimizer.get_cached_result(optimizer_with_cache, cache_key)
IO.puts("   - Second access: #{inspect(result2)}")

# Show updated cache statistics
updated_stats = StepPatternOptimizer.get_performance_stats(optimizer_after_hit)
IO.puts("   - Cache hits: #{updated_stats.cache_hits}")
IO.puts("   - Cache misses: #{updated_stats.cache_misses}")
IO.puts("   - Cache hit rate: #{Float.round(updated_stats.cache_hit_rate * 100, 1)}%")

# 5. Run performance benchmarks
IO.puts("\n5. Running performance benchmarks...")
benchmark_results = StepDetectionBenchmark.run_detection_benchmark(iterations: 100)

IO.puts("   Basic detector average time: #{Float.round(benchmark_results.basic_detector.avg_time_us, 2)} μs")
IO.puts("   Optimized detector average time: #{Float.round(benchmark_results.optimized_detector.avg_time_us, 2)} μs")
IO.puts("   Speed improvement: #{Float.round(benchmark_results.performance_improvement.speed_improvement_percent, 1)}%")

# 6. Demonstrate tuning suggestions
IO.puts("\n6. Pattern tuning suggestions:")
suggestions = StepPatternOptimizer.get_tuning_suggestions(optimizer_after_hit)
for suggestion <- suggestions do
  IO.puts("   - #{suggestion}")
end

# 7. Run optimization benchmark
IO.puts("\n7. Running comprehensive optimization benchmark...")
optimization_results = StepDetectionBenchmark.run_optimization_benchmark(iterations: 50)

IO.puts("   Pre-compilation results:")
pre_comp = optimization_results.pre_compilation_results
IO.puts("     - Average compilation time: #{Float.round(pre_comp.avg_compilation_time_us, 2)} μs")
IO.puts("     - Compilations per second: #{Float.round(pre_comp.compilations_per_second, 1)}")

IO.puts("   Indexing strategy results:")
for strategy_result <- optimization_results.indexing_results do
  IO.puts("     - #{strategy_result.strategy}: #{Float.round(strategy_result.avg_time_per_detection_us, 2)} μs avg")
end

IO.puts("   Cache effectiveness results:")
for cache_result <- optimization_results.cache_effectiveness_results do
  IO.puts("     - #{cache_result.config}: #{Float.round(cache_result.effectiveness_score, 1)} effectiveness score")
end

IO.puts("   Overall recommendations:")
for recommendation <- optimization_results.overall_recommendations do
  IO.puts("     - #{recommendation}")
end

# 8. Demonstrate advanced indexing
IO.puts("\n8. Advanced indexing capabilities:")
advanced_index = StepPatternOptimizer.create_advanced_index(patterns, enable_ngram: true)
IO.puts("   - Priority index groups: #{inspect(Map.keys(advanced_index.priority_index))}")
IO.puts("   - Confidence index groups: #{inspect(Map.keys(advanced_index.confidence_index))}")
IO.puts("   - N-gram index size: #{map_size(advanced_index.ngram_index)}")

# 9. Pattern accuracy analysis
IO.puts("\n9. Pattern accuracy analysis:")
test_cases = [
  {%ClaudeCodeSDK.Message{type: :assistant, subtype: nil, data: %{message: %{"content" => "<function_calls><invoke name=\"readFile\"></invoke></function_calls>"}, session_id: "test"}, raw: %{}}, :file_operation},
  {%ClaudeCodeSDK.Message{type: :assistant, subtype: nil, data: %{message: %{"content" => "<function_calls><invoke name=\"strReplace\"></invoke></function_calls>"}, session_id: "test"}, raw: %{}}, :code_modification},
  {%ClaudeCodeSDK.Message{type: :assistant, subtype: nil, data: %{message: %{"content" => "Let me explain how this works"}, session_id: "test"}, raw: %{}}, :communication}
]

accuracy_results = StepDetectionBenchmark.analyze_pattern_accuracy(test_cases)
IO.puts("   - Total test cases: #{accuracy_results.total_cases}")
IO.puts("   - Correct predictions: #{accuracy_results.correct_predictions}")
IO.puts("   - Accuracy: #{Float.round(accuracy_results.accuracy_percentage, 1)}%")
IO.puts("   - False positives: #{accuracy_results.false_positives}")
IO.puts("   - False negatives: #{accuracy_results.false_negatives}")

# 10. Advanced pattern tuning analysis
IO.puts("\n10. Advanced pattern tuning analysis:")
performance_results = %{avg_time_us: benchmark_results.optimized_detector.avg_time_us}
tuning_analysis = StepPatternOptimizer.analyze_pattern_tuning(optimizer_after_hit, accuracy_results, performance_results)

IO.puts("   - Overall score: #{tuning_analysis.overall_score}")
IO.puts("   - Accuracy score: #{tuning_analysis.tuning_metrics.accuracy_score}")
IO.puts("   - Performance score: #{tuning_analysis.tuning_metrics.performance_score}")
IO.puts("   - Cache efficiency: #{Float.round(tuning_analysis.tuning_metrics.cache_efficiency, 1)}%")

IO.puts("   Top recommendations:")
for recommendation <- Enum.take(tuning_analysis.recommended_actions, 3) do
  IO.puts("     - #{recommendation}")
end

IO.puts("\n=== Pattern Optimization and Caching Example Complete ===")