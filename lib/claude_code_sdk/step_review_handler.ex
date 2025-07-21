defmodule ClaudeCodeSDK.StepReviewHandler do
  @moduledoc """
  Behavior for implementing step review handlers.

  Review handlers are responsible for evaluating steps before they execute
  in review_required mode. They provide async review processing with timeout
  handling and decision validation.

  ## Behavior

  Review handlers must implement the `review_step/1` callback which receives
  a step and returns a review decision.

  ## Review Decisions

  - `:approved` - Step is approved for execution
  - `:rejected` - Step should be skipped
  - `{:approved_with_changes, changes}` - Step approved with modifications
  - `{:error, reason}` - Review failed with error

  ## Examples

      defmodule MyApp.SafetyReviewer do
        @behaviour ClaudeCodeSDK.StepReviewHandler

        @impl true
        def review_step(step) do
          case step.type do
            :file_operation -> 
              if safe_file_operation?(step) do
                :approved
              else
                :rejected
              end
            
            :system_command ->
              :rejected  # Never allow system commands
            
            _ ->
              :approved
          end
        end

        defp safe_file_operation?(step) do
          # Custom safety logic
          not Enum.any?(step.tools_used, &(&1 == "deleteFile"))
        end
      end

  """

  alias ClaudeCodeSDK.Step

  @type review_decision ::
          :approved
          | :rejected
          | {:approved_with_changes, map()}
          | {:error, term()}

  @doc """
  Reviews a step and returns a decision.

  This callback is called for each step when the controller is in
  review_required mode. The implementation should evaluate the step
  and return an appropriate decision.

  ## Parameters

  - `step` - The step to review

  ## Returns

  A review decision indicating whether the step should proceed.

  ## Examples

      def review_step(step) do
        case analyze_step_safety(step) do
          :safe -> :approved
          :unsafe -> :rejected
          {:conditional, changes} -> {:approved_with_changes, changes}
        end
      end

  """
  @callback review_step(Step.t()) :: review_decision()

  @doc """
  Optional callback for handling review timeouts.

  If not implemented, defaults to rejecting the step.

  ## Parameters

  - `step` - The step that timed out
  - `timeout_ms` - The timeout duration that was exceeded

  ## Returns

  A review decision for the timed-out step.

  """
  @callback handle_review_timeout(Step.t(), pos_integer()) :: review_decision()

  @optional_callbacks handle_review_timeout: 2

  ## Default Implementations

  @doc """
  Default timeout handler that rejects timed-out steps.
  """
  def default_timeout_handler(_step, _timeout_ms) do
    :rejected
  end

  ## Utility Functions

  @doc """
  Creates an async review task with timeout handling.

  This utility function wraps the review process with proper timeout
  and error handling, making it easier to implement robust review handlers.

  ## Parameters

  - `review_handler` - Module implementing the review behavior
  - `step` - Step to review
  - `timeout_ms` - Timeout for the review process
  - `callback_pid` - PID to send results to

  ## Examples

      ClaudeCodeSDK.StepReviewHandler.async_review(
        MyApp.SafetyReviewer,
        step,
        5000,
        self()
      )

  """
  @spec async_review(module(), Step.t(), pos_integer(), pid()) :: {:ok, pid()}
  def async_review(review_handler, step, timeout_ms, callback_pid) do
    {:ok, task_pid} =
      Task.start(fn ->
        result =
          try do
            # Direct call with timeout using Task.async
            task =
              Task.async(fn ->
                try do
                  review_handler.review_step(step)
                rescue
                  error -> {:error, {:review_exception, error}}
                catch
                  :exit, reason -> {:error, {:review_exit, reason}}
                  :throw, value -> {:error, {:review_throw, value}}
                end
              end)

            case Task.yield(task, timeout_ms) do
              {:ok, {:error, _} = error_result} ->
                error_result

              {:ok, decision} ->
                validate_review_decision(decision)

              nil ->
                # Timeout occurred
                Task.shutdown(task, :brutal_kill)

                if function_exported?(review_handler, :handle_review_timeout, 2) do
                  review_handler.handle_review_timeout(step, timeout_ms)
                else
                  default_timeout_handler(step, timeout_ms)
                end

              {:exit, reason} ->
                {:error, {:review_task_exit, reason}}
            end
          rescue
            error ->
              {:error, {:review_exception, error}}
          catch
            :exit, reason ->
              {:error, {:review_exit, reason}}

            :throw, value ->
              {:error, {:review_throw, value}}
          end

        send(callback_pid, {:review_result, step.id, result})
      end)

    {:ok, task_pid}
  end

  @doc """
  Validates a review decision to ensure it's properly formatted.

  ## Parameters

  - `decision` - The decision to validate

  ## Returns

  The validated decision or an error tuple.

  """
  @spec validate_review_decision(any()) :: review_decision()
  def validate_review_decision(decision) do
    case decision do
      :approved ->
        :approved

      :rejected ->
        :rejected

      {:approved_with_changes, changes} when is_map(changes) ->
        {:approved_with_changes, changes}

      {:error, _reason} = error ->
        error

      _ ->
        {:error, {:invalid_decision, decision}}
    end
  end

  @doc """
  Applies approved changes to a step.

  When a review handler returns `{:approved_with_changes, changes}`,
  this function applies those changes to the step.

  ## Parameters

  - `step` - The step to modify
  - `changes` - Map of changes to apply

  ## Supported Changes

  - `:description` - Update step description
  - `:metadata` - Merge additional metadata
  - `:interventions` - Add interventions to the step

  ## Examples

      changes = %{
        description: "Modified: " <> step.description,
        metadata: %{safety_reviewed: true},
        interventions: [%{type: :guidance, content: "Be careful"}]
      }
      
      updated_step = ClaudeCodeSDK.StepReviewHandler.apply_changes(step, changes)

  """
  @spec apply_changes(Step.t(), map()) :: Step.t()
  def apply_changes(step, changes) when is_map(changes) do
    Enum.reduce(changes, step, fn {key, value}, acc_step ->
      case key do
        :description when is_binary(value) ->
          %{acc_step | description: value}

        :metadata when is_map(value) ->
          Step.update_metadata(acc_step, value)

        :interventions when is_list(value) ->
          Enum.reduce(value, acc_step, fn intervention, s ->
            Step.add_intervention(s, intervention)
          end)

        _ ->
          # Ignore unknown changes
          acc_step
      end
    end)
  end

  ## Built-in Review Handlers

  defmodule AlwaysApprove do
    @moduledoc """
    Review handler that always approves steps.
    Useful for testing or when review is handled externally.
    """

    @behaviour ClaudeCodeSDK.StepReviewHandler

    @impl true
    def review_step(_step) do
      :approved
    end
  end

  defmodule AlwaysReject do
    @moduledoc """
    Review handler that always rejects steps.
    Useful for testing or maximum safety scenarios.
    """

    @behaviour ClaudeCodeSDK.StepReviewHandler

    @impl true
    def review_step(_step) do
      :rejected
    end
  end

  defmodule SafetyFirst do
    @moduledoc """
    Conservative review handler that rejects potentially dangerous operations.

    This handler rejects:
    - System commands
    - File deletion operations
    - Operations with unknown tools
    """

    @behaviour ClaudeCodeSDK.StepReviewHandler

    # Dangerous tools that should be rejected
    @dangerous_tools [
      "deleteFile",
      "executePwsh",
      "executeCommand",
      "rmdir",
      "rm"
    ]

    # Safe step types that are generally approved
    @safe_step_types [
      :exploration,
      :analysis,
      :communication
    ]

    @impl true
    def review_step(step) do
      cond do
        step.type in @safe_step_types ->
          :approved

        step.type == :system_command ->
          :rejected

        has_dangerous_tools?(step) ->
          :rejected

        step.type == :file_operation ->
          review_file_operation(step)

        step.type == :code_modification ->
          review_code_modification(step)

        true ->
          # Unknown step type, be conservative
          :rejected
      end
    end

    @impl true
    def handle_review_timeout(_step, _timeout_ms) do
      # Conservative default: reject on timeout
      :rejected
    end

    defp has_dangerous_tools?(step) do
      Enum.any?(step.tools_used, fn tool -> tool in @dangerous_tools end)
    end

    defp review_file_operation(step) do
      if has_dangerous_tools?(step) do
        :rejected
      else
        # Allow safe file operations
        :approved
      end
    end

    defp review_code_modification(_step) do
      # Allow code modifications but add safety metadata
      changes = %{
        metadata: %{
          safety_reviewed: true,
          review_timestamp: DateTime.utc_now()
        },
        interventions: [
          %{
            type: :guidance,
            content: "Code modification approved - please review changes carefully",
            applied_at: DateTime.utc_now()
          }
        ]
      }

      {:approved_with_changes, changes}
    end
  end

  defmodule InteractiveReviewer do
    @moduledoc """
    Review handler that prompts for interactive approval.

    This handler displays step information and waits for user input
    to make review decisions. Useful for manual review workflows.
    """

    @behaviour ClaudeCodeSDK.StepReviewHandler

    @impl true
    def review_step(step) do
      IO.puts("\n=== Step Review Required ===")
      IO.puts("Step ID: #{step.id}")
      IO.puts("Type: #{step.type}")
      IO.puts("Description: #{step.description}")
      IO.puts("Tools: #{Enum.join(step.tools_used, ", ")}")

      if not Enum.empty?(step.messages) do
        IO.puts("Messages: #{length(step.messages)} message(s)")
      end

      IO.puts("\nOptions:")
      IO.puts("  a) Approve")
      IO.puts("  r) Reject")
      IO.puts("  s) Skip (same as reject)")
      IO.puts("  q) Quit/Abort")

      case get_user_input() do
        "a" ->
          :approved

        "r" ->
          :rejected

        "s" ->
          :rejected

        "q" ->
          {:error, :user_abort}

        _ ->
          IO.puts("Invalid input, defaulting to reject")
          :rejected
      end
    end

    @impl true
    def handle_review_timeout(step, timeout_ms) do
      IO.puts("\nReview timeout (#{timeout_ms}ms) for step: #{step.id}")
      IO.puts("Defaulting to rejection for safety")
      :rejected
    end

    defp get_user_input do
      IO.gets("Enter choice (a/r/s/q): ")
      |> String.trim()
      |> String.downcase()
    end
  end
end
