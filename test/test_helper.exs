# Enable mocking for tests
Application.put_env(:claude_code_sdk, :use_mock, true)

# Start the mock server
{:ok, _} = ClaudeCodeSDK.Mock.start_link()

# Exclude live tests by default unless LIVE_TESTS env var is set
exclude_tags = if System.get_env("LIVE_TESTS") == "true", do: [], else: [:live]

ExUnit.start(exclude: exclude_tags)
