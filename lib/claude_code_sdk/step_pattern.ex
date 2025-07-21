defmodule ClaudeCodeSDK.StepPattern do
  @moduledoc """
  Defines patterns for detecting logical step boundaries in Claude's message stream.

  Patterns are used by the Step Detector to identify when messages should be grouped
  together into logical steps. Each pattern defines triggers (conditions that start
  a step), validators (conditions that confirm the step), and metadata about the
  pattern's behavior.

  ## Pattern Components

  - **Triggers**: Conditions that indicate the start of a new step
  - **Validators**: Conditions that confirm the step type and boundaries
  - **Priority**: Numeric priority for pattern matching (higher = more important)
  - **Confidence**: Base confidence score for matches (0.0 - 1.0)

  ## Trigger Types

  - `:message_content` - Match against message content
  - `:tool_usage` - Match against tool usage patterns
  - `:message_sequence` - Match against sequences of message types
  - `:custom_function` - Use custom function for complex matching

  ## Validator Types

  - `:content_regex` - Validate using regular expressions
  - `:tool_sequence` - Validate tool usage sequences
  - `:message_count` - Validate based on message count
  - `:custom_function` - Use custom validation function

  ## Examples

      # File operation pattern
      %ClaudeCodeSDK.StepPattern{
        id: :file_operation,
        name: "File Operations",
        triggers: [
          %{type: :tool_usage, tools: ["readFile", "fsWrite", "listDirectory"]}
        ],
        validators: [
          %{type: :tool_sequence, min_tools: 1}
        ],
        priority: 80,
        confidence: 0.9
      }

      # Code modification pattern
      %ClaudeCodeSDK.StepPattern{
        id: :code_modification,
        name: "Code Modifications",
        triggers: [
          %{type: :tool_usage, tools: ["strReplace", "fsWrite"]},
          %{type: :message_content, regex: ~r/implement|refactor|fix/i}
        ],
        validators: [
          %{type: :content_regex, regex: ~r/\.(ex|exs|js|ts|py)$/}
        ],
        priority: 85,
        confidence: 0.85
      }

  """

  defstruct [
    # Pattern identifier (atom)
    :id,
    # Human-readable name
    :name,
    # Pattern description
    :description,
    # List of trigger conditions
    :triggers,
    # List of validation rules
    :validators,
    # Pattern priority (0-100)
    :priority,
    # Base confidence score (0.0-1.0)
    :confidence
  ]

  @type trigger_type ::
          :message_content
          | :tool_usage
          | :message_sequence
          | :custom_function

  @type validator_type ::
          :content_regex
          | :tool_sequence
          | :message_count
          | :custom_function

  @type trigger :: %{
          type: trigger_type(),
          tools: [String.t()] | nil,
          regex: Regex.t() | nil,
          sequence: [atom()] | nil,
          function: (any() -> boolean()) | nil,
          options: map()
        }

  @type validator :: %{
          type: validator_type(),
          regex: Regex.t() | nil,
          min_tools: integer() | nil,
          max_tools: integer() | nil,
          min_messages: integer() | nil,
          max_messages: integer() | nil,
          function: (any() -> boolean()) | nil,
          options: map()
        }

  @type t :: %__MODULE__{
          id: atom(),
          name: String.t(),
          description: String.t(),
          triggers: [trigger()],
          validators: [validator()],
          priority: integer(),
          confidence: float()
        }

  @doc """
  Creates a new step pattern with the given parameters.

  ## Parameters

  - `opts` - Keyword list of pattern options

  ## Options

  - `:id` - Pattern identifier (required)
  - `:name` - Human-readable name (required)
  - `:description` - Pattern description
  - `:triggers` - List of trigger conditions (required)
  - `:validators` - List of validation rules (defaults to empty list)
  - `:priority` - Pattern priority 0-100 (defaults to 50)
  - `:confidence` - Base confidence 0.0-1.0 (defaults to 0.5)

  ## Examples

      iex> ClaudeCodeSDK.StepPattern.new(
      ...>   id: :test_pattern,
      ...>   name: "Test Pattern",
      ...>   triggers: [%{type: :tool_usage, tools: ["readFile"]}]
      ...> )
      %ClaudeCodeSDK.StepPattern{
        id: :test_pattern,
        name: "Test Pattern",
        triggers: [%{type: :tool_usage, tools: ["readFile"]}]
      }

  """
  @spec new(keyword()) :: t()
  def new(opts) do
    unless Keyword.has_key?(opts, :id) do
      raise ArgumentError, "Pattern :id is required"
    end

    unless Keyword.has_key?(opts, :name) do
      raise ArgumentError, "Pattern :name is required"
    end

    unless Keyword.has_key?(opts, :triggers) do
      raise ArgumentError, "Pattern :triggers is required"
    end

    %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      name: Keyword.fetch!(opts, :name),
      description: Keyword.get(opts, :description, ""),
      triggers: Keyword.fetch!(opts, :triggers),
      validators: Keyword.get(opts, :validators, []),
      priority: Keyword.get(opts, :priority, 50),
      confidence: Keyword.get(opts, :confidence, 0.5)
    }
  end

  @doc """
  Creates a trigger condition for message content matching.

  ## Parameters

  - `regex` - Regular expression to match against message content
  - `opts` - Additional options

  ## Examples

      iex> ClaudeCodeSDK.StepPattern.content_trigger(~r/implement/i)
      %{type: :message_content, regex: ~r/implement/i, options: %{}}

  """
  @spec content_trigger(Regex.t(), map()) :: trigger()
  def content_trigger(regex, opts \\ %{}) do
    %{
      type: :message_content,
      regex: regex,
      tools: nil,
      sequence: nil,
      function: nil,
      options: opts
    }
  end

  @doc """
  Creates a trigger condition for tool usage matching.

  ## Parameters

  - `tools` - List of tool names to match
  - `opts` - Additional options

  ## Examples

      iex> ClaudeCodeSDK.StepPattern.tool_trigger(["readFile", "fsWrite"])
      %{type: :tool_usage, tools: ["readFile", "fsWrite"], options: %{}}

  """
  @spec tool_trigger([String.t()], map()) :: trigger()
  def tool_trigger(tools, opts \\ %{}) when is_list(tools) do
    %{
      type: :tool_usage,
      tools: tools,
      regex: nil,
      sequence: nil,
      function: nil,
      options: opts
    }
  end

  @doc """
  Creates a trigger condition for message sequence matching.

  ## Parameters

  - `sequence` - List of message types to match in sequence
  - `opts` - Additional options

  ## Examples

      iex> ClaudeCodeSDK.StepPattern.sequence_trigger([:assistant, :user])
      %{type: :message_sequence, sequence: [:assistant, :user], options: %{}}

  """
  @spec sequence_trigger([atom()], map()) :: trigger()
  def sequence_trigger(sequence, opts \\ %{}) when is_list(sequence) do
    %{
      type: :message_sequence,
      sequence: sequence,
      tools: nil,
      regex: nil,
      function: nil,
      options: opts
    }
  end

  @doc """
  Creates a trigger condition using a custom function.

  ## Parameters

  - `function` - Function that takes context and returns boolean
  - `opts` - Additional options

  ## Examples

      iex> trigger_fn = fn _context -> true end
      iex> ClaudeCodeSDK.StepPattern.custom_trigger(trigger_fn)
      %{type: :custom_function, function: trigger_fn, options: %{}}

  """
  @spec custom_trigger((any() -> boolean()), map()) :: trigger()
  def custom_trigger(function, opts \\ %{}) when is_function(function, 1) do
    %{
      type: :custom_function,
      function: function,
      tools: nil,
      regex: nil,
      sequence: nil,
      options: opts
    }
  end

  @doc """
  Creates a validator for content regex matching.

  ## Parameters

  - `regex` - Regular expression to validate against
  - `opts` - Additional options

  ## Examples

      iex> ClaudeCodeSDK.StepPattern.content_validator(~r/\\.ex$/)
      %{type: :content_regex, regex: ~r/\\.ex$/, options: %{}}

  """
  @spec content_validator(Regex.t(), map()) :: validator()
  def content_validator(regex, opts \\ %{}) do
    %{
      type: :content_regex,
      regex: regex,
      min_tools: nil,
      max_tools: nil,
      min_messages: nil,
      max_messages: nil,
      function: nil,
      options: opts
    }
  end

  @doc """
  Creates a validator for tool sequence requirements.

  ## Parameters

  - `opts` - Validation options

  ## Options

  - `:min_tools` - Minimum number of tools required
  - `:max_tools` - Maximum number of tools allowed

  ## Examples

      iex> ClaudeCodeSDK.StepPattern.tool_validator(min_tools: 1, max_tools: 5)
      %{type: :tool_sequence, min_tools: 1, max_tools: 5, options: %{}}

  """
  @spec tool_validator(keyword()) :: validator()
  def tool_validator(opts \\ []) do
    %{
      type: :tool_sequence,
      regex: nil,
      min_tools: Keyword.get(opts, :min_tools),
      max_tools: Keyword.get(opts, :max_tools),
      min_messages: nil,
      max_messages: nil,
      function: nil,
      options: Keyword.get(opts, :options, %{})
    }
  end

  @doc """
  Creates a validator for message count requirements.

  ## Parameters

  - `opts` - Validation options

  ## Options

  - `:min_messages` - Minimum number of messages required
  - `:max_messages` - Maximum number of messages allowed

  ## Examples

      iex> ClaudeCodeSDK.StepPattern.message_validator(min_messages: 2)
      %{type: :message_count, min_messages: 2, options: %{}}

  """
  @spec message_validator(keyword()) :: validator()
  def message_validator(opts \\ []) do
    %{
      type: :message_count,
      regex: nil,
      min_tools: nil,
      max_tools: nil,
      min_messages: Keyword.get(opts, :min_messages),
      max_messages: Keyword.get(opts, :max_messages),
      function: nil,
      options: Keyword.get(opts, :options, %{})
    }
  end

  @doc """
  Creates a validator using a custom function.

  ## Parameters

  - `function` - Function that takes context and returns boolean
  - `opts` - Additional options

  ## Examples

      iex> validator_fn = fn _context -> true end
      iex> ClaudeCodeSDK.StepPattern.custom_validator(validator_fn)
      %{type: :custom_function, function: validator_fn, options: %{}}

  """
  @spec custom_validator((any() -> boolean()), map()) :: validator()
  def custom_validator(function, opts \\ %{}) when is_function(function, 1) do
    %{
      type: :custom_function,
      regex: nil,
      min_tools: nil,
      max_tools: nil,
      min_messages: nil,
      max_messages: nil,
      function: function,
      options: opts
    }
  end

  @doc """
  Gets the default built-in patterns for step detection.

  ## Returns

  List of built-in step patterns.

  ## Examples

      iex> patterns = ClaudeCodeSDK.StepPattern.default_patterns()
      iex> Enum.find(patterns, & &1.id == :file_operation)
      %ClaudeCodeSDK.StepPattern{id: :file_operation, name: "File Operations"}

  """
  @spec default_patterns() :: [t()]
  def default_patterns do
    [
      # File operation pattern - highest priority for clear file operations
      new(
        id: :file_operation,
        name: "File Operations",
        description: "Reading, writing, or editing files",
        triggers: [
          tool_trigger(["readFile", "fsWrite", "fsAppend", "listDirectory", "deleteFile"])
        ],
        validators: [
          tool_validator(min_tools: 1)
        ],
        priority: 90,
        confidence: 0.95
      ),

      # Code modification pattern - high priority for code changes
      new(
        id: :code_modification,
        name: "Code Modifications",
        description: "Refactoring, implementing, or fixing code",
        triggers: [
          tool_trigger(["strReplace", "fsWrite"]),
          content_trigger(~r/implement|refactor|fix|update.*code/i)
        ],
        validators: [
          content_validator(~r/\.(ex|exs|js|ts|py|rb|java|cpp|c|h)$/),
          tool_validator(min_tools: 1)
        ],
        priority: 85,
        confidence: 0.9
      ),

      # System command pattern - high priority for shell operations
      new(
        id: :system_command,
        name: "System Commands",
        description: "Running bash or shell commands",
        triggers: [
          tool_trigger(["executePwsh"]),
          content_trigger(~r/run|execute|command|shell|bash/i)
        ],
        validators: [
          tool_validator(min_tools: 1)
        ],
        priority: 80,
        confidence: 0.9
      ),

      # Exploration pattern - medium priority for discovery operations
      new(
        id: :exploration,
        name: "Code Exploration",
        description: "Searching, browsing, or discovering code structure",
        triggers: [
          tool_trigger(["grepSearch", "fileSearch", "listDirectory"]),
          content_trigger(~r/search|find|explore|browse|discover/i)
        ],
        validators: [
          tool_validator(min_tools: 1)
        ],
        priority: 70,
        confidence: 0.8
      ),

      # Analysis pattern - medium priority for understanding operations
      new(
        id: :analysis,
        name: "Code Analysis",
        description: "Understanding, reviewing, or analyzing code",
        triggers: [
          tool_trigger(["readFile", "readMultipleFiles"]),
          content_trigger(~r/analyze|review|understand|examine|inspect/i)
        ],
        validators: [
          message_validator(min_messages: 2),
          tool_validator(min_tools: 1)
        ],
        priority: 60,
        confidence: 0.75
      ),

      # Communication pattern - lowest priority for general communication
      new(
        id: :communication,
        name: "Communication",
        description: "General communication or explanation",
        triggers: [
          content_trigger(~r/explain|describe|tell|show|help/i)
        ],
        validators: [
          message_validator(min_messages: 1)
        ],
        priority: 30,
        confidence: 0.6
      )
    ]
  end

  @doc """
  Validates a pattern structure.

  ## Parameters

  - `pattern` - The pattern to validate

  ## Returns

  `:ok` if valid, `{:error, reason}` if invalid.

  ## Examples

      iex> pattern = ClaudeCodeSDK.StepPattern.new(
      ...>   id: :test,
      ...>   name: "Test",
      ...>   triggers: [%{type: :tool_usage, tools: ["readFile"]}]
      ...> )
      iex> ClaudeCodeSDK.StepPattern.validate(pattern)
      :ok

  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = pattern) do
    with :ok <- validate_id(pattern.id),
         :ok <- validate_name(pattern.name),
         :ok <- validate_triggers(pattern.triggers),
         :ok <- validate_validators(pattern.validators),
         :ok <- validate_priority(pattern.priority),
         :ok <- validate_confidence(pattern.confidence) do
      :ok
    end
  end

  # Private validation functions
  defp validate_id(id) when is_atom(id), do: :ok
  defp validate_id(_), do: {:error, "Pattern id must be an atom"}

  defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_name(_), do: {:error, "Pattern name must be a non-empty string"}

  defp validate_triggers(triggers) when is_list(triggers) and length(triggers) > 0 do
    Enum.reduce_while(triggers, :ok, fn trigger, :ok ->
      case validate_trigger(trigger) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_triggers(_), do: {:error, "Pattern must have at least one trigger"}

  defp validate_validators(validators) when is_list(validators) do
    Enum.reduce_while(validators, :ok, fn validator, :ok ->
      case validate_validator(validator) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_validators(_), do: {:error, "Validators must be a list"}

  defp validate_priority(priority)
       when is_integer(priority) and priority >= 0 and priority <= 100,
       do: :ok

  defp validate_priority(_), do: {:error, "Priority must be an integer between 0 and 100"}

  defp validate_confidence(confidence)
       when is_float(confidence) and confidence >= 0.0 and confidence <= 1.0,
       do: :ok

  defp validate_confidence(_), do: {:error, "Confidence must be a float between 0.0 and 1.0"}

  defp validate_trigger(%{type: type})
       when type in [:message_content, :tool_usage, :message_sequence, :custom_function],
       do: :ok

  defp validate_trigger(_), do: {:error, "Invalid trigger type"}

  defp validate_validator(%{type: type})
       when type in [:content_regex, :tool_sequence, :message_count, :custom_function],
       do: :ok

  defp validate_validator(_), do: {:error, "Invalid validator type"}
end
