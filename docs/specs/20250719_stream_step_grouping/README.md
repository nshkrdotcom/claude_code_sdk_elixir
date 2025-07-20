# Stream Step Grouping for Claude Code SDK

## Overview

This specification introduces Stream Step Grouping functionality to the Claude Code SDK, enabling structured pause/resume capabilities by organizing Claude's output into logical, reviewable steps.

## Documentation Structure

### Core Documents

1. **[Overview](./overview.md)** - Executive summary and high-level design
   - Problem statement
   - Solution concept
   - Key features
   - Benefits

2. **[Architecture](./architecture.md)** - Technical system design
   - Component structure
   - Data flow
   - Integration points
   - Performance considerations

3. **[Step Detection](./step_detection.md)** - Pattern detection algorithms
   - Detection strategies
   - Built-in patterns
   - Custom patterns
   - Testing patterns

4. **[API Reference](./api_reference.md)** - Complete API documentation
   - Main functions
   - Data types
   - Configuration options
   - Examples

5. **[Implementation Guide](./implementation_guide.md)** - Step-by-step implementation
   - Development phases
   - Code examples
   - Testing approach
   - Deployment guide

## Key Concepts

### What is Step Grouping?

Step grouping transforms Claude's raw message stream into logical "steps" - coherent units of work that can be:
- Reviewed before execution
- Paused and resumed
- Modified or skipped
- Monitored for safety

### Example Transformation

**Before (Raw Messages):**
```
Message 1: "Let me check the file structure"
Message 2: tool_use(ls)
Message 3: tool_result(...)
Message 4: "I found 3 files..."
```

**After (Grouped Step):**
```
Step 1: {
  type: :exploration,
  description: "Checking file structure",
  messages: [1, 2, 3, 4],
  tools_used: ["ls"],
  status: :completed
}
```

## Quick Start

### Basic Usage

```elixir
# Get steps instead of messages
{:ok, steps} = ClaudeCodeSDK.query_with_steps(
  "Implement a function to calculate fibonacci numbers",
  step_grouping: [enabled: true]
)

Enum.each(steps, fn step ->
  IO.puts("Step: #{step.description}")
  IO.puts("Tools: #{Enum.join(step.tools_used, ", ")}")
end)
```

### With Review Control

```elixir
{:ok, steps} = ClaudeCodeSDK.query_with_steps(prompt,
  step_control: [
    mode: :review_required,
    review_handler: fn step ->
      if safe_operation?(step), do: :approved, else: :rejected
    end
  ]
)
```

### With Manual Control

```elixir
{:ok, controller} = ClaudeCodeSDK.query_with_control(prompt,
  step_control: [mode: :manual]
)

loop do
  case StepController.next_step(controller) do
    {:ok, step} -> 
      process_step(step)
    {:paused, step} ->
      if approve?(step) do
        StepController.resume(controller, :continue)
      else
        StepController.resume(controller, :skip)
      end
    :completed ->
      break
  end
end
```

## Integration with Pipeline Safety

This step grouping feature is designed to work seamlessly with the Pipeline Safety Reviewer system:

```yaml
# In pipeline configuration
steps:
  - type: claude_code
    config:
      prompt: "Refactor the authentication module"
      step_grouping:
        enabled: true
        patterns: [:code_modification, :file_operation]
      step_control:
        mode: :review_required
        review_handler: "Pipeline.Safety.StepReviewer"
```

## Built-in Step Patterns

The system includes pre-defined patterns for common operations:

1. **File Operations** - Reading, writing, editing files
2. **Code Modifications** - Refactoring, implementing features
3. **System Commands** - Running bash commands
4. **Exploration** - Searching, browsing code
5. **Analysis** - Understanding and reviewing code

## Architecture Highlights

### Detection Pipeline
```
Messages → Pattern Matching → Step Boundaries → Buffering → Step Emission
```

### Control Flow
```
Step Stream → Controller → Review → Decision → Continue/Pause/Abort
```

## Configuration

```elixir
config = %{
  step_grouping: %{
    enabled: true,
    strategy: :pattern_based,
    patterns: :default,
    confidence_threshold: 0.7,
    buffer_timeout_ms: 5000
  },
  step_control: %{
    mode: :automatic,  # :automatic | :manual | :review_required
    pause_between_steps: false,
    review_handler: nil
  }
}
```

## Benefits

### For Safety
- Review actions before side effects occur
- Intercept and modify problematic steps
- Implement fine-grained access control

### For Debugging
- Clear execution boundaries
- Step-by-step replay capability
- Detailed logging per step

### For User Experience
- Progress tracking
- Pause/resume workflows
- Interactive guidance

## Implementation Status

This is a specification for a feature to be implemented. The implementation will follow these phases:

1. **Phase 1**: Core step detection (Week 1)
2. **Phase 2**: Pattern library (Week 2)
3. **Phase 3**: Stream processing (Week 3)
4. **Phase 4**: Control interface (Week 4)
5. **Phase 5**: Testing & refinement (Week 5)

## Next Steps

1. Review and approve the specification
2. Begin Phase 1 implementation
3. Create prototype with basic patterns
4. Test with real Claude conversations
5. Integrate with Pipeline Safety system

---

*This feature enhances the Claude Code SDK with structured execution control, enabling safer and more manageable AI-assisted development workflows.*