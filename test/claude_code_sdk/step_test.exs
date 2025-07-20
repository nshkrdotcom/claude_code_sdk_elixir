defmodule ClaudeCodeSDK.StepTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{Step, Message, StepTestHelpers}

  describe "Step.new/1" do
    test "creates a step with default values" do
      step = Step.new()

      assert is_binary(step.id)
      assert String.starts_with?(step.id, "step-")
      assert step.type == :unknown
      assert step.description == ""
      assert step.messages == []
      assert step.tools_used == []
      assert step.status == :in_progress
      assert step.metadata == %{}
      assert step.review_status == nil
      assert step.interventions == []
      assert %DateTime{} = step.started_at
      assert step.completed_at == nil
    end

    test "creates a step with custom options" do
      opts = [
        id: "custom-id",
        type: :file_operation,
        description: "Test step",
        status: :completed
      ]

      step = Step.new(opts)

      assert step.id == "custom-id"
      assert step.type == :file_operation
      assert step.description == "Test step"
      assert step.status == :completed
    end
  end

  describe "Step.add_message/2" do
    test "adds a message to the step" do
      step = Step.new()
      message = %Message{type: :assistant, data: %{}, raw: %{}}

      updated_step = Step.add_message(step, message)

      assert length(updated_step.messages) == 1
      assert hd(updated_step.messages) == message
    end

    test "appends messages in order" do
      step = Step.new()
      message1 = %Message{type: :assistant, data: %{content: "first"}, raw: %{}}
      message2 = %Message{type: :assistant, data: %{content: "second"}, raw: %{}}

      updated_step =
        step
        |> Step.add_message(message1)
        |> Step.add_message(message2)

      assert length(updated_step.messages) == 2
      assert Enum.at(updated_step.messages, 0) == message1
      assert Enum.at(updated_step.messages, 1) == message2
    end
  end

  describe "Step.add_tool/2" do
    test "adds a tool to the step" do
      step = Step.new()

      updated_step = Step.add_tool(step, "readFile")

      assert updated_step.tools_used == ["readFile"]
    end

    test "does not add duplicate tools" do
      step = Step.new()

      updated_step =
        step
        |> Step.add_tool("readFile")
        |> Step.add_tool("readFile")
        |> Step.add_tool("fsWrite")

      assert updated_step.tools_used == ["readFile", "fsWrite"]
    end
  end

  describe "Step.complete/1" do
    test "marks step as completed with timestamp" do
      step = Step.new()

      completed_step = Step.complete(step)

      assert completed_step.status == :completed
      assert %DateTime{} = completed_step.completed_at
    end
  end

  describe "Step.abort/1" do
    test "marks step as aborted with timestamp" do
      step = Step.new()

      aborted_step = Step.abort(step)

      assert aborted_step.status == :aborted
      assert %DateTime{} = aborted_step.completed_at
    end
  end

  describe "Step.timeout/1" do
    test "marks step as timed out with timestamp" do
      step = Step.new()

      timeout_step = Step.timeout(step)

      assert timeout_step.status == :timeout
      assert %DateTime{} = timeout_step.completed_at
    end
  end

  describe "Step.set_review_status/2" do
    test "sets the review status" do
      step = Step.new()

      approved_step = Step.set_review_status(step, :approved)
      assert approved_step.review_status == :approved

      rejected_step = Step.set_review_status(step, :rejected)
      assert rejected_step.review_status == :rejected
    end
  end

  describe "Step.add_intervention/2" do
    test "adds an intervention to the step" do
      step = Step.new()

      intervention = %{
        type: :guidance,
        content: "Be careful with this operation",
        applied_at: DateTime.utc_now()
      }

      updated_step = Step.add_intervention(step, intervention)

      assert length(updated_step.interventions) == 1
      assert hd(updated_step.interventions) == intervention
    end
  end

  describe "Step.update_metadata/2" do
    test "updates step metadata" do
      step = Step.new(metadata: %{confidence: 0.5})

      updated_step = Step.update_metadata(step, %{accuracy: 0.8, confidence: 0.9})

      assert updated_step.metadata == %{confidence: 0.9, accuracy: 0.8}
    end
  end

  describe "Step.completed?/1" do
    test "returns true for completed steps" do
      assert Step.completed?(Step.new(status: :completed))
      assert Step.completed?(Step.new(status: :timeout))
      assert Step.completed?(Step.new(status: :aborted))
      assert Step.completed?(Step.new(status: :error))
    end

    test "returns false for in-progress steps" do
      refute Step.completed?(Step.new(status: :in_progress))
    end
  end

  describe "Step.approved?/1" do
    test "returns true for approved or no review status" do
      assert Step.approved?(Step.new(review_status: nil))
      assert Step.approved?(Step.new(review_status: :approved))
    end

    test "returns false for rejected or pending" do
      refute Step.approved?(Step.new(review_status: :rejected))
      refute Step.approved?(Step.new(review_status: :pending))
    end
  end

  describe "Step.duration_ms/1" do
    test "calculates duration for completed steps" do
      started = DateTime.utc_now()
      completed = DateTime.add(started, 1500, :millisecond)

      step = %Step{
        id: "test-step",
        type: :unknown,
        description: "",
        messages: [],
        tools_used: [],
        started_at: started,
        completed_at: completed,
        status: :completed,
        metadata: %{},
        review_status: nil,
        interventions: []
      }

      assert Step.duration_ms(step) == 1500
    end

    test "returns nil for incomplete steps" do
      step = Step.new()
      assert Step.duration_ms(step) == nil
    end
  end

  describe "Step.to_summary/1" do
    test "creates a summary map" do
      step =
        StepTestHelpers.create_test_step(:file_operation,
          description: "Test operation",
          tools_used: ["readFile", "fsWrite"]
        )

      summary = Step.to_summary(step)

      assert summary.id == step.id
      assert summary.type == :file_operation
      assert summary.description == "Test operation"
      assert summary.status == step.status
      assert summary.tools_used == ["readFile", "fsWrite"]
      assert summary.message_count == 3
    end
  end
end
