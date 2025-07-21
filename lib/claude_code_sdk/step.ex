defmodule ClaudeCodeSDK.Step do
  @moduledoc """
  Represents a logical step in Claude's processing workflow.

  A step groups related messages and tool uses into a cohesive unit that can be
  reviewed, paused, or controlled as a single operation. Steps provide structure
  to Claude's output stream, enabling better observability and control.

  ## Step Types

  - `:file_operation` - Reading, writing, or editing files
  - `:code_modification` - Refactoring, implementing, or fixing code
  - `:system_command` - Running bash or shell commands
  - `:exploration` - Searching, browsing, or discovering code structure
  - `:analysis` - Understanding, reviewing, or analyzing code
  - `:communication` - General communication or explanation
  - `:unknown` - Unclassified step type

  ## Step Status

  - `:in_progress` - Step is currently being processed
  - `:completed` - Step completed successfully
  - `:timeout` - Step timed out before completion
  - `:aborted` - Step was manually aborted
  - `:error` - Step encountered an error

  ## Review Status

  - `:pending` - Awaiting review
  - `:approved` - Approved for execution
  - `:rejected` - Rejected, should be skipped

  ## Examples

      # File operation step
      %ClaudeCodeSDK.Step{
        id: "step-001",
        type: :file_operation,
        description: "Reading configuration files",
        messages: [message1, message2],
        tools_used: ["readFile", "listDirectory"],
        status: :completed
      }

      # Code modification step
      %ClaudeCodeSDK.Step{
        id: "step-002",
        type: :code_modification,
        description: "Implementing user authentication",
        messages: [message3, message4, message5],
        tools_used: ["strReplace", "fsWrite"],
        status: :in_progress,
        review_status: :pending
      }

  """

  alias ClaudeCodeSDK.Message

  @derive Jason.Encoder
  defstruct [
    # Unique step identifier
    :id,
    # Step type atom
    :type,
    # Human-readable description
    :description,
    # List of Message structs in this step
    :messages,
    # List of tool names used
    :tools_used,
    # Start timestamp
    :started_at,
    # Completion timestamp
    :completed_at,
    # Step status atom
    :status,
    # Additional step-specific data
    :metadata,
    # Review status atom
    :review_status,
    # List of applied interventions
    :interventions
  ]

  @type step_type ::
          :file_operation
          | :code_modification
          | :system_command
          | :exploration
          | :analysis
          | :communication
          | :unknown

  @type step_status ::
          :in_progress
          | :completed
          | :timeout
          | :aborted
          | :error

  @type review_status ::
          :pending
          | :approved
          | :rejected

  @type intervention :: %{
          id: String.t(),
          type: :guidance | :correction | :context,
          content: String.t(),
          applied_at: DateTime.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          type: step_type(),
          description: String.t(),
          messages: [Message.t()],
          tools_used: [String.t()],
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          status: step_status(),
          metadata: map(),
          review_status: review_status() | nil,
          interventions: [intervention()]
        }

  @doc """
  Creates a new step with the given parameters.

  ## Parameters

  - `opts` - Keyword list of step options

  ## Options

  - `:id` - Unique identifier (generated if not provided)
  - `:type` - Step type (defaults to `:unknown`)
  - `:description` - Human-readable description
  - `:messages` - List of messages (defaults to empty list)
  - `:tools_used` - List of tool names (defaults to empty list)
  - `:metadata` - Additional metadata (defaults to empty map)

  ## Examples

      iex> ClaudeCodeSDK.Step.new(type: :file_operation, description: "Reading files")
      %ClaudeCodeSDK.Step{
        id: "step-" <> _,
        type: :file_operation,
        description: "Reading files",
        status: :in_progress
      }

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      type: Keyword.get(opts, :type, :unknown),
      description: Keyword.get(opts, :description, ""),
      messages: Keyword.get(opts, :messages, []),
      tools_used: Keyword.get(opts, :tools_used, []),
      started_at: Keyword.get(opts, :started_at, now),
      completed_at: nil,
      status: Keyword.get(opts, :status, :in_progress),
      metadata: Keyword.get(opts, :metadata, %{}),
      review_status: Keyword.get(opts, :review_status),
      interventions: Keyword.get(opts, :interventions, [])
    }
  end

  @doc """
  Adds a message to the step.

  ## Parameters

  - `step` - The step to add the message to
  - `message` - The message to add

  ## Returns

  Updated step with the message added.

  ## Examples

      iex> step = ClaudeCodeSDK.Step.new()
      iex> message = %ClaudeCodeSDK.Message{type: :assistant}
      iex> ClaudeCodeSDK.Step.add_message(step, message)
      %ClaudeCodeSDK.Step{messages: [message]}

  """
  @spec add_message(t(), Message.t()) :: t()
  def add_message(%__MODULE__{messages: messages} = step, %Message{} = message) do
    %{step | messages: messages ++ [message]}
  end

  @doc """
  Adds a tool to the list of tools used in this step.

  ## Parameters

  - `step` - The step to add the tool to
  - `tool_name` - Name of the tool used

  ## Returns

  Updated step with the tool added (if not already present).

  ## Examples

      iex> step = ClaudeCodeSDK.Step.new()
      iex> ClaudeCodeSDK.Step.add_tool(step, "readFile")
      %ClaudeCodeSDK.Step{tools_used: ["readFile"]}

  """
  @spec add_tool(t(), String.t()) :: t()
  def add_tool(%__MODULE__{tools_used: tools} = step, tool_name) when is_binary(tool_name) do
    if tool_name in tools do
      step
    else
      %{step | tools_used: tools ++ [tool_name]}
    end
  end

  @doc """
  Marks the step as completed.

  ## Parameters

  - `step` - The step to complete

  ## Returns

  Updated step with completed status and timestamp.

  ## Examples

      iex> step = ClaudeCodeSDK.Step.new()
      iex> completed_step = ClaudeCodeSDK.Step.complete(step)
      iex> completed_step.status
      :completed

  """
  @spec complete(t()) :: t()
  def complete(%__MODULE__{} = step) do
    %{step | status: :completed, completed_at: DateTime.utc_now()}
  end

  @doc """
  Marks the step as aborted.

  ## Parameters

  - `step` - The step to abort

  ## Returns

  Updated step with aborted status and timestamp.

  """
  @spec abort(t()) :: t()
  def abort(%__MODULE__{} = step) do
    %{step | status: :aborted, completed_at: DateTime.utc_now()}
  end

  @doc """
  Marks the step as timed out.

  ## Parameters

  - `step` - The step to mark as timed out

  ## Returns

  Updated step with timeout status and timestamp.

  """
  @spec timeout(t()) :: t()
  def timeout(%__MODULE__{} = step) do
    %{step | status: :timeout, completed_at: DateTime.utc_now()}
  end

  @doc """
  Sets the review status of the step.

  ## Parameters

  - `step` - The step to update
  - `status` - The review status to set

  ## Returns

  Updated step with the new review status.

  ## Examples

      iex> step = ClaudeCodeSDK.Step.new()
      iex> ClaudeCodeSDK.Step.set_review_status(step, :approved)
      %ClaudeCodeSDK.Step{review_status: :approved}

  """
  @spec set_review_status(t(), review_status()) :: t()
  def set_review_status(%__MODULE__{} = step, status)
      when status in [:pending, :approved, :rejected] do
    %{step | review_status: status}
  end

  @doc """
  Adds an intervention to the step.

  ## Parameters

  - `step` - The step to add the intervention to
  - `intervention` - The intervention to add

  ## Returns

  Updated step with the intervention added.

  ## Examples

      iex> step = ClaudeCodeSDK.Step.new()
      iex> intervention = %{type: :guidance, content: "Be careful", applied_at: DateTime.utc_now()}
      iex> ClaudeCodeSDK.Step.add_intervention(step, intervention)
      %ClaudeCodeSDK.Step{interventions: [intervention]}

  """
  @spec add_intervention(t(), intervention()) :: t()
  def add_intervention(%__MODULE__{interventions: interventions} = step, intervention) do
    %{step | interventions: interventions ++ [intervention]}
  end

  @doc """
  Updates the step metadata.

  ## Parameters

  - `step` - The step to update
  - `metadata` - Map of metadata to merge

  ## Returns

  Updated step with merged metadata.

  ## Examples

      iex> step = ClaudeCodeSDK.Step.new()
      iex> ClaudeCodeSDK.Step.update_metadata(step, %{confidence: 0.8})
      %ClaudeCodeSDK.Step{metadata: %{confidence: 0.8}}

  """
  @spec update_metadata(t(), map()) :: t()
  def update_metadata(%__MODULE__{metadata: existing} = step, new_metadata)
      when is_map(new_metadata) do
    %{step | metadata: Map.merge(existing, new_metadata)}
  end

  @doc """
  Checks if the step is completed (any final status).

  ## Parameters

  - `step` - The step to check

  ## Returns

  `true` if the step has a final status, `false` otherwise.

  ## Examples

      iex> step = ClaudeCodeSDK.Step.new(status: :completed)
      iex> ClaudeCodeSDK.Step.completed?(step)
      true

      iex> step = ClaudeCodeSDK.Step.new(status: :in_progress)
      iex> ClaudeCodeSDK.Step.completed?(step)
      false

  """
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{status: status}) do
    status in [:completed, :timeout, :aborted, :error]
  end

  @doc """
  Checks if the step is approved for execution.

  ## Parameters

  - `step` - The step to check

  ## Returns

  `true` if the step is approved or has no review status, `false` otherwise.

  """
  @spec approved?(t()) :: boolean()
  def approved?(%__MODULE__{review_status: nil}), do: true
  def approved?(%__MODULE__{review_status: :approved}), do: true
  def approved?(%__MODULE__{review_status: _}), do: false

  @doc """
  Gets the duration of the step in milliseconds.

  ## Parameters

  - `step` - The step to calculate duration for

  ## Returns

  Duration in milliseconds, or `nil` if not completed.

  ## Examples

      iex> started = DateTime.utc_now()
      iex> completed = DateTime.add(started, 1000, :millisecond)
      iex> step = %ClaudeCodeSDK.Step{started_at: started, completed_at: completed}
      iex> ClaudeCodeSDK.Step.duration_ms(step)
      1000

  """
  @spec duration_ms(t()) :: integer() | nil
  def duration_ms(%__MODULE__{started_at: nil}), do: nil
  def duration_ms(%__MODULE__{completed_at: nil}), do: nil

  def duration_ms(%__MODULE__{started_at: started, completed_at: completed}) do
    DateTime.diff(completed, started, :millisecond)
  end

  @doc """
  Converts the step to a summary map for logging or display.

  ## Parameters

  - `step` - The step to summarize

  ## Returns

  Map containing step summary information.

  ## Examples

      iex> step = ClaudeCodeSDK.Step.new(type: :file_operation, description: "Reading files")
      iex> summary = ClaudeCodeSDK.Step.to_summary(step)
      iex> summary.type
      :file_operation

  """
  @spec to_summary(t()) :: map()
  def to_summary(%__MODULE__{} = step) do
    %{
      id: step.id,
      type: step.type,
      description: step.description,
      status: step.status,
      review_status: step.review_status,
      message_count: length(step.messages),
      tools_used: step.tools_used,
      duration_ms: duration_ms(step),
      started_at: step.started_at,
      completed_at: step.completed_at
    }
  end

  # Private helper to generate unique step IDs
  defp generate_id do
    "step-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
