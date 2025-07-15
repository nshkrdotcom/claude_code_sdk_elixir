# Model Selection API Design

## Overview

Add clean model selection support to the Elixir Claude Code SDK, enabling cost control and performance optimization through programmatic model choice.

## Current Problem

The SDK cannot control model selection, forcing users to:
- Use whatever model is set globally
- Cannot optimize costs per query (25x price difference between models)
- Cannot choose appropriate models for task complexity
- Missing critical production feature

## Proposed API Design

### 1. Simple Shortcuts (Recommended)

```elixir
# Use latest Sonnet (fast, cost-effective)
options = %ClaudeCodeSDK.Options{model: "sonnet"}

# Use latest Opus (highest capability, expensive)  
options = %ClaudeCodeSDK.Options{model: "opus"}

# Use default mixed mode (automatic model selection)
options = %ClaudeCodeSDK.Options{model: nil}  # or omit field
```

### 2. Specific Model Versions

```elixir
# Use specific model version for reproducibility
options = %ClaudeCodeSDK.Options{
  model: "claude-3-5-sonnet-20241022"
}

# Use specific Opus version
options = %ClaudeCodeSDK.Options{
  model: "claude-3-opus-20240229"  
}
```

### 3. Fallback Model Support

```elixir
# Primary model with fallback when overloaded
options = %ClaudeCodeSDK.Options{
  model: "opus",
  fallback_model: "sonnet"
}
```

### 4. Usage Examples

```elixir
# Cost-optimized workflow
cheap_options = %ClaudeCodeSDK.Options{model: "sonnet"}
expensive_options = %ClaudeCodeSDK.Options{model: "opus"}

# Simple tasks - save money (1¢ vs 26¢)
ClaudeCodeSDK.query("Fix typo in comment", cheap_options)

# Complex analysis - worth the cost
ClaudeCodeSDK.query("Analyze entire codebase architecture", expensive_options)

# Mixed approach with fallback
ClaudeCodeSDK.query("Complex task", %ClaudeCodeSDK.Options{
  model: "opus", 
  fallback_model: "sonnet"
})
```

## Implementation Plan

### 1. Options Struct Updates

Add to `lib/claude_code_sdk/options.ex`:

```elixir
defstruct [
  # ... existing fields ...
  :model,              # "sonnet", "opus", "claude-3-5-sonnet-20241022", etc.
  :fallback_model      # Optional fallback model
]

@type model_choice :: String.t() | nil
@type t :: %__MODULE__{
  # ... existing types ...
  model: model_choice(),
  fallback_model: model_choice()
}
```

### 2. CLI Argument Generation

Add to `to_args/1` function:

```elixir
def to_args(%__MODULE__{} = options) do
  []
  |> add_output_format_args(options)
  # ... existing args ...
  |> add_model_args(options)
  |> add_fallback_model_args(options)
end

defp add_model_args(args, %{model: nil}), do: args
defp add_model_args(args, %{model: model}), do: args ++ ["--model", model]

defp add_fallback_model_args(args, %{fallback_model: nil}), do: args  
defp add_fallback_model_args(args, %{fallback_model: model}), 
  do: args ++ ["--fallback-model", model]
```

### 3. Model Validation (Optional Enhancement)

```elixir
defmodule ClaudeCodeSDK.ModelValidator do
  @shortcuts ["sonnet", "opus"]
  @valid_models [
    "claude-3-5-sonnet-20241022",
    "claude-3-opus-20240229",
    # ... other known models
  ]
  
  def validate_model(nil), do: :ok
  def validate_model(model) when model in @shortcuts, do: :ok
  def validate_model(model) when model in @valid_models, do: :ok
  def validate_model(model), do: {:error, "Unknown model: #{model}"}
end
```

### 4. OptionBuilder Integration

Update `lib/claude_code_sdk/option_builder.ex` presets:

```elixir
def build_development_options do
  %Options{
    model: "sonnet",         # Cost-effective for development
    max_turns: 10,
    verbose: true,
    # ... other dev settings
  }
end

def build_production_options do
  %Options{
    model: "opus",           # High-quality for production
    fallback_model: "sonnet", # Fallback when overloaded
    max_turns: 3,
    # ... other prod settings  
  }
end

def build_analysis_options do
  %Options{
    model: "opus",           # Best capability for analysis
    allowed_tools: ["Read", "Grep"],
    # ... other analysis settings
  }
end
```

### 5. Documentation Examples

```elixir
# Cost comparison examples
@doc """
Model selection for cost optimization:

- `"sonnet"` - $0.01 per query (fast, efficient)
- `"opus"` - $0.26 per query (highest quality)  
- `nil` - Default mixed mode

## Examples

    # Cost-effective development
    %ClaudeCodeSDK.Options{model: "sonnet"}
    
    # High-quality production
    %ClaudeCodeSDK.Options{model: "opus", fallback_model: "sonnet"}
"""
```

## Benefits

1. **Cost Control**: 25x cost difference between models
2. **Performance Optimization**: Choose speed vs capability per task
3. **Production Ready**: Specific model versions for reproducibility
4. **Fallback Support**: Reliability when models are overloaded
5. **Clean API**: Simple shortcuts with full model name support
6. **Backward Compatible**: `model: nil` maintains current behavior

## Migration Path

- **Phase 1**: Add model fields to Options struct
- **Phase 2**: Implement CLI argument generation
- **Phase 3**: Update OptionBuilder presets  
- **Phase 4**: Add validation and documentation
- **Phase 5**: Update examples and tests

Existing code continues working unchanged (model defaults to nil).

## Testing Strategy

```elixir
# Test model selection
test "model selection works" do
  options = %Options{model: "sonnet"}
  args = Options.to_args(options)
  assert ["--model", "sonnet"] = Enum.take(args, -2)
end

# Test fallback model
test "fallback model works" do  
  options = %Options{model: "opus", fallback_model: "sonnet"}
  args = Options.to_args(options)
  assert "--model" in args
  assert "--fallback-model" in args
end
```

This design provides a clean, production-ready API for model selection while maintaining backward compatibility.