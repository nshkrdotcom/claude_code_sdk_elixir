defmodule ClaudeCodeSDK.StepIntervention do
  @moduledoc """
  System for handling step interventions with different types and validation.

  Interventions allow external systems or users to modify step behavior
  by injecting guidance, corrections, or additional context. The system
  tracks intervention history and handles errors with rollback capabilities.

  ## Intervention Types

  - `:guidance` - Provides guidance or suggestions for step execution
  - `:correction` - Corrects errors or issues in the step
  - `:context` - Adds additional context or information

  ## Features

  - Intervention application and validation
  - Intervention history tracking
  - Error handling and rollback
  - Configurable intervention processors

  ## Examples

      # Create guidance intervention
      intervention = ClaudeCodeSDK.StepIntervention.new(
        :guidance,
        "Be more careful with file operations",
        %{priority: :high}
      )

      # Apply intervention to step
      {:ok, updated_step} = ClaudeCodeSDK.StepIntervention.apply(step, intervention)

      # Create intervention processor
      processor = ClaudeCodeSDK.StepIntervention.Processor.new(
        guidance_handler: &MyApp.handle_guidance/2,
        correction_handler: &MyApp.handle_correction/2
      )

  """

  alias ClaudeCodeSDK.{Step, StepIntervention}

  defstruct [
    :id,
    :type,
    :content,
    :metadata,
    :created_at,
    :applied_at,
    :status,
    :source,
    :priority
  ]

  @type intervention_type :: :guidance | :correction | :context

  @type intervention_status :: :pending | :applied | :failed | :rolled_back

  @type intervention_priority :: :low | :medium | :high | :critical

  @type t :: %__MODULE__{
          id: String.t(),
          type: intervention_type(),
          content: String.t(),
          metadata: map(),
          created_at: DateTime.t(),
          applied_at: DateTime.t() | nil,
          status: intervention_status(),
          source: String.t() | nil,
          priority: intervention_priority()
        }

  @type application_result ::
          {:ok, Step.t()}
          | {:error, term()}
          | {:rollback, Step.t(), term()}

  ## Public API

  @doc """
  Creates a new intervention.

  ## Parameters

  - `type` - Type of intervention
  - `content` - Intervention content/message
  - `metadata` - Additional metadata (optional)

  ## Options

  - `:id` - Custom intervention ID
  - `:source` - Source of the intervention
  - `:priority` - Intervention priority
  - `:metadata` - Additional metadata

  ## Examples

      intervention = ClaudeCodeSDK.StepIntervention.new(
        :guidance,
        "Consider using a safer approach",
        %{suggestion: "Use readFile instead of direct file access"}
      )

  """
  @spec new(intervention_type(), String.t(), map(), keyword()) :: t()
  def new(type, content, metadata \\ %{}, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      type: type,
      content: content,
      metadata: metadata,
      created_at: DateTime.utc_now(),
      applied_at: nil,
      status: :pending,
      source: Keyword.get(opts, :source),
      priority: Keyword.get(opts, :priority, :medium)
    }
  end

  @doc """
  Applies an intervention to a step.

  ## Parameters

  - `step` - The step to apply the intervention to
  - `intervention` - The intervention to apply
  - `processor` - Optional intervention processor

  ## Returns

  - `{:ok, updated_step}` - Intervention applied successfully
  - `{:error, reason}` - Application failed
  - `{:rollback, step, reason}` - Application failed, rollback performed

  ## Examples

      case ClaudeCodeSDK.StepIntervention.apply(step, intervention) do
        {:ok, updated_step} -> 
          IO.puts("Intervention applied successfully")
        {:error, reason} -> 
          IO.puts("Failed to apply intervention: \#{reason}")
      end

  """
  @spec apply(Step.t(), t(), module() | nil) :: application_result()
  def apply(step, intervention, processor \\ nil) do
    try do
      # Validate intervention
      case validate_intervention(intervention) do
        :ok ->
          apply_intervention(step, intervention, processor)

        {:error, reason} ->
          {:error, {:validation_failed, reason}}
      end
    rescue
      error ->
        {:error, {:application_exception, error}}
    end
  end

  @doc """
  Applies multiple interventions to a step in order.

  ## Parameters

  - `step` - The step to apply interventions to
  - `interventions` - List of interventions to apply
  - `processor` - Optional intervention processor

  ## Returns

  - `{:ok, updated_step}` - All interventions applied successfully
  - `{:error, reason, partial_step}` - Some interventions failed
  - `{:rollback, step, reason}` - Application failed, rollback performed

  ## Examples

      interventions = [guidance_intervention, correction_intervention]
      
      case ClaudeCodeSDK.StepIntervention.apply_multiple(step, interventions) do
        {:ok, updated_step} -> 
          IO.puts("All interventions applied")
        {:error, reason, partial_step} -> 
          IO.puts("Partial application: \#{reason}")
      end

  """
  @spec apply_multiple(Step.t(), [t()], module() | nil) ::
          {:ok, Step.t()} | {:error, term(), Step.t()} | {:rollback, Step.t(), term()}
  def apply_multiple(step, interventions, processor \\ nil) do
    # Sort interventions by priority
    sorted_interventions = sort_by_priority(interventions)

    # Apply interventions one by one
    apply_interventions_sequentially(step, sorted_interventions, processor, [])
  end

  @doc """
  Rolls back an intervention from a step.

  ## Parameters

  - `step` - The step to rollback the intervention from
  - `intervention_id` - ID of the intervention to rollback

  ## Returns

  - `{:ok, updated_step}` - Rollback successful
  - `{:error, reason}` - Rollback failed

  ## Examples

      {:ok, rolled_back_step} = ClaudeCodeSDK.StepIntervention.rollback(
        step, 
        "intervention-123"
      )

  """
  @spec rollback(Step.t(), String.t()) :: {:ok, Step.t()} | {:error, term()}
  def rollback(step, intervention_id) do
    case find_intervention_in_step(step, intervention_id) do
      nil ->
        {:error, :intervention_not_found}

      intervention ->
        perform_rollback(step, intervention)
    end
  end

  @doc """
  Gets the intervention history for a step.

  ## Parameters

  - `step` - The step to get history for

  ## Returns

  List of interventions applied to the step, sorted by application time.

  ## Examples

      history = ClaudeCodeSDK.StepIntervention.get_history(step)
      IO.puts("Applied \#{length(history)} interventions")

  """
  @spec get_history(Step.t()) :: [t()]
  def get_history(step) do
    step.interventions
    |> Enum.map(&intervention_from_step_data/1)
    |> Enum.sort_by(& &1.applied_at, {:asc, DateTime})
  end

  @doc """
  Validates an intervention for correctness.

  ## Parameters

  - `intervention` - The intervention to validate

  ## Returns

  - `:ok` - Intervention is valid
  - `{:error, reason}` - Intervention is invalid

  """
  @spec validate_intervention(t()) :: :ok | {:error, term()}
  def validate_intervention(intervention) do
    with :ok <- validate_type(intervention.type),
         :ok <- validate_content(intervention.content),
         :ok <- validate_priority(intervention.priority) do
      :ok
    end
  end

  ## Private Functions

  # Applies a single intervention to a step
  defp apply_intervention(step, intervention, processor) do
    # Mark intervention as being applied
    applying_intervention = %{intervention | status: :applied, applied_at: DateTime.utc_now()}

    # Apply the intervention based on type
    case apply_by_type(step, applying_intervention, processor) do
      {:ok, updated_step} ->
        # Add intervention to step history
        final_step =
          Step.add_intervention(updated_step, intervention_to_step_data(applying_intervention))

        {:ok, final_step}

      {:error, reason} ->
        # Mark intervention as failed
        failed_intervention = %{applying_intervention | status: :failed}
        {:error, {reason, failed_intervention}}

      {:rollback, rollback_step, reason} ->
        # Mark intervention as rolled back
        rolled_back_intervention = %{applying_intervention | status: :rolled_back}
        {:rollback, rollback_step, {reason, rolled_back_intervention}}
    end
  end

  # Applies intervention based on its type
  defp apply_by_type(step, intervention, processor) do
    case intervention.type do
      :guidance ->
        apply_guidance(step, intervention, processor)

      :correction ->
        apply_correction(step, intervention, processor)

      :context ->
        apply_context(step, intervention, processor)

      _ ->
        {:error, {:unknown_intervention_type, intervention.type}}
    end
  end

  # Applies guidance intervention
  defp apply_guidance(step, intervention, processor) do
    if processor && function_exported?(processor, :handle_guidance, 2) do
      processor.handle_guidance(step, intervention)
    else
      # Default guidance handling - add to metadata
      updated_metadata = Map.put(step.metadata, :guidance, intervention.content)
      updated_step = %{step | metadata: updated_metadata}
      {:ok, updated_step}
    end
  end

  # Applies correction intervention
  defp apply_correction(step, intervention, processor) do
    if processor && function_exported?(processor, :handle_correction, 2) do
      processor.handle_correction(step, intervention)
    else
      # Default correction handling - add to metadata and update description
      updated_metadata = Map.put(step.metadata, :correction, intervention.content)
      updated_description = "#{step.description} [CORRECTED: #{intervention.content}]"

      updated_step = %{step | metadata: updated_metadata, description: updated_description}
      {:ok, updated_step}
    end
  end

  # Applies context intervention
  defp apply_context(step, intervention, processor) do
    if processor && function_exported?(processor, :handle_context, 2) do
      processor.handle_context(step, intervention)
    else
      # Default context handling - merge context into metadata
      context_data = Map.get(intervention.metadata, :context, %{})
      updated_metadata = Map.merge(step.metadata, context_data)
      updated_step = %{step | metadata: updated_metadata}
      {:ok, updated_step}
    end
  end

  # Applies interventions sequentially
  defp apply_interventions_sequentially(step, [], _processor, _applied) do
    # All interventions applied successfully
    {:ok, step}
  end

  defp apply_interventions_sequentially(step, [intervention | rest], processor, applied) do
    case apply_intervention(step, intervention, processor) do
      {:ok, updated_step} ->
        apply_interventions_sequentially(updated_step, rest, processor, [intervention | applied])

      {:error, {reason, _failed_intervention}} ->
        # Rollback previously applied interventions
        rollback_step = rollback_applied_interventions(step, applied)
        {:error, reason, rollback_step}

      {:rollback, rollback_step, {reason, _rolled_back_intervention}} ->
        {:rollback, rollback_step, reason}
    end
  end

  # Rolls back previously applied interventions
  defp rollback_applied_interventions(step, applied_interventions) do
    Enum.reduce(applied_interventions, step, fn intervention, acc_step ->
      case perform_rollback(acc_step, intervention) do
        {:ok, rolled_back_step} -> rolled_back_step
        # Continue with partial rollback
        {:error, _reason} -> acc_step
      end
    end)
  end

  # Performs rollback of a specific intervention
  defp perform_rollback(step, intervention) do
    # Remove intervention from step history
    updated_interventions =
      step.interventions
      |> Enum.reject(fn int_data ->
        Map.get(int_data, :id) == intervention.id
      end)

    # Revert changes based on intervention type
    case revert_by_type(step, intervention) do
      {:ok, reverted_step} ->
        final_step = %{reverted_step | interventions: updated_interventions}
        {:ok, final_step}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Reverts changes based on intervention type
  defp revert_by_type(step, intervention) do
    case intervention.type do
      :guidance ->
        # Remove guidance from metadata
        updated_metadata = Map.delete(step.metadata, :guidance)
        {:ok, %{step | metadata: updated_metadata}}

      :correction ->
        # This is more complex - would need to store original values
        # For now, just remove correction metadata
        updated_metadata = Map.delete(step.metadata, :correction)
        {:ok, %{step | metadata: updated_metadata}}

      :context ->
        # Remove context data - this is also complex without original state
        {:ok, step}

      _ ->
        {:error, {:unknown_intervention_type, intervention.type}}
    end
  end

  # Sorts interventions by priority
  defp sort_by_priority(interventions) do
    priority_order = %{critical: 0, high: 1, medium: 2, low: 3}

    Enum.sort_by(interventions, fn intervention ->
      Map.get(priority_order, intervention.priority, 999)
    end)
  end

  # Finds an intervention in a step by ID
  defp find_intervention_in_step(step, intervention_id) do
    step.interventions
    |> Enum.find(fn int_data ->
      Map.get(int_data, :id) == intervention_id
    end)
    |> case do
      nil -> nil
      int_data -> intervention_from_step_data(int_data)
    end
  end

  # Converts intervention to step data format
  defp intervention_to_step_data(intervention) do
    %{
      id: intervention.id,
      type: intervention.type,
      content: intervention.content,
      applied_at: intervention.applied_at
    }
  end

  # Converts step data to intervention format
  defp intervention_from_step_data(step_data) do
    %__MODULE__{
      id: Map.get(step_data, :id),
      type: Map.get(step_data, :type),
      content: Map.get(step_data, :content),
      metadata: Map.get(step_data, :metadata, %{}),
      created_at: Map.get(step_data, :created_at),
      applied_at: Map.get(step_data, :applied_at),
      status: Map.get(step_data, :status, :applied),
      source: Map.get(step_data, :source),
      priority: Map.get(step_data, :priority, :medium)
    }
  end

  # Validation functions
  defp validate_type(type) when type in [:guidance, :correction, :context], do: :ok
  defp validate_type(type), do: {:error, {:invalid_type, type}}

  defp validate_content(content) when is_binary(content) and byte_size(content) > 0, do: :ok
  defp validate_content(content), do: {:error, {:invalid_content, content}}

  defp validate_priority(priority) when priority in [:low, :medium, :high, :critical], do: :ok
  defp validate_priority(priority), do: {:error, {:invalid_priority, priority}}

  # Generates unique intervention IDs
  defp generate_id do
    "intervention-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  ## Intervention Processor Behavior

  defmodule Processor do
    @moduledoc """
    Behavior for implementing custom intervention processors.

    Processors handle the application of specific intervention types
    with custom logic beyond the default implementations.
    """

    @type processor_result ::
            {:ok, Step.t()}
            | {:error, term()}
            | {:rollback, Step.t(), term()}

    @doc """
    Handles guidance interventions.

    ## Parameters

    - `step` - The step to apply guidance to
    - `intervention` - The guidance intervention

    ## Returns

    Processor result indicating success, error, or rollback needed.
    """
    @callback handle_guidance(Step.t(), StepIntervention.t()) :: processor_result()

    @doc """
    Handles correction interventions.

    ## Parameters

    - `step` - The step to apply correction to
    - `intervention` - The correction intervention

    ## Returns

    Processor result indicating success, error, or rollback needed.
    """
    @callback handle_correction(Step.t(), StepIntervention.t()) :: processor_result()

    @doc """
    Handles context interventions.

    ## Parameters

    - `step` - The step to apply context to
    - `intervention` - The context intervention

    ## Returns

    Processor result indicating success, error, or rollback needed.
    """
    @callback handle_context(Step.t(), StepIntervention.t()) :: processor_result()

    @optional_callbacks handle_guidance: 2, handle_correction: 2, handle_context: 2

    ## Built-in Processors

    defmodule Default do
      @moduledoc """
      Default intervention processor with basic implementations.
      """

      @behaviour ClaudeCodeSDK.StepIntervention.Processor

      @impl true
      def handle_guidance(step, intervention) do
        # Add guidance to step metadata
        guidance_list = Map.get(step.metadata, :guidance_history, [])
        updated_guidance = [intervention.content | guidance_list]

        updated_metadata = Map.put(step.metadata, :guidance_history, updated_guidance)
        updated_step = %{step | metadata: updated_metadata}

        {:ok, updated_step}
      end

      @impl true
      def handle_correction(step, intervention) do
        # Apply correction by updating description and metadata
        correction_note = "[CORRECTED: #{intervention.content}]"
        updated_description = "#{step.description} #{correction_note}"

        correction_list = Map.get(step.metadata, :correction_history, [])
        updated_corrections = [intervention.content | correction_list]

        updated_metadata = Map.put(step.metadata, :correction_history, updated_corrections)

        updated_step = %{step | description: updated_description, metadata: updated_metadata}

        {:ok, updated_step}
      end

      @impl true
      def handle_context(step, intervention) do
        # Merge context data into step metadata
        context_data = Map.get(intervention.metadata, :context, %{})
        updated_metadata = Map.merge(step.metadata, context_data)

        # Track context additions
        context_list = Map.get(step.metadata, :context_history, [])
        updated_context = [intervention.content | context_list]
        final_metadata = Map.put(updated_metadata, :context_history, updated_context)

        updated_step = %{step | metadata: final_metadata}
        {:ok, updated_step}
      end
    end
  end
end
