defmodule ClaudeCodeSDK.StepConfigTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{StepConfig, StepPattern}

  describe "StepConfig.new/1" do
    test "creates config with default values" do
      config = StepConfig.new()

      # Step grouping defaults
      assert config.step_grouping.enabled == false
      assert config.step_grouping.strategy == :pattern_based
      assert config.step_grouping.patterns == :default
      assert config.step_grouping.confidence_threshold == 0.7
      assert config.step_grouping.buffer_timeout_ms == 5000
      assert config.step_grouping.max_buffer_size == 100

      # Step control defaults
      assert config.step_control.mode == :automatic
      assert config.step_control.pause_between_steps == false
      assert config.step_control.review_handler == nil
      assert config.step_control.intervention_handler == nil
      assert config.step_control.review_timeout_ms == 30_000
      assert config.step_control.default_review_action == :approve

      # State management defaults
      assert config.state_management.persist_steps == false
      assert config.state_management.persistence_adapter == nil
      assert config.state_management.max_step_history == 100
      assert config.state_management.checkpoint_interval == 10
      assert config.state_management.auto_prune == true
    end

    test "creates config with custom options" do
      config =
        StepConfig.new(
          step_grouping: %{enabled: true, confidence_threshold: 0.8},
          step_control: %{mode: :manual, pause_between_steps: true},
          state_management: %{persist_steps: true, max_step_history: 200}
        )

      assert config.step_grouping.enabled == true
      assert config.step_grouping.confidence_threshold == 0.8
      assert config.step_control.mode == :manual
      assert config.step_control.pause_between_steps == true
      assert config.state_management.persist_steps == true
      assert config.state_management.max_step_history == 200
    end
  end

  describe "StepConfig.default/0" do
    test "returns default config with step grouping disabled" do
      config = StepConfig.default()

      assert config.step_grouping.enabled == false
    end
  end

  describe "StepConfig.with_step_grouping/1" do
    test "creates config with step grouping enabled" do
      config = StepConfig.with_step_grouping()

      assert config.step_grouping.enabled == true
    end

    test "accepts additional options" do
      config =
        StepConfig.with_step_grouping(
          step_grouping: %{confidence_threshold: 0.9},
          step_control: %{mode: :manual}
        )

      assert config.step_grouping.enabled == true
      assert config.step_grouping.confidence_threshold == 0.9
      assert config.step_control.mode == :manual
    end
  end

  describe "StepConfig.with_manual_control/1" do
    test "creates config with manual control" do
      config = StepConfig.with_manual_control()

      assert config.step_grouping.enabled == true
      assert config.step_control.mode == :manual
    end
  end

  describe "StepConfig.with_review_control/2" do
    test "creates config with review control" do
      config = StepConfig.with_review_control(MyApp.Reviewer)

      assert config.step_grouping.enabled == true
      assert config.step_control.mode == :review_required
      assert config.step_control.review_handler == MyApp.Reviewer
    end
  end

  describe "StepConfig.validate/1" do
    test "validates correct config" do
      config = StepConfig.new()

      assert StepConfig.validate(config) == :ok
    end

    test "validates config with step grouping enabled" do
      config = StepConfig.with_step_grouping()

      assert StepConfig.validate(config) == :ok
    end

    test "validates config with custom patterns" do
      patterns = [
        StepPattern.new(
          id: :custom_pattern,
          name: "Custom Pattern",
          triggers: [StepPattern.tool_trigger(["readFile"])]
        )
      ]

      config = StepConfig.new(step_grouping: %{enabled: true, patterns: patterns})

      assert StepConfig.validate(config) == :ok
    end

    test "returns error for invalid confidence threshold" do
      config =
        StepConfig.new(
          # Invalid - should be 0.0-1.0
          step_grouping: %{confidence_threshold: 1.5}
        )

      assert {:error, _reason} = StepConfig.validate(config)
    end

    test "returns error for review mode without handler" do
      config = StepConfig.new(step_control: %{mode: :review_required, review_handler: nil})

      assert {:error, reason} = StepConfig.validate(config)
      assert reason =~ "Review handler is required"
    end
  end

  describe "StepConfig.merge/2" do
    test "merges two configurations" do
      base = StepConfig.default()
      override = StepConfig.with_step_grouping(step_grouping: %{confidence_threshold: 0.9})

      merged = StepConfig.merge(base, override)

      assert merged.step_grouping.enabled == true
      assert merged.step_grouping.confidence_threshold == 0.9
      # From base
      assert merged.step_control.mode == :automatic
    end
  end

  describe "StepConfig.to_keyword/1" do
    test "converts config to keyword list" do
      config = StepConfig.with_step_grouping()
      keyword_config = StepConfig.to_keyword(config)

      assert is_list(keyword_config)
      assert Keyword.has_key?(keyword_config, :step_grouping)
      assert Keyword.has_key?(keyword_config, :step_control)
      assert Keyword.has_key?(keyword_config, :state_management)

      step_grouping = Keyword.get(keyword_config, :step_grouping)
      assert Keyword.get(step_grouping, :enabled) == true
    end
  end
end
