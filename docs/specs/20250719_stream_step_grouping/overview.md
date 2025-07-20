# Stream Step Grouping for Claude Code SDK - Overview

## Executive Summary

This specification outlines the design for enhancing the Claude Code SDK with stream step grouping functionality. This feature will enable structured pause/resume capabilities by organizing Claude's output into logical, reviewable steps that can be intercepted, reviewed, and controlled by external systems like the Pipeline Safety Reviewer.

## Problem Statement

The current Claude Code SDK operates in two modes:

1. **Synchronous**: Collects all output before returning
2. **Asynchronous**: Streams messages in real-time

Neither mode provides the ability to:
- Pause execution between logical steps
- Review actions before they complete
- Resume from specific points in a conversation
- Intervene during multi-step operations

This limitation makes it difficult to implement safety controls, step-by-step review processes, or interactive debugging.

## Solution Overview

### Core Concept: Logical Step Detection

Transform the raw message stream into a stream of logical "steps" where each step represents:
- A complete action or thought process
- One or more related tool uses
- Clear beginning and end boundaries
- Reviewable/pauseable execution points

### Example Transformation

**Before (Raw Messages):**
```
Message 1: "Let me check the file structure"
Message 2: tool_use(bash, "ls -la")
Message 3: tool_result("file1.txt file2.txt")
Message 4: "I found 2 files. Now reading file1.txt"
Message 5: tool_use(read, "file1.txt")
Message 6: tool_result("content...")
Message 7: "The file contains..."
```

**After (Grouped Steps):**
```
Step 1: {
  description: "Checking file structure",
  messages: [1, 2, 3],
  tools: ["bash"],
  status: "completed"
}

Step 2: {
  description: "Reading file1.txt",
  messages: [4, 5, 6, 7],
  tools: ["read"],
  status: "completed"
}
```

## Key Features

### 1. Automatic Step Detection
- Pattern-based detection of logical boundaries
- Configurable detection strategies
- Support for custom step definitions

### 2. Streaming Step Groups
- Real-time step emission as they complete
- Buffering for incomplete steps
- Timeout handling for long-running steps

### 3. Step Control Interface
- Pause after each step
- Review step before allowing continuation
- Inject guidance between steps
- Skip or retry steps

### 4. State Management
- Step history tracking
- Conversation state preservation
- Resume from specific steps

## Architecture Components

### 1. Step Detector
Analyzes message patterns to identify step boundaries

### 2. Step Buffer
Accumulates messages until a complete step is formed

### 3. Step Emitter
Emits completed steps to consumers

### 4. Step Controller
Manages pause/resume/intervention logic

### 5. State Manager
Persists step history and conversation state

## Integration Points

### With Claude Code SDK
- Wraps existing message streams
- Preserves backward compatibility
- Optional feature activation

### With Pipeline System
- Steps become reviewable units
- Safety reviewer can intercept steps
- Checkpoint system aligns with steps

### With Safety Reviewer
- Each step can be reviewed before continuation
- Interventions can be injected between steps
- Risk assessment per step

## Benefits

### 1. Enhanced Control
- Fine-grained execution control
- Step-by-step debugging
- Interactive guidance

### 2. Improved Safety
- Review actions before side effects
- Prevent cascading errors
- Enable human-in-the-loop workflows

### 3. Better Observability
- Clear action boundaries
- Structured logging
- Performance metrics per step

### 4. Developer Experience
- Easier to understand Claude's process
- Debuggable execution flow
- Replayable steps

## Implementation Approach

### Phase 1: Core Step Detection
- Implement pattern-based step detection
- Create step data structures
- Build basic buffering logic

### Phase 2: Streaming Integration
- Integrate with async streaming
- Handle sync mode transformation
- Implement timeout handling

### Phase 3: Control Interface
- Add pause/resume capabilities
- Implement step intervention API
- Create state management

### Phase 4: Advanced Features
- Custom step definitions
- Machine learning-based detection
- Step optimization

## Success Criteria

1. **Accuracy**: 95%+ correct step boundary detection
2. **Performance**: < 5% overhead on streaming
3. **Reliability**: No message loss or corruption
4. **Usability**: Simple API for step consumption

## Configuration Example

```elixir
config = %{
  step_detection: %{
    enabled: true,
    strategy: :pattern_based,
    patterns: :default,
    buffer_timeout_ms: 5000
  },
  step_control: %{
    pause_between_steps: true,
    review_handler: &MyReviewer.review_step/1,
    intervention_enabled: true
  },
  state_management: %{
    persist_steps: true,
    max_step_history: 100
  }
}

{:ok, stream} = ClaudeCodeSDK.query_with_steps(prompt, config)
```

## Next Steps

1. Review and approve the design
2. Implement core step detection logic
3. Create prototype with basic patterns
4. Test with real Claude conversations
5. Refine detection algorithms
6. Build control interfaces
7. Integrate with pipeline system

## Related Documents

- [Technical Architecture](./architecture.md)
- [Step Detection Patterns](./step_detection.md)
- [API Reference](./api_reference.md)
- [Implementation Guide](./implementation_guide.md)