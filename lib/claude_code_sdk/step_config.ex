defmodule ClaudeCodeSDK.StepConfig do
  @moduledoc """
  Configuration structures for the step grouping feature.

  This module defines the configuration options for step detection, control,
  and state management. It provides validation and default values for all
  configuration options.

  ## Configuration Sections

  - **Step Grouping**: Controls step detection and pattern matching
  - **Step Control**: Controls pause/resume and review behavior
  - **State Management**: Controls persistence and history management

  ## Examples

      # Basic configuration
      config = %ClaudeCodeSDK.StepConfig{
        step_grouping: %{
          enabled: true,
          strategy: :pattern_based,
          patterns: :default
        }
      }

      # Advanced configuration
      config = %ClaudeCodeSDK.StepConfig{
        step_grouping: %{
          enabled: true,
          strategy: :pattern_based,
          patterns: custom_patterns,
          confidence_threshold: 0.8,
          buffer_timeout_ms: 3000
        },
        step_control: %{
          mode: :review_required,
          review_handler: MyApp.StepReviewer,
          intervention_handler: MyApp.InterventionHandler
        },
        state_management: %{
          persist_steps: true,
          persistence_adapter: MyApp.DatabaseAdapter,
          max_step_history: 200
        }
      }

  """

  alias ClaudeCodeSDK.StepPattern

  defstruct [
    :step_grouping,
    :step_control,
    :state_management
  ]

  @type step_grouping_config :: %{
          enabled: boolean(),
          strategy: :pattern_based | :heuristic | :hybrid,
          patterns: :default | [StepPattern.t()],
          confidence_threshold: float(),
          buffer_timeout_ms: integer(),
          max_buffer_size: integer()
        }

  @type step_control_config :: %{
          mode: :automatic | :manual | :review_required,
          pause_between_steps: boolean(),
          review_handler: module() | nil,
          intervention_handler: module() | nil,
          review_timeout_ms: integer(),
          default_review_action: :approve | :reject | :pause
        }

  @type state_management_config :: %{
          persist_steps: boolean(),
          persistence_adapter: module() | nil,
          max_step_history: integer(),
          checkpoint_interval: integer(),
          auto_prune: boolean()
        }

  @type t :: %__MODULE__{
          step_grouping: step_grouping_config(),
          step_control: step_control_config(),
          state_management: state_management_config()
        }

  @doc """
  Creates a new configuration with default values.

  ## Parameters

  - `opts` - Keyword list of configuration options

  ## Options

  - `:step_grouping` - Step grouping configuration map
  - `:step_control` - Step control configuration map
  - `:state_management` - State management configuration map

  ## Examples

      iex> ClaudeCodeSDK.StepConfig.new()
      %ClaudeCodeSDK.StepConfig{
        step_grouping: %{enabled: false, ...},
        step_control: %{mode: :automatic, ...}
      }

      iex> ClaudeCodeSDK.StepConfig.new(
      ...>   step_grouping: %{enabled: true},
      ...>   step_control: %{mode: :manual}
      ...> )
      %ClaudeCodeSDK.StepConfig{
        step_grouping: %{enabled: true, ...},
        step_control: %{mode: :manual, ...}
      }

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    step_grouping_opts = Keyword.get(opts, :step_grouping, %{})
    step_control_opts = Keyword.get(opts, :step_control, %{})
    state_management_opts = Keyword.get(opts, :state_management, %{})

    %__MODULE__{
      step_grouping: build_step_grouping_config(step_grouping_opts),
      step_control: build_step_control_config(step_control_opts),
      state_management: build_state_management_config(state_management_opts)
    }
  end

  @doc """
  Gets the default configuration.

  This configuration preserves backward compatibility by disabling
  step grouping by default.

  ## Returns

  Default configuration with step grouping disabled.

  ## Examples

      iex> config = ClaudeCodeSDK.StepConfig.default()
      iex> config.step_grouping.enabled
      false

  """
  @spec default() :: t()
  def default do
    new()
  end

  @doc """
  Creates a configuration with step grouping enabled and default patterns.

  ## Parameters

  - `opts` - Additional configuration options

  ## Returns

  Configuration with step grouping enabled.

  ## Examples

      iex> config = ClaudeCodeSDK.StepConfig.with_step_grouping()
      iex> config.step_grouping.enabled
      true

  """
  @spec with_step_grouping(keyword()) :: t()
  def with_step_grouping(opts \\ []) do
    step_grouping_opts =
      opts
      |> Keyword.get(:step_grouping, %{})
      |> Map.put(:enabled, true)

    new(Keyword.put(opts, :step_grouping, step_grouping_opts))
  end

  @doc """
  Creates a configuration with manual step control.

  ## Parameters

  - `opts` - Additional configuration options

  ## Returns

  Configuration with manual step control enabled.

  ## Examples

      iex> config = ClaudeCodeSDK.StepConfig.with_manual_control()
      iex> config.step_control.mode
      :manual

  """
  @spec with_manual_control(keyword()) :: t()
  def with_manual_control(opts \\ []) do
    step_control_opts =
      opts
      |> Keyword.get(:step_control, %{})
      |> Map.put(:mode, :manual)

    step_grouping_opts =
      opts
      |> Keyword.get(:step_grouping, %{})
      |> Map.put(:enabled, true)

    new(
      [
        step_grouping: step_grouping_opts,
        step_control: step_control_opts
      ] ++ Keyword.drop(opts, [:step_grouping, :step_control])
    )
  end

  @doc """
  Creates a configuration with review-required step control.

  ## Parameters

  - `review_handler` - Module implementing review handler behavior
  - `opts` - Additional configuration options

  ## Returns

  Configuration with review-required step control.

  ## Examples

      iex> config = ClaudeCodeSDK.StepConfig.with_review_control(MyApp.Reviewer)
      iex> config.step_control.mode
      :review_required

  """
  @spec with_review_control(module(), keyword()) :: t()
  def with_review_control(review_handler, opts \\ []) do
    step_control_opts =
      opts
      |> Keyword.get(:step_control, %{})
      |> Map.put(:mode, :review_required)
      |> Map.put(:review_handler, review_handler)

    step_grouping_opts =
      opts
      |> Keyword.get(:step_grouping, %{})
      |> Map.put(:enabled, true)

    new(
      [
        step_grouping: step_grouping_opts,
        step_control: step_control_opts
      ] ++ Keyword.drop(opts, [:step_grouping, :step_control])
    )
  end

  @doc """
  Validates the configuration.

  ## Parameters

  - `config` - The configuration to validate

  ## Returns

  `:ok` if valid, `{:error, reason}` if invalid.

  ## Examples

      iex> config = ClaudeCodeSDK.StepConfig.new()
      iex> ClaudeCodeSDK.StepConfig.validate(config)
      :ok

  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = config) do
    with :ok <- validate_step_grouping(config.step_grouping),
         :ok <- validate_step_control(config.step_control),
         :ok <- validate_state_management(config.state_management) do
      :ok
    end
  end

  @doc """
  Merges two configurations, with the second taking precedence.

  ## Parameters

  - `base` - Base configuration
  - `override` - Override configuration

  ## Returns

  Merged configuration.

  ## Examples

      iex> base = ClaudeCodeSDK.StepConfig.default()
      iex> override = ClaudeCodeSDK.StepConfig.with_step_grouping()
      iex> merged = ClaudeCodeSDK.StepConfig.merge(base, override)
      iex> merged.step_grouping.enabled
      true

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = base, %__MODULE__{} = override) do
    %__MODULE__{
      step_grouping: Map.merge(base.step_grouping, override.step_grouping),
      step_control: Map.merge(base.step_control, override.step_control),
      state_management: Map.merge(base.state_management, override.state_management)
    }
  end

  @doc """
  Converts configuration to keyword list for application config.

  ## Parameters

  - `config` - The configuration to convert

  ## Returns

  Keyword list suitable for application configuration.

  ## Examples

      iex> config = ClaudeCodeSDK.StepConfig.with_step_grouping()
      iex> keyword_config = ClaudeCodeSDK.StepConfig.to_keyword(config)
      iex> keyword_config[:step_grouping][:enabled]
      true

  """
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = config) do
    [
      step_grouping: Map.to_list(config.step_grouping),
      step_control: Map.to_list(config.step_control),
      state_management: Map.to_list(config.state_management)
    ]
  end

  # Private helper functions

  defp build_step_grouping_config(opts) when is_map(opts) do
    defaults = %{
      enabled: false,
      strategy: :pattern_based,
      patterns: :default,
      confidence_threshold: 0.7,
      buffer_timeout_ms: 5000,
      max_buffer_size: 100
    }

    Map.merge(defaults, opts)
  end

  defp build_step_grouping_config(opts) when is_list(opts) do
    build_step_grouping_config(Map.new(opts))
  end

  defp build_step_control_config(opts) when is_map(opts) do
    defaults = %{
      mode: :automatic,
      pause_between_steps: false,
      review_handler: nil,
      intervention_handler: nil,
      review_timeout_ms: 30_000,
      default_review_action: :approve
    }

    Map.merge(defaults, opts)
  end

  defp build_step_control_config(opts) when is_list(opts) do
    build_step_control_config(Map.new(opts))
  end

  defp build_state_management_config(opts) when is_map(opts) do
    defaults = %{
      persist_steps: false,
      persistence_adapter: nil,
      max_step_history: 100,
      checkpoint_interval: 10,
      auto_prune: true
    }

    Map.merge(defaults, opts)
  end

  defp build_state_management_config(opts) when is_list(opts) do
    build_state_management_config(Map.new(opts))
  end

  # Validation functions

  defp validate_step_grouping(%{enabled: enabled} = config) when is_boolean(enabled) do
    with :ok <- validate_strategy(config.strategy),
         :ok <- validate_patterns(config.patterns),
         :ok <- validate_confidence_threshold(config.confidence_threshold),
         :ok <- validate_buffer_timeout(config.buffer_timeout_ms),
         :ok <- validate_buffer_size(config.max_buffer_size) do
      :ok
    end
  end

  defp validate_step_grouping(_),
    do: {:error, "Step grouping config must have boolean :enabled field"}

  defp validate_step_control(%{mode: mode} = config)
       when mode in [:automatic, :manual, :review_required] do
    with :ok <- validate_pause_between_steps(config.pause_between_steps),
         :ok <- validate_review_handler(config.review_handler, mode),
         :ok <- validate_intervention_handler(config.intervention_handler),
         :ok <- validate_review_timeout(config.review_timeout_ms),
         :ok <- validate_default_review_action(config.default_review_action) do
      :ok
    end
  end

  defp validate_step_control(_),
    do: {:error, "Step control mode must be :automatic, :manual, or :review_required"}

  defp validate_state_management(%{persist_steps: persist} = config) when is_boolean(persist) do
    with :ok <- validate_persistence_adapter(config.persistence_adapter, persist),
         :ok <- validate_max_history(config.max_step_history),
         :ok <- validate_checkpoint_interval(config.checkpoint_interval),
         :ok <- validate_auto_prune(config.auto_prune) do
      :ok
    end
  end

  defp validate_state_management(_),
    do: {:error, "State management config must have boolean :persist_steps field"}

  defp validate_strategy(strategy) when strategy in [:pattern_based, :heuristic, :hybrid], do: :ok

  defp validate_strategy(_),
    do: {:error, "Strategy must be :pattern_based, :heuristic, or :hybrid"}

  defp validate_patterns(:default), do: :ok

  defp validate_patterns(patterns) when is_list(patterns) do
    if Enum.all?(patterns, &match?(%StepPattern{}, &1)) do
      :ok
    else
      {:error, "Patterns must be a list of StepPattern structs"}
    end
  end

  defp validate_patterns(_),
    do: {:error, "Patterns must be :default or a list of StepPattern structs"}

  defp validate_confidence_threshold(threshold)
       when is_float(threshold) and threshold >= 0.0 and threshold <= 1.0,
       do: :ok

  defp validate_confidence_threshold(_),
    do: {:error, "Confidence threshold must be a float between 0.0 and 1.0"}

  defp validate_buffer_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_buffer_timeout(_), do: {:error, "Buffer timeout must be a positive integer"}

  defp validate_buffer_size(size) when is_integer(size) and size > 0, do: :ok
  defp validate_buffer_size(_), do: {:error, "Buffer size must be a positive integer"}

  defp validate_pause_between_steps(pause) when is_boolean(pause), do: :ok
  defp validate_pause_between_steps(_), do: {:error, "Pause between steps must be a boolean"}

  defp validate_review_handler(nil, :review_required),
    do: {:error, "Review handler is required when mode is :review_required"}

  defp validate_review_handler(nil, mode) when mode != :review_required, do: :ok

  defp validate_review_handler(handler, :review_required)
       when is_atom(handler) and not is_nil(handler),
       do: :ok

  defp validate_review_handler(handler, _) when is_atom(handler), do: :ok
  defp validate_review_handler(_, _), do: {:error, "Review handler must be a module atom"}

  defp validate_intervention_handler(nil), do: :ok
  defp validate_intervention_handler(handler) when is_atom(handler), do: :ok

  defp validate_intervention_handler(_),
    do: {:error, "Intervention handler must be a module atom"}

  defp validate_review_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_review_timeout(_), do: {:error, "Review timeout must be a positive integer"}

  defp validate_default_review_action(action) when action in [:approve, :reject, :pause], do: :ok

  defp validate_default_review_action(_),
    do: {:error, "Default review action must be :approve, :reject, or :pause"}

  defp validate_persistence_adapter(nil, false), do: :ok
  defp validate_persistence_adapter(adapter, true) when is_atom(adapter), do: :ok

  defp validate_persistence_adapter(nil, true),
    do: {:error, "Persistence adapter is required when persist_steps is true"}

  defp validate_persistence_adapter(adapter, _) when is_atom(adapter), do: :ok

  defp validate_persistence_adapter(_, _),
    do: {:error, "Persistence adapter must be a module atom"}

  defp validate_max_history(max) when is_integer(max) and max > 0, do: :ok
  defp validate_max_history(_), do: {:error, "Max step history must be a positive integer"}

  defp validate_checkpoint_interval(interval) when is_integer(interval) and interval > 0, do: :ok

  defp validate_checkpoint_interval(_),
    do: {:error, "Checkpoint interval must be a positive integer"}

  defp validate_auto_prune(prune) when is_boolean(prune), do: :ok
  defp validate_auto_prune(_), do: {:error, "Auto prune must be a boolean"}
end
