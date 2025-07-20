#!/usr/bin/env elixir

# Simple Pattern Optimization Demo
# This demonstrates the key optimization features without complex message creation

Mix.install([
  {:claude_code_sdk, path: "."}
])

alias ClaudeCodeSDK.{StepPattern, StepPatternOptimizer, StepDetectionBenchmark}

IO.puts("=== Pattern Optimization and Caching Demo ===\n")

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

# 4. Demonstrate caching with simple cache key
IO.puts("\n4. Demonstrating result caching:")
cache_key = {:assistant, ["readFile"], "hash123"}

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

# 9. Cache performance benchmark
IO.puts("\n9. Cache performance analysis:")
cache_results = StepDetectionBenchmark.benchmark_caching_strategies(
  cache_sizes: [50, 200, 500],
  iterations: 100
)

IO.puts("   Optimal cache size: #{cache_results.optimal_cache_size}")
IO.puts("   Cache recommendations:")
for recommendation <- cache_results.recommendations do
  IO.puts("     - #{recommendation}")
end

# 10. Stress test
IO.puts("\n10. Stress test results:")
stress_results = StepDetectionBenchmark.run_stress_tests(
  concurrent_processes: 3,
  messages_per_process: 20
)

IO.puts("   - Stability score: #{stress_results.stability_score}")
IO.puts("   - Throughput: #{Float.round(stress_results.concurrent_detection_results.throughput_messages_per_second, 1)} msg/s")
IO.puts("   - Concurrency efficiency: #{Float.round(stress_results.concurrent_detection_results.concurrency_efficiency, 1)}%")

IO.puts("   Stress test recommendations:")
for recommendation <- stress_results.recommendations do
  IO.puts("     - #{recommendation}")
end

IO.puts("\n=== Pattern Optimization and Caching Demo Complete ===")