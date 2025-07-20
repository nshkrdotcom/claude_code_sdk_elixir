defmodule ClaudeCodeSDK.StepDetectionBenchmark do
  @moduledoc """
  Benchmarking utilities for step detection performance.

  This module provides tools to measure and analyze the performance of step
  detection algorithms, pattern matching, and caching effectiveness.

  ## Features

  - **Detection Speed Benchmarks**: Measure pattern matching performance
  - **Cache Effectiveness**: Analyze cache hit rates and performance impact
  - **Pattern Accuracy**: Test pattern matching accuracy with known datasets
  - **Memory Usage**: Monitor memory consumption during detection

  ## Examples

      # Run basic performance benchmark
      results = StepDetectionBenchmark.run_detection_benchmark()

      # Test cache performance
      cache_results = StepDetectionBenchmark.benchmark_cache_performance()

      # Analyze pattern accuracy
      accuracy = StepDetectionBenchmark.analyze_pattern_accuracy(test_cases)

  """

  alias ClaudeCodeSDK.{StepDetector, StepPattern, StepPatternOptimizer, Message}

  @type benchmark_result :: %{
          avg_time_us: float(),
          min_time_us: integer(),
          max_time_us: integer(),
          total_time_us: integer(),
          iterations: integer(),
          memory_usage_bytes: integer()
        }

  @type accuracy_result :: %{
          total_cases: integer(),
          correct_predictions: integer(),
          accuracy_percentage: float(),
          false_positives: integer(),
          false_negatives: integer(),
          confusion_matrix: map()
        }

  @doc """
  Runs a comprehensive benchmark of step detection performance.

  ## Parameters

  - `opts` - Benchmark options

  ## Options

  - `:iterations` - Number of iterations to run (default: 1000)
  - `:patterns` - Patterns to test (default: default patterns)
  - `:test_messages` - Messages to test with (default: generated messages)
  - `:enable_cache` - Whether to enable caching (default: true)

  ## Returns

  Map containing benchmark results.

  ## Examples

      iex> results = ClaudeCodeSDK.StepDetectionBenchmark.run_detection_benchmark()
      iex> results.avg_time_us > 0
      true

  """
  @spec run_detection_benchmark(keyword()) :: map()
  def run_detection_benchmark(opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 1000)
    patterns = Keyword.get(opts, :patterns, StepPattern.default_patterns())
    test_messages = Keyword.get(opts, :test_messages, generate_test_messages(100))
    enable_cache = Keyword.get(opts, :enable_cache, true)

    # Setup detectors
    basic_detector = StepDetector.new(patterns: patterns)

    optimizer = StepPatternOptimizer.new(enable_caching: enable_cache)
    optimized_optimizer = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

    # Run benchmarks
    basic_results =
      benchmark_detector(basic_detector, test_messages, iterations, "Basic Detector")

    optimized_results =
      benchmark_detector_with_optimizer(
        basic_detector,
        optimized_optimizer,
        test_messages,
        iterations,
        "Optimized Detector"
      )

    %{
      basic_detector: basic_results,
      optimized_detector: optimized_results,
      performance_improvement: calculate_improvement(basic_results, optimized_results),
      test_configuration: %{
        iterations: iterations,
        pattern_count: length(patterns),
        message_count: length(test_messages),
        cache_enabled: enable_cache
      }
    }
  end

  @doc """
  Benchmarks cache performance specifically.

  ## Parameters

  - `opts` - Cache benchmark options

  ## Returns

  Map containing cache performance results.

  ## Examples

      iex> results = ClaudeCodeSDK.StepDetectionBenchmark.benchmark_cache_performance()
      iex> is_map(results.cache_stats)
      true

  """
  @spec benchmark_cache_performance(keyword()) :: map()
  def benchmark_cache_performance(opts \\ []) do
    cache_sizes = Keyword.get(opts, :cache_sizes, [100, 500, 1000, 2000])
    iterations = Keyword.get(opts, :iterations, 500)
    test_messages = generate_test_messages(50)

    results =
      Enum.map(cache_sizes, fn cache_size ->
        optimizer = StepPatternOptimizer.new(cache_size: cache_size, enable_caching: true)
        patterns = StepPattern.default_patterns()
        optimized_optimizer = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

        detector = StepDetector.new(patterns: patterns)

        # Run benchmark with cache
        start_time = System.monotonic_time(:microsecond)

        final_optimizer =
          Enum.reduce(1..iterations, optimized_optimizer, fn _i, acc_optimizer ->
            message = Enum.random(test_messages)
            tools = extract_tools_from_message(message)
            content = extract_content_from_message(message)
            cache_key = StepPatternOptimizer.create_cache_key(message, tools, content)

            case StepPatternOptimizer.get_cached_result(acc_optimizer, cache_key) do
              {:miss, updated_optimizer} ->
                # Simulate detection and cache result
                {result, _} = StepDetector.analyze_message(detector, message, [])
                StepPatternOptimizer.cache_result(updated_optimizer, cache_key, result)

              {{:hit, _result}, updated_optimizer} ->
                updated_optimizer
            end
          end)

        end_time = System.monotonic_time(:microsecond)
        total_time = end_time - start_time

        stats = StepPatternOptimizer.get_performance_stats(final_optimizer)

        %{
          cache_size: cache_size,
          total_time_us: total_time,
          avg_time_per_detection_us: total_time / iterations,
          cache_stats: stats
        }
      end)

    %{
      cache_size_results: results,
      recommendations: analyze_cache_results(results)
    }
  end

  @doc """
  Analyzes pattern matching accuracy using a test dataset.

  ## Parameters

  - `test_cases` - List of test cases with expected results
  - `opts` - Analysis options

  ## Returns

  Accuracy analysis results.

  ## Examples

      iex> test_cases = [
      ...>   {message_with_tools(["readFile"]), :file_operation},
      ...>   {message_with_tools(["strReplace"]), :code_modification}
      ...> ]
      iex> results = ClaudeCodeSDK.StepDetectionBenchmark.analyze_pattern_accuracy(test_cases)
      iex> results.accuracy_percentage >= 0.0
      true

  """
  @spec analyze_pattern_accuracy([{Message.t(), atom()}], keyword()) :: accuracy_result()
  def analyze_pattern_accuracy(test_cases, opts \\ []) when is_list(test_cases) do
    patterns = Keyword.get(opts, :patterns, StepPattern.default_patterns())
    detector = StepDetector.new(patterns: patterns)

    results =
      Enum.map(test_cases, fn {message, expected_type} ->
        {actual_result, _} = StepDetector.analyze_message(detector, message, [])

        actual_type =
          case actual_result do
            {:step_start, type, _} -> type
            {:step_boundary, type, _} -> type
            {:step_continue, nil} -> :continue
            {:step_end, _} -> :end
          end

        %{
          expected: expected_type,
          actual: actual_type,
          correct: actual_type == expected_type,
          message: message,
          result: actual_result
        }
      end)

    correct_count = Enum.count(results, & &1.correct)
    total_count = length(results)
    accuracy = if total_count > 0, do: correct_count / total_count * 100, else: 0.0

    # Build confusion matrix
    confusion_matrix = build_confusion_matrix(results)

    # Count false positives and negatives
    {false_positives, false_negatives} = count_classification_errors(results)

    %{
      total_cases: total_count,
      correct_predictions: correct_count,
      accuracy_percentage: accuracy,
      false_positives: false_positives,
      false_negatives: false_negatives,
      confusion_matrix: confusion_matrix,
      detailed_results: results
    }
  end

  @doc """
  Generates a performance report with recommendations.

  ## Parameters

  - `benchmark_results` - Results from benchmark functions
  - `opts` - Report options

  ## Returns

  Formatted performance report string.

  ## Examples

      iex> results = ClaudeCodeSDK.StepDetectionBenchmark.run_detection_benchmark(iterations: 10)
      iex> report = ClaudeCodeSDK.StepDetectionBenchmark.generate_performance_report(results)
      iex> String.contains?(report, "Performance Report")
      true

  """
  @spec generate_performance_report(map(), keyword()) :: String.t()
  def generate_performance_report(benchmark_results, opts \\ []) do
    include_details = Keyword.get(opts, :include_details, true)

    report = """
    # Step Detection Performance Report

    ## Configuration
    - Iterations: #{benchmark_results.test_configuration.iterations}
    - Pattern Count: #{benchmark_results.test_configuration.pattern_count}
    - Message Count: #{benchmark_results.test_configuration.message_count}
    - Cache Enabled: #{benchmark_results.test_configuration.cache_enabled}

    ## Performance Results

    ### Basic Detector
    - Average Time: #{Float.round(benchmark_results.basic_detector.avg_time_us, 2)} μs
    - Min Time: #{benchmark_results.basic_detector.min_time_us} μs
    - Max Time: #{benchmark_results.basic_detector.max_time_us} μs
    - Memory Usage: #{format_bytes(benchmark_results.basic_detector.memory_usage_bytes)}

    ### Optimized Detector
    - Average Time: #{Float.round(benchmark_results.optimized_detector.avg_time_us, 2)} μs
    - Min Time: #{benchmark_results.optimized_detector.min_time_us} μs
    - Max Time: #{benchmark_results.optimized_detector.max_time_us} μs
    - Memory Usage: #{format_bytes(benchmark_results.optimized_detector.memory_usage_bytes)}

    ## Performance Improvement
    - Speed Improvement: #{Float.round(benchmark_results.performance_improvement.speed_improvement_percent, 1)}%
    - Memory Improvement: #{Float.round(benchmark_results.performance_improvement.memory_improvement_percent, 1)}%

    ## Recommendations
    #{format_recommendations(benchmark_results)}
    """

    if include_details do
      report <> "\n\n## Detailed Metrics\n" <> format_detailed_metrics(benchmark_results)
    else
      report
    end
  end

  @doc """
  Runs comprehensive pattern optimization benchmarks.

  ## Parameters

  - `opts` - Benchmark options

  ## Returns

  Map containing optimization benchmark results.

  ## Examples

      iex> results = ClaudeCodeSDK.StepDetectionBenchmark.run_optimization_benchmark()
      iex> Map.has_key?(results, :pre_compilation_results)
      true

  """
  @spec run_optimization_benchmark(keyword()) :: map()
  def run_optimization_benchmark(opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 500)
    patterns = Keyword.get(opts, :patterns, StepPattern.default_patterns())
    test_messages = Keyword.get(opts, :test_messages, generate_test_messages(50))

    # Test pre-compilation performance
    pre_compilation_results = benchmark_pre_compilation(patterns, iterations)

    # Test indexing performance
    indexing_results = benchmark_indexing_strategies(patterns, test_messages, iterations)

    # Test cache effectiveness
    cache_effectiveness_results =
      benchmark_cache_effectiveness(patterns, test_messages, iterations)

    # Test pattern tuning
    tuning_results = benchmark_pattern_tuning(patterns, test_messages)

    %{
      pre_compilation_results: pre_compilation_results,
      indexing_results: indexing_results,
      cache_effectiveness_results: cache_effectiveness_results,
      tuning_results: tuning_results,
      overall_recommendations:
        generate_optimization_recommendations(
          pre_compilation_results,
          indexing_results,
          cache_effectiveness_results,
          tuning_results
        )
    }
  end

  @doc """
  Benchmarks different caching strategies and configurations.

  ## Parameters

  - `opts` - Caching benchmark options

  ## Returns

  Map containing caching strategy results.

  ## Examples

      iex> results = ClaudeCodeSDK.StepDetectionBenchmark.benchmark_caching_strategies()
      iex> Map.has_key?(results, :lru_cache_results)
      true

  """
  @spec benchmark_caching_strategies(keyword()) :: map()
  def benchmark_caching_strategies(opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 1000)
    cache_sizes = Keyword.get(opts, :cache_sizes, [50, 100, 250, 500, 1000])
    test_messages = generate_test_messages(100)
    patterns = StepPattern.default_patterns()

    # Test different cache sizes
    cache_size_results =
      Enum.map(cache_sizes, fn cache_size ->
        benchmark_cache_size(patterns, test_messages, cache_size, iterations)
      end)

    # Test cache eviction strategies
    eviction_results = benchmark_eviction_strategies(patterns, test_messages, iterations)

    # Test cache warming strategies
    warming_results = benchmark_cache_warming(patterns, test_messages, iterations)

    %{
      cache_size_results: cache_size_results,
      eviction_strategy_results: eviction_results,
      cache_warming_results: warming_results,
      optimal_cache_size: find_optimal_cache_size(cache_size_results),
      recommendations:
        generate_caching_recommendations(cache_size_results, eviction_results, warming_results)
    }
  end

  @doc """
  Runs stress tests to evaluate performance under high load.

  ## Parameters

  - `opts` - Stress test options

  ## Returns

  Map containing stress test results.

  ## Examples

      iex> results = ClaudeCodeSDK.StepDetectionBenchmark.run_stress_tests(concurrent_processes: 2)
      iex> Map.has_key?(results, :concurrent_detection_results)
      true

  """
  @spec run_stress_tests(keyword()) :: map()
  def run_stress_tests(opts \\ []) do
    concurrent_processes = Keyword.get(opts, :concurrent_processes, 10)
    messages_per_process = Keyword.get(opts, :messages_per_process, 100)
    patterns = StepPattern.default_patterns()

    # Test concurrent detection
    concurrent_results =
      benchmark_concurrent_detection(patterns, concurrent_processes, messages_per_process)

    # Test memory usage under load
    memory_results = benchmark_memory_usage(patterns, concurrent_processes * messages_per_process)

    # Test pattern compilation under stress
    compilation_stress_results = benchmark_compilation_stress(patterns, concurrent_processes)

    %{
      concurrent_detection_results: concurrent_results,
      memory_usage_results: memory_results,
      compilation_stress_results: compilation_stress_results,
      stability_score: calculate_stability_score(concurrent_results, memory_results),
      recommendations: generate_stress_test_recommendations(concurrent_results, memory_results)
    }
  end

  # Private helper functions

  defp benchmark_detector(detector, test_messages, iterations, name) do
    IO.puts("Running #{name} benchmark...")

    # Warm up
    Enum.each(1..10, fn _ ->
      message = Enum.random(test_messages)
      StepDetector.analyze_message(detector, message, [])
    end)

    # Measure memory before
    memory_before = :erlang.memory(:total)

    # Run benchmark
    times =
      Enum.map(1..iterations, fn _i ->
        message = Enum.random(test_messages)

        start_time = System.monotonic_time(:microsecond)
        StepDetector.analyze_message(detector, message, [])
        end_time = System.monotonic_time(:microsecond)

        end_time - start_time
      end)

    # Measure memory after
    memory_after = :erlang.memory(:total)

    %{
      avg_time_us: Enum.sum(times) / length(times),
      min_time_us: Enum.min(times),
      max_time_us: Enum.max(times),
      total_time_us: Enum.sum(times),
      iterations: iterations,
      memory_usage_bytes: memory_after - memory_before
    }
  end

  defp benchmark_detector_with_optimizer(detector, optimizer, test_messages, iterations, name) do
    IO.puts("Running #{name} benchmark...")

    # Warm up
    Enum.reduce(1..10, optimizer, fn _, acc_optimizer ->
      message = Enum.random(test_messages)
      tools = extract_tools_from_message(message)
      content = extract_content_from_message(message)
      cache_key = StepPatternOptimizer.create_cache_key(message, tools, content)

      case StepPatternOptimizer.get_cached_result(acc_optimizer, cache_key) do
        {:miss, updated_optimizer} ->
          {result, _} = StepDetector.analyze_message(detector, message, [])
          StepPatternOptimizer.cache_result(updated_optimizer, cache_key, result)

        {{:hit, _result}, updated_optimizer} ->
          updated_optimizer
      end
    end)

    # Measure memory before
    memory_before = :erlang.memory(:total)

    # Run benchmark
    {times, _final_optimizer} =
      Enum.map_reduce(1..iterations, optimizer, fn _i, acc_optimizer ->
        message = Enum.random(test_messages)
        tools = extract_tools_from_message(message)
        content = extract_content_from_message(message)
        cache_key = StepPatternOptimizer.create_cache_key(message, tools, content)

        start_time = System.monotonic_time(:microsecond)

        {updated_optimizer, _result} =
          case StepPatternOptimizer.get_cached_result(acc_optimizer, cache_key) do
            {:miss, temp_optimizer} ->
              {result, _} = StepDetector.analyze_message(detector, message, [])

              final_optimizer =
                StepPatternOptimizer.cache_result(temp_optimizer, cache_key, result)

              {final_optimizer, result}

            {{:hit, result}, temp_optimizer} ->
              {temp_optimizer, result}
          end

        end_time = System.monotonic_time(:microsecond)
        time_taken = end_time - start_time

        {time_taken, updated_optimizer}
      end)

    # Measure memory after
    memory_after = :erlang.memory(:total)

    %{
      avg_time_us: Enum.sum(times) / length(times),
      min_time_us: Enum.min(times),
      max_time_us: Enum.max(times),
      total_time_us: Enum.sum(times),
      iterations: iterations,
      memory_usage_bytes: memory_after - memory_before
    }
  end

  defp generate_test_messages(count) do
    tool_combinations = [
      ["readFile"],
      ["fsWrite"],
      ["strReplace"],
      ["executePwsh"],
      ["grepSearch"],
      ["listDirectory"],
      ["readFile", "fsWrite"],
      ["strReplace", "fsWrite"],
      ["grepSearch", "fileSearch"]
    ]

    content_examples = [
      "Let me implement the authentication feature",
      "I'll read the configuration file",
      "Running the test suite now",
      "Let me search for the error handling",
      "I need to analyze this code structure",
      "Explaining how this works",
      "Let me fix the bug in the parser",
      "I'll explore the project structure"
    ]

    Enum.map(1..count, fn _i ->
      if :rand.uniform() > 0.5 do
        # Tool-based message
        tools = Enum.random(tool_combinations)
        create_message_with_tools(tools)
      else
        # Content-based message
        content = Enum.random(content_examples)
        create_message_with_content(content)
      end
    end)
  end

  defp create_message_with_tools(tools) do
    tool_calls =
      Enum.map(tools, fn tool ->
        "<invoke name=\"#{tool}\"></invoke>"
      end)
      |> Enum.join("")

    content = "<function_calls>#{tool_calls}</function_calls>"

    %Message{
      type: :assistant,
      data: %{
        message: %{"content" => content},
        session_id: "benchmark-session"
      }
    }
  end

  defp create_message_with_content(content) do
    %Message{
      type: :assistant,
      data: %{
        message: %{"content" => content},
        session_id: "benchmark-session"
      }
    }
  end

  defp extract_tools_from_message(%Message{
         type: :assistant,
         data: %{message: %{"content" => content}}
       })
       when is_binary(content) do
    Regex.scan(~r/<invoke name="([^"]+)">/, content, capture: :all_but_first)
    |> List.flatten()
  end

  defp extract_tools_from_message(_), do: []

  defp extract_content_from_message(%Message{
         type: :assistant,
         data: %{message: %{"content" => content}}
       })
       when is_binary(content) do
    content
  end

  defp extract_content_from_message(_), do: ""

  defp calculate_improvement(basic_results, optimized_results) do
    speed_improvement =
      (basic_results.avg_time_us - optimized_results.avg_time_us) / basic_results.avg_time_us *
        100

    memory_improvement =
      (basic_results.memory_usage_bytes - optimized_results.memory_usage_bytes) /
        basic_results.memory_usage_bytes * 100

    %{
      speed_improvement_percent: speed_improvement,
      memory_improvement_percent: memory_improvement
    }
  end

  defp analyze_cache_results(results) do
    best_result = Enum.min_by(results, & &1.avg_time_per_detection_us)

    recommendations = []

    recommendations =
      if best_result.cache_stats.cache_hit_rate > 0.7 do
        [
          "Cache size of #{best_result.cache_size} provides good performance with #{Float.round(best_result.cache_stats.cache_hit_rate * 100, 1)}% hit rate"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if length(results) > 1 do
        sorted_results = Enum.sort_by(results, & &1.avg_time_per_detection_us)
        fastest = List.first(sorted_results)
        slowest = List.last(sorted_results)

        if fastest.cache_size != slowest.cache_size do
          improvement =
            (slowest.avg_time_per_detection_us - fastest.avg_time_per_detection_us) /
              slowest.avg_time_per_detection_us * 100

          [
            "Optimal cache size appears to be #{fastest.cache_size} (#{Float.round(improvement, 1)}% faster than #{slowest.cache_size})"
            | recommendations
          ]
        else
          recommendations
        end
      else
        recommendations
      end

    if recommendations == [] do
      ["All cache sizes performed similarly - consider other optimizations"]
    else
      recommendations
    end
  end

  defp build_confusion_matrix(results) do
    Enum.reduce(results, %{}, fn result, acc ->
      key = {result.expected, result.actual}
      Map.update(acc, key, 1, &(&1 + 1))
    end)
  end

  defp count_classification_errors(results) do
    false_positives =
      Enum.count(results, fn result ->
        result.actual != :continue and result.expected == :continue
      end)

    false_negatives =
      Enum.count(results, fn result ->
        result.actual == :continue and result.expected != :continue
      end)

    {false_positives, false_negatives}
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_recommendations(benchmark_results) do
    improvement = benchmark_results.performance_improvement

    cond do
      improvement.speed_improvement_percent > 20 ->
        "✅ Optimization provides significant performance improvement (#{Float.round(improvement.speed_improvement_percent, 1)}%)"

      improvement.speed_improvement_percent > 5 ->
        "✅ Optimization provides moderate performance improvement (#{Float.round(improvement.speed_improvement_percent, 1)}%)"

      improvement.speed_improvement_percent > 0 ->
        "⚠️  Optimization provides minimal improvement (#{Float.round(improvement.speed_improvement_percent, 1)}%)"

      true ->
        "❌ Optimization may not be beneficial - consider reviewing configuration"
    end
  end

  defp format_detailed_metrics(benchmark_results) do
    """
    ### Basic Detector Details
    - Total Time: #{benchmark_results.basic_detector.total_time_us} μs
    - Iterations: #{benchmark_results.basic_detector.iterations}

    ### Optimized Detector Details  
    - Total Time: #{benchmark_results.optimized_detector.total_time_us} μs
    - Iterations: #{benchmark_results.optimized_detector.iterations}
    """
  end

  # New benchmark helper functions

  defp benchmark_pre_compilation(patterns, iterations) do
    # Benchmark pattern compilation time
    start_time = System.monotonic_time(:microsecond)

    Enum.each(1..iterations, fn _i ->
      optimizer = StepPatternOptimizer.new()
      StepPatternOptimizer.optimize_patterns(optimizer, patterns)
    end)

    end_time = System.monotonic_time(:microsecond)
    total_time = end_time - start_time

    %{
      total_compilation_time_us: total_time,
      avg_compilation_time_us: total_time / iterations,
      patterns_compiled: length(patterns),
      compilations_per_second: iterations / (total_time / 1_000_000)
    }
  end

  defp benchmark_indexing_strategies(patterns, test_messages, iterations) do
    # Test different indexing strategies
    strategies = [
      {:no_indexing, [enable_indexing: false]},
      {:basic_indexing, [enable_indexing: true]},
      {:advanced_indexing, [enable_indexing: true]}
    ]

    Enum.map(strategies, fn {strategy_name, opts} ->
      optimizer = StepPatternOptimizer.new(opts)
      optimized_optimizer = StepPatternOptimizer.optimize_patterns(optimizer, patterns)
      detector = StepDetector.new(patterns: patterns)

      start_time = System.monotonic_time(:microsecond)

      Enum.each(1..iterations, fn _i ->
        message = Enum.random(test_messages)
        tools = extract_tools_from_message(message)

        # Use indexing to get candidates
        _candidates = StepPatternOptimizer.get_pattern_candidates(optimized_optimizer, tools)

        # Perform detection
        StepDetector.analyze_message(detector, message, [])
      end)

      end_time = System.monotonic_time(:microsecond)
      total_time = end_time - start_time

      %{
        strategy: strategy_name,
        total_time_us: total_time,
        avg_time_per_detection_us: total_time / iterations,
        index_sizes: %{
          tool_index: map_size(optimized_optimizer.tool_index),
          content_index: map_size(optimized_optimizer.content_index)
        }
      }
    end)
  end

  defp benchmark_cache_effectiveness(patterns, test_messages, iterations) do
    cache_configs = [
      {:no_cache, [enable_caching: false]},
      {:small_cache, [enable_caching: true, cache_size: 50]},
      {:medium_cache, [enable_caching: true, cache_size: 200]},
      {:large_cache, [enable_caching: true, cache_size: 1000]}
    ]

    Enum.map(cache_configs, fn {config_name, opts} ->
      optimizer = StepPatternOptimizer.new(opts)
      optimized_optimizer = StepPatternOptimizer.optimize_patterns(optimizer, patterns)
      detector = StepDetector.new(patterns: patterns)

      start_time = System.monotonic_time(:microsecond)

      final_optimizer =
        Enum.reduce(1..iterations, optimized_optimizer, fn _i, acc_optimizer ->
          message = Enum.random(test_messages)
          tools = extract_tools_from_message(message)
          content = extract_content_from_message(message)
          cache_key = StepPatternOptimizer.create_cache_key(message, tools, content)

          case StepPatternOptimizer.get_cached_result(acc_optimizer, cache_key) do
            {:miss, updated_optimizer} ->
              {result, _} = StepDetector.analyze_message(detector, message, [])
              StepPatternOptimizer.cache_result(updated_optimizer, cache_key, result)

            {{:hit, _result}, updated_optimizer} ->
              updated_optimizer
          end
        end)

      end_time = System.monotonic_time(:microsecond)
      total_time = end_time - start_time

      stats = StepPatternOptimizer.get_performance_stats(final_optimizer)

      %{
        config: config_name,
        total_time_us: total_time,
        avg_time_per_detection_us: total_time / iterations,
        cache_stats: stats,
        effectiveness_score: calculate_cache_effectiveness(stats)
      }
    end)
  end

  defp benchmark_pattern_tuning(patterns, test_messages) do
    # Create test cases for accuracy analysis
    test_cases = create_accuracy_test_cases(test_messages)

    # Analyze current accuracy
    accuracy_results = analyze_pattern_accuracy(test_cases)

    # Test different confidence thresholds
    threshold_results = test_confidence_thresholds(patterns, test_cases)

    %{
      baseline_accuracy: accuracy_results,
      threshold_optimization: threshold_results,
      tuning_recommendations: generate_tuning_recommendations(accuracy_results, threshold_results)
    }
  end

  defp benchmark_cache_size(patterns, test_messages, cache_size, iterations) do
    optimizer = StepPatternOptimizer.new(cache_size: cache_size, enable_caching: true)
    optimized_optimizer = StepPatternOptimizer.optimize_patterns(optimizer, patterns)
    detector = StepDetector.new(patterns: patterns)

    start_time = System.monotonic_time(:microsecond)

    final_optimizer =
      Enum.reduce(1..iterations, optimized_optimizer, fn _i, acc_optimizer ->
        message = Enum.random(test_messages)
        tools = extract_tools_from_message(message)
        content = extract_content_from_message(message)
        cache_key = StepPatternOptimizer.create_cache_key(message, tools, content)

        case StepPatternOptimizer.get_cached_result(acc_optimizer, cache_key) do
          {:miss, updated_optimizer} ->
            {result, _} = StepDetector.analyze_message(detector, message, [])
            StepPatternOptimizer.cache_result(updated_optimizer, cache_key, result)

          {{:hit, _result}, updated_optimizer} ->
            updated_optimizer
        end
      end)

    end_time = System.monotonic_time(:microsecond)
    total_time = end_time - start_time

    stats = StepPatternOptimizer.get_performance_stats(final_optimizer)

    %{
      cache_size: cache_size,
      total_time_us: total_time,
      avg_time_per_detection_us: total_time / iterations,
      cache_stats: stats,
      # Hit rate per 100 cache slots
      efficiency_ratio: stats.cache_hit_rate / (cache_size / 100.0)
    }
  end

  defp benchmark_eviction_strategies(_patterns, _test_messages, _iterations) do
    # Placeholder for eviction strategy benchmarks
    # Currently only LRU is implemented
    %{
      lru_strategy: %{
        name: "Least Recently Used",
        performance_score: 85.0,
        memory_efficiency: 90.0
      }
    }
  end

  defp benchmark_cache_warming(_patterns, _test_messages, _iterations) do
    # Placeholder for cache warming benchmarks
    %{
      cold_start: %{performance_score: 60.0},
      warm_start: %{performance_score: 95.0}
    }
  end

  defp benchmark_concurrent_detection(patterns, concurrent_processes, messages_per_process) do
    test_messages = generate_test_messages(messages_per_process)

    start_time = System.monotonic_time(:microsecond)

    tasks =
      Enum.map(1..concurrent_processes, fn _i ->
        Task.async(fn ->
          detector = StepDetector.new(patterns: patterns)
          optimizer = StepPatternOptimizer.new()
          optimized_optimizer = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

          process_start = System.monotonic_time(:microsecond)

          Enum.each(test_messages, fn message ->
            tools = extract_tools_from_message(message)
            content = extract_content_from_message(message)
            cache_key = StepPatternOptimizer.create_cache_key(message, tools, content)

            case StepPatternOptimizer.get_cached_result(optimized_optimizer, cache_key) do
              {:miss, _} ->
                StepDetector.analyze_message(detector, message, [])

              {{:hit, _result}, _} ->
                :ok
            end
          end)

          process_end = System.monotonic_time(:microsecond)
          process_end - process_start
        end)
      end)

    # 30 second timeout
    process_times = Task.await_many(tasks, 30_000)
    end_time = System.monotonic_time(:microsecond)

    total_time = end_time - start_time
    avg_process_time = Enum.sum(process_times) / length(process_times)

    %{
      concurrent_processes: concurrent_processes,
      messages_per_process: messages_per_process,
      total_time_us: total_time,
      avg_process_time_us: avg_process_time,
      throughput_messages_per_second:
        concurrent_processes * messages_per_process / (total_time / 1_000_000),
      concurrency_efficiency: avg_process_time / (total_time / concurrent_processes) * 100
    }
  end

  defp benchmark_memory_usage(patterns, total_messages) do
    memory_before = :erlang.memory(:total)

    detector = StepDetector.new(patterns: patterns)
    optimizer = StepPatternOptimizer.new()
    _optimized_optimizer = StepPatternOptimizer.optimize_patterns(optimizer, patterns)

    test_messages = generate_test_messages(total_messages)

    memory_after_setup = :erlang.memory(:total)

    Enum.each(test_messages, fn message ->
      StepDetector.analyze_message(detector, message, [])
    end)

    memory_after_processing = :erlang.memory(:total)

    %{
      baseline_memory_bytes: memory_before,
      setup_memory_bytes: memory_after_setup - memory_before,
      processing_memory_bytes: memory_after_processing - memory_after_setup,
      total_memory_bytes: memory_after_processing - memory_before,
      memory_per_message_bytes: (memory_after_processing - memory_after_setup) / total_messages
    }
  end

  defp benchmark_compilation_stress(patterns, concurrent_compilations) do
    start_time = System.monotonic_time(:microsecond)

    tasks =
      Enum.map(1..concurrent_compilations, fn _i ->
        Task.async(fn ->
          compilation_start = System.monotonic_time(:microsecond)

          optimizer = StepPatternOptimizer.new()
          StepPatternOptimizer.optimize_patterns(optimizer, patterns)

          compilation_end = System.monotonic_time(:microsecond)
          compilation_end - compilation_start
        end)
      end)

    compilation_times = Task.await_many(tasks, 30_000)
    end_time = System.monotonic_time(:microsecond)

    total_time = end_time - start_time
    avg_compilation_time = Enum.sum(compilation_times) / length(compilation_times)

    %{
      concurrent_compilations: concurrent_compilations,
      total_time_us: total_time,
      avg_compilation_time_us: avg_compilation_time,
      compilation_throughput: concurrent_compilations / (total_time / 1_000_000),
      stress_efficiency: avg_compilation_time / (total_time / concurrent_compilations) * 100
    }
  end

  defp calculate_cache_effectiveness(stats) do
    hit_rate = stats.cache_hit_rate
    cache_utilization = stats.cache_size / stats.cache_max_size

    # Effectiveness score based on hit rate and utilization
    (hit_rate * 0.7 + cache_utilization * 0.3) * 100
  end

  defp create_accuracy_test_cases(test_messages) do
    # Create test cases with expected results based on message content
    Enum.map(test_messages, fn message ->
      tools = extract_tools_from_message(message)
      content = extract_content_from_message(message)

      expected_type =
        cond do
          Enum.any?(tools, &(&1 in ["readFile", "fsWrite", "listDirectory"])) -> :file_operation
          Enum.any?(tools, &(&1 in ["strReplace"])) -> :code_modification
          Enum.any?(tools, &(&1 in ["executePwsh"])) -> :system_command
          Enum.any?(tools, &(&1 in ["grepSearch", "fileSearch"])) -> :exploration
          Regex.match?(~r/explain|describe/i, content) -> :communication
          true -> :analysis
        end

      {message, expected_type}
    end)
  end

  defp test_confidence_thresholds(patterns, test_cases) do
    thresholds = [0.5, 0.6, 0.7, 0.8, 0.9]

    Enum.map(thresholds, fn threshold ->
      detector = StepDetector.new(patterns: patterns, confidence_threshold: threshold)

      results =
        Enum.map(test_cases, fn {message, expected_type} ->
          {actual_result, _} = StepDetector.analyze_message(detector, message, [])

          actual_type =
            case actual_result do
              {:step_start, type, _} -> type
              {:step_boundary, type, _} -> type
              {:step_continue, nil} -> :continue
              {:step_end, _} -> :end
            end

          %{
            expected: expected_type,
            actual: actual_type,
            correct: actual_type == expected_type
          }
        end)

      correct_count = Enum.count(results, & &1.correct)
      accuracy = if length(results) > 0, do: correct_count / length(results) * 100, else: 0.0

      %{
        threshold: threshold,
        accuracy_percentage: accuracy,
        correct_predictions: correct_count,
        total_cases: length(results)
      }
    end)
  end

  defp generate_optimization_recommendations(
         pre_compilation,
         indexing,
         cache_effectiveness,
         tuning
       ) do
    recommendations = []

    # Pre-compilation recommendations
    recommendations =
      if pre_compilation.avg_compilation_time_us > 1000.0 do
        [
          "Pattern compilation is slow (#{Float.round(pre_compilation.avg_compilation_time_us, 1)}μs) - consider pattern simplification"
          | recommendations
        ]
      else
        recommendations
      end

    # Indexing recommendations
    best_indexing = Enum.max_by(indexing, & &1.avg_time_per_detection_us)

    recommendations =
      if best_indexing.strategy != :no_indexing do
        [
          "#{best_indexing.strategy} provides best performance - consider enabling"
          | recommendations
        ]
      else
        recommendations
      end

    # Cache recommendations
    best_cache = Enum.max_by(cache_effectiveness, & &1.effectiveness_score)

    recommendations =
      if best_cache.config != :no_cache do
        ["#{best_cache.config} configuration provides best cache effectiveness" | recommendations]
      else
        recommendations
      end

    # Tuning recommendations
    best_threshold = Enum.max_by(tuning.threshold_optimization, & &1.accuracy_percentage)

    recommendations =
      if best_threshold.threshold != 0.7 do
        [
          "Optimal confidence threshold appears to be #{best_threshold.threshold} (#{Float.round(best_threshold.accuracy_percentage, 1)}% accuracy)"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["Current configuration appears optimal"]
    else
      recommendations
    end
  end

  defp find_optimal_cache_size(cache_size_results) do
    # Find cache size with best efficiency ratio
    best_result = Enum.max_by(cache_size_results, & &1.efficiency_ratio)
    best_result.cache_size
  end

  defp generate_caching_recommendations(cache_size_results, _eviction_results, _warming_results) do
    optimal_size = find_optimal_cache_size(cache_size_results)
    best_result = Enum.find(cache_size_results, &(&1.cache_size == optimal_size))

    [
      "Optimal cache size: #{optimal_size} (#{Float.round(best_result.cache_stats.cache_hit_rate * 100, 1)}% hit rate)",
      "Cache efficiency ratio: #{Float.round(best_result.efficiency_ratio, 2)}"
    ]
  end

  defp generate_tuning_recommendations(accuracy_results, threshold_results) do
    best_threshold = Enum.max_by(threshold_results, & &1.accuracy_percentage)
    baseline_accuracy = accuracy_results.accuracy_percentage

    recommendations = []

    recommendations =
      if best_threshold.accuracy_percentage > baseline_accuracy + 5.0 do
        improvement = best_threshold.accuracy_percentage - baseline_accuracy

        [
          "Adjusting confidence threshold to #{best_threshold.threshold} could improve accuracy by #{Float.round(improvement, 1)}%"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if baseline_accuracy < 80.0 do
        [
          "Current accuracy (#{Float.round(baseline_accuracy, 1)}%) is below recommended threshold - consider pattern refinement"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["Pattern tuning appears optimal"]
    else
      recommendations
    end
  end

  defp calculate_stability_score(concurrent_results, memory_results) do
    # Calculate stability based on concurrency efficiency and memory usage
    concurrency_score = min(concurrent_results.concurrency_efficiency, 100.0)

    memory_score =
      if memory_results.memory_per_message_bytes < 1000,
        do: 100.0,
        else: max(0.0, 100.0 - memory_results.memory_per_message_bytes / 100)

    (concurrency_score * 0.6 + memory_score * 0.4) |> Float.round(1)
  end

  defp generate_stress_test_recommendations(concurrent_results, memory_results) do
    recommendations = []

    recommendations =
      if concurrent_results.concurrency_efficiency < 80.0 do
        [
          "Low concurrency efficiency (#{Float.round(concurrent_results.concurrency_efficiency, 1)}%) - consider reducing shared state"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if memory_results.memory_per_message_bytes > 2000 do
        [
          "High memory usage per message (#{Float.round(memory_results.memory_per_message_bytes, 1)} bytes) - consider memory optimization"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if concurrent_results.throughput_messages_per_second < 100 do
        [
          "Low throughput (#{Float.round(concurrent_results.throughput_messages_per_second, 1)} msg/s) - consider performance optimization"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["System performs well under stress"]
    else
      recommendations
    end
  end
end
