# Stream Step Grouping - API Reference

## Overview

This document provides the complete API reference for the Stream Step Grouping feature in Claude Code SDK.

## Main API

### ClaudeCodeSDK.query_with_steps/2

Executes a query and returns a stream of grouped steps instead of individual messages.

```elixir
@spec query_with_steps(prompt :: String.t(), options :: keyword()) :: 
  {:ok, Enumerable.t()} | {:error, term()}
```

#### Parameters

- `prompt` - The prompt to send to Claude
- `options` - Configuration options including step grouping settings

#### Options

```elixir
options = [
  # Standard Claude options
  model: "claude-3-opus-20240229",
  max_tokens: 4096,
  temperature: 0.7,
  
  # Step grouping options
  step_grouping: [
    enabled: true,
    strategy: :pattern_based,  # :pattern_based | :ml_based | :custom
    patterns: :default,        # :default | :all | [pattern_ids] | custom_patterns
    buffer_timeout_ms: 5000,
    confidence_threshold: 0.7
  ],
  
  # Step control options
  step_control: [
    mode: :automatic,          # :automatic | :manual | :review_required
    pause_between_steps: false,
    review_handler: &review_function/1,
    intervention_handler: &intervention_function/1
  ],
  
  # State management options
  state_management: [
    persist_steps: true,
    persistence_adapter: MyPersistenceAdapter,
    max_step_history: 100
  ]
]
```

#### Example

```elixir
{:ok, step_stream} = ClaudeCodeSDK.query_with_steps(
  "Implement a TODO list application",
  step_grouping: [enabled: true],
  step_control: [mode: :manual]
)

Enum.each(step_stream, fn step ->
  IO.puts("Step: #{step.description}")
  IO.puts("Tools used: #{Enum.join(step.tools_used, ", ")}")
  
  # Review step if needed
  case review_step(step) do
    :continue -> :ok
    :pause -> wait_for_user_input()
    :abort -> break
  end
end)
```

### ClaudeCodeSDK.StepStream.transform/2

Transforms an existing message stream into a step stream.

```elixir
@spec transform(message_stream :: Enumerable.t(), options :: keyword()) :: 
  Enumerable.t()
```

#### Parameters

- `message_stream` - A stream of Claude messages
- `options` - Step grouping configuration

#### Example

```elixir
# Get raw message stream
{:ok, message_stream} = ClaudeCodeSDK.query_stream("Read all config files")

# Transform to steps
step_stream = ClaudeCodeSDK.StepStream.transform(message_stream,
  strategy: :pattern_based,
  patterns: [:file_operation, :code_modification]
)
```

## Step Controller API

### ClaudeCodeSDK.StepController

Manages step execution flow with pause/resume capabilities.

#### start_link/2

Starts a step controller process.

```elixir
@spec start_link(step_stream :: Enumerable.t(), options :: keyword()) :: 
  {:ok, pid()} | {:error, term()}
```

#### next_step/2

Gets the next step, applying control logic.

```elixir
@spec next_step(controller :: pid(), timeout :: timeout()) :: 
  {:ok, Step.t()} | 
  {:paused, Step.t()} | 
  {:awaiting_review, Step.t()} |
  {:intervention_required, intervention()} |
  :completed |
  {:error, term()}
```

#### resume/2

Resumes execution after a pause.

```elixir
@spec resume(controller :: pid(), decision :: decision()) :: 
  :ok | {:error, term()}

@type decision :: :continue | :skip | :abort | {:intervene, String.t()}
```

#### inject_intervention/2

Injects an intervention before the next step.

```elixir
@spec inject_intervention(controller :: pid(), intervention :: intervention()) :: 
  :ok | {:error, term()}

@type intervention :: %{
  type: :guidance | :correction | :context,
  content: String.t(),
  metadata: map()
}
```

#### Example

```elixir
# Start controller with manual control
{:ok, controller} = StepController.start_link(step_stream,
  control_mode: :manual,
  review_handler: &my_review_handler/1
)

# Process steps with control
loop do
  case StepController.next_step(controller) do
    {:ok, step} ->
      process_step(step)
      
    {:paused, step} ->
      IO.puts("Step paused: #{step.description}")
      user_decision = get_user_decision()
      StepController.resume(controller, user_decision)
      
    {:awaiting_review, step} ->
      # Review handler will be called automatically
      :ok
      
    :completed ->
      break
  end
end
```

## State Manager API

### ClaudeCodeSDK.StateManager

Manages conversation state and step history.

#### start_link/1

```elixir
@spec start_link(options :: keyword()) :: {:ok, pid()} | {:error, term()}
```

#### save_step/2

Saves a step to history.

```elixir
@spec save_step(manager :: pid(), step :: Step.t()) :: :ok | {:error, term()}
```

#### get_history/1

Retrieves step history.

```elixir
@spec get_history(manager :: pid()) :: [Step.t()]
```

#### create_checkpoint/2

Creates a checkpoint at the current position.

```elixir
@spec create_checkpoint(manager :: pid(), label :: String.t()) :: 
  {:ok, checkpoint()} | {:error, term()}
```

#### restore_checkpoint/2

Restores to a previous checkpoint.

```elixir
@spec restore_checkpoint(manager :: pid(), checkpoint_id :: String.t()) :: 
  :ok | {:error, term()}
```

## Data Types

### Step

```elixir
defmodule ClaudeCodeSDK.Step do
  @type t :: %__MODULE__{
    id: String.t(),
    type: step_type(),
    description: String.t(),
    messages: [Message.t()],
    tools_used: [String.t()],
    started_at: DateTime.t(),
    completed_at: DateTime.t() | nil,
    status: step_status(),
    metadata: map(),
    review_status: review_status() | nil,
    interventions: [intervention()]
  }
  
  @type step_type :: 
    :file_operation |
    :code_modification |
    :system_command |
    :exploration |
    :analysis |
    :custom
    
  @type step_status :: :in_progress | :completed | :timeout | :aborted
  
  @type review_status :: :pending | :approved | :rejected | :modified
end
```

### Pattern

```elixir
defmodule ClaudeCodeSDK.StepDetector.Pattern do
  @type t :: %{
    id: atom(),
    name: String.t(),
    description: String.t(),
    triggers: [trigger()],
    validators: [validator()],
    priority: integer(),
    confidence: float()
  }
  
  @type trigger :: 
    {:message_text, Regex.t()} |
    {:tool_use, String.t() | :any} |
    {:tool_sequence, [String.t()]} |
    {:message_count, integer()} |
    {:time_gap, integer()}
    
  @type validator ::
    {:has_tool_use, boolean()} |
    {:has_tool_result, boolean()} |
    {:min_messages, integer()} |
    {:max_messages, integer()} |
    {:contains_text, Regex.t()}
end
```

## Review Handler Interface

Review handlers must implement the following function signature:

```elixir
@spec review_handler(step :: Step.t()) :: review_decision()

@type review_decision :: 
  :approved |
  :rejected |
  {:pause, reason :: String.t()} |
  {:modify, modifications :: map()} |
  {:intervene, intervention :: intervention()} |
  :abort
```

### Example Review Handler

```elixir
def my_review_handler(step) do
  cond do
    # Auto-approve read operations
    step.type == :file_operation && only_uses_tool?(step, "read") ->
      :approved
      
    # Pause for file modifications
    uses_tool?(step, "write") || uses_tool?(step, "edit") ->
      {:pause, "File modification requires approval"}
      
    # Reject dangerous operations
    uses_tool?(step, "rm") && step.messages =~ ~r/-rf/ ->
      :rejected
      
    # Default to approved
    true ->
      :approved
  end
end
```

## Intervention Handler Interface

```elixir
@spec intervention_handler(
  step :: Step.t(), 
  intervention :: intervention()
) :: :ok | {:error, term()}
```

### Example Intervention Handler

```elixir
def my_intervention_handler(step, intervention) do
  case intervention.type do
    :guidance ->
      # Inject guidance message
      inject_message(intervention.content)
      
    :correction ->
      # Modify the step
      modify_step(step, intervention.metadata.modifications)
      
    :context ->
      # Update context
      update_context(intervention.metadata.context_updates)
  end
end
```

## Persistence Adapter Interface

Custom persistence adapters must implement:

```elixir
defmodule MyPersistenceAdapter do
  @behaviour ClaudeCodeSDK.StateManager.PersistenceAdapter
  
  @impl true
  def save_step(conversation_id, step) do
    # Save to database/file/etc
    :ok
  end
  
  @impl true
  def load_steps(conversation_id) do
    # Load from storage
    {:ok, []}
  end
  
  @impl true
  def save_checkpoint(conversation_id, checkpoint) do
    # Save checkpoint
    :ok
  end
  
  @impl true
  def load_checkpoint(conversation_id, checkpoint_id) do
    # Load checkpoint
    {:ok, checkpoint}
  end
end
```

## Stream Processing Functions

### Utility Functions

```elixir
# Filter steps by type
step_stream
|> ClaudeCodeSDK.StepStream.filter_by_type([:file_operation, :code_modification])

# Map over steps
step_stream
|> ClaudeCodeSDK.StepStream.map(fn step ->
  %{step | metadata: Map.put(step.metadata, :reviewed, true)}
end)

# Take steps until condition
step_stream
|> ClaudeCodeSDK.StepStream.take_until(fn step ->
  step.type == :completed
end)

# Batch steps
step_stream
|> ClaudeCodeSDK.StepStream.batch(5)

# Add timeout to steps
step_stream
|> ClaudeCodeSDK.StepStream.with_timeout(30_000)
```

## Error Handling

### Common Errors

```elixir
{:error, :detection_timeout} 
# Step detection timed out

{:error, :invalid_pattern}
# Invalid pattern configuration

{:error, :controller_timeout}
# Controller operation timed out

{:error, {:review_handler_error, reason}}
# Review handler raised an error

{:error, :conversation_aborted}
# Conversation was aborted
```

### Error Recovery

```elixir
case ClaudeCodeSDK.query_with_steps(prompt, opts) do
  {:ok, stream} ->
    process_stream(stream)
    
  {:error, :detection_timeout} ->
    # Fall back to message-based processing
    {:ok, messages} = ClaudeCodeSDK.query(prompt, opts)
    process_messages(messages)
    
  {:error, reason} ->
    Logger.error("Step grouping failed: #{inspect(reason)}")
    {:error, reason}
end
```

## Configuration Examples

### Development Configuration

```elixir
dev_config = [
  step_grouping: [
    enabled: true,
    strategy: :pattern_based,
    patterns: :all,
    buffer_timeout_ms: 10_000,
    confidence_threshold: 0.6
  ],
  step_control: [
    mode: :automatic,
    pause_between_steps: false
  ],
  state_management: [
    persist_steps: false
  ]
]
```

### Production Configuration

```elixir
prod_config = [
  step_grouping: [
    enabled: true,
    strategy: :pattern_based,
    patterns: [:file_operation, :code_modification, :system_command],
    buffer_timeout_ms: 5_000,
    confidence_threshold: 0.8
  ],
  step_control: [
    mode: :review_required,
    pause_between_steps: true,
    review_handler: &ProductionReviewer.review/1,
    intervention_handler: &ProductionIntervenor.handle/2
  ],
  state_management: [
    persist_steps: true,
    persistence_adapter: DatabaseAdapter,
    max_step_history: 1000
  ]
]
```

### Testing Configuration

```elixir
test_config = [
  step_grouping: [
    enabled: true,
    strategy: :pattern_based,
    patterns: [
      %{
        id: :test_pattern,
        triggers: [{:message_text, ~r/test/}],
        validators: [{:min_messages, 1}]
      }
    ],
    buffer_timeout_ms: 100,
    confidence_threshold: 0.5
  ],
  step_control: [
    mode: :manual
  ]
]
```

## Debugging and Monitoring

### Enable Debug Logging

```elixir
# In config/config.exs
config :claude_code_sdk, :step_grouping,
  debug: true,
  log_level: :debug
```

### Step Metrics

```elixir
# Get step detection metrics
metrics = ClaudeCodeSDK.StepDetector.Metrics.get_metrics()

%{
  total_messages_processed: 1523,
  steps_detected: 87,
  average_step_size: 17.5,
  detection_accuracy: 0.94,
  average_detection_time_ms: 2.3
}
```

### Step Visualization

```elixir
# Visualize step structure
ClaudeCodeSDK.StepStream.visualize(step_stream)

# Output:
# Step 1: File Operation (4 messages, 2.3s)
#   └─ Tools: read
# Step 2: Code Modification (6 messages, 5.1s)
#   └─ Tools: edit, write
# Step 3: System Command (3 messages, 1.2s)
#   └─ Tools: bash
```