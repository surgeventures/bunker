defmodule Bunker.HandlerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Bunker.TestHelper

  defmodule TestAdapter do
    @behaviour Bunker.Adapter

    @impl true
    def events, do: [[:test, :event]]

    @impl true
    def handle_event([:test, :event], _measurements, metadata, _config) do
      {:ok, :test_operation, metadata}
    end

    def handle_event(_event, _measurements, _metadata, _config), do: :ignore

    @impl true
    def format_operation(:test_operation, metadata) do
      "test_operation: #{metadata.service}.#{metadata.method}"
    end

    def format_operation(operation_type, _metadata) do
      "#{operation_type}"
    end
  end

  setup do
    original_enabled = Application.get_env(:bunker, :enabled)
    original_repos = Application.get_env(:bunker, :repos, [])

    Application.put_env(:bunker, :enabled, true)

    on_exit(fn ->
      Application.put_env(:bunker, :enabled, original_enabled)
      Application.put_env(:bunker, :repos, original_repos)
    end)

    :ok
  end

  describe "handle_event/4" do
    test "stores violation when operation happens in transaction" do
      adapters = [TestAdapter]

      with_mock_transaction(fn ->
        Bunker.Handler.handle_event(
          [:test, :event],
          %{},
          %{service: "Test", method: "test"},
          adapters
        )
      end)

      # Check that violation was stored in app env
      violations = Application.get_env(:bunker, :test_violations, [])
      assert length(violations) > 0
      [violation | _] = violations
      assert violation.message =~ "Transaction violation"

      # Clear for next test
      Application.put_env(:bunker, :test_violations, [])
    end

    test "does not log when operation happens outside transaction" do
      adapters = [TestAdapter]

      log =
        capture_log(fn ->
          Bunker.Handler.handle_event(
            [:test, :event],
            %{},
            %{service: "Test", method: "test"},
            adapters
          )
        end)

      refute log =~ "Transaction violation"
    end

    test "respects enabled flag" do
      Application.put_env(:bunker, :enabled, false)
      adapters = [TestAdapter]

      with_mock_transaction(fn ->
        log =
          capture_log(fn ->
            Bunker.Handler.handle_event(
              [:test, :event],
              %{},
              %{service: "Test", method: "test"},
              adapters
            )
          end)

        refute log =~ "Transaction violation"
      end)
    end

    test "handles unknown events gracefully" do
      adapters = [TestAdapter]

      result =
        Bunker.Handler.handle_event(
          [:unknown, :event],
          %{},
          %{},
          adapters
        )

      assert result == :ok
    end
  end
end
