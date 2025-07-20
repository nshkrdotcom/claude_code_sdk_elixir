defmodule ClaudeCodeSDK.StepStreamSimpleTest do
  use ExUnit.Case, async: true

  alias ClaudeCodeSDK.{StepStream, StepDetector, Message, Step}

  # Test helper to create test messages
  defp create_test_message(type \\ :assistant, content \\ "test content") do
    %Message{
      type: type,
      data: %{
        message: %{"content" => content},
        session_id: "test-session"
      }
    }
  end

  # Test helper to create a list of test messages
  defp create_test_messages(count \\ 3) do
    for i <- 1..count do
      create_test_message(:assistant, "Message #{i}")
    end
  end

  describe "transform/2" do
    test "transforms message stream to step stream" do
      messages = create_test_messages(3)
      detector = StepDetector.new()

      steps =
        messages
        |> StepStream.transform(step_detector: detector)
        |> Enum.to_list()

      # Our simple implementation creates one step
      assert length(steps) == 1

      assert Enum.all?(steps, fn step ->
               %Step{} = step
               is_binary(step.id)
             end)
    end

    test "handles empty message stream" do
      steps =
        []
        |> StepStream.transform()
        |> Enum.to_list()

      assert steps == []
    end

    test "accepts custom step detector" do
      messages = create_test_messages(2)
      detector = StepDetector.new(confidence_threshold: 0.5)

      steps =
        messages
        |> StepStream.transform(step_detector: detector)
        |> Enum.to_list()

      assert length(steps) == 1
    end
  end

  describe "from_messages/2" do
    test "creates step stream from message list" do
      messages = create_test_messages(3)

      steps =
        StepStream.from_messages(messages)
        |> Enum.to_list()

      assert length(steps) == 1
      assert Enum.all?(steps, &match?(%Step{}, &1))
    end

    test "handles empty message list" do
      steps =
        StepStream.from_messages([])
        |> Enum.to_list()

      assert steps == []
    end
  end

  describe "utility functions" do
    setup do
      # Create a mix of different step types for testing
      steps = [
        Step.new(type: :file_operation, description: "Read file"),
        Step.new(type: :code_modification, description: "Update code"),
        Step.new(type: :file_operation, description: "Write file"),
        Step.new(type: :analysis, description: "Analyze code")
      ]

      %{steps: steps}
    end

    test "filter_by_type/2 filters by single type", %{steps: steps} do
      file_steps =
        steps
        |> StepStream.filter_by_type(:file_operation)
        |> Enum.to_list()

      assert length(file_steps) == 2
      assert Enum.all?(file_steps, &(&1.type == :file_operation))
    end

    test "map/2 transforms each step", %{steps: steps} do
      mapped_steps =
        steps
        |> StepStream.map(fn step ->
          %{step | description: String.upcase(step.description)}
        end)
        |> Enum.to_list()

      assert length(mapped_steps) == 4

      assert Enum.all?(mapped_steps, fn step ->
               step.description == String.upcase(step.description)
             end)
    end

    test "batch/2 groups steps into batches", %{steps: steps} do
      batches =
        steps
        |> StepStream.batch(2)
        |> Enum.to_list()

      assert length(batches) == 2
      assert length(Enum.at(batches, 0)) == 2
      assert length(Enum.at(batches, 1)) == 2
    end
  end
end
