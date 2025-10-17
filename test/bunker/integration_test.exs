defmodule Bunker.IntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  @moduletag :integration

  setup do
    original_config = [
      enabled: Application.get_env(:bunker, :enabled),
      adapters: Application.get_env(:bunker, :adapters),
      repos: Application.get_env(:bunker, :repos)
    ]

    Application.put_env(:bunker, :enabled, true)
    Application.put_env(:bunker, :adapters, [Bunker.Adapters.GRPC])

    # Ensure handlers are attached (might have been detached by previous test)
    ensure_handlers_attached()

    # Set up automatic violation checking - just like client code would do
    Bunker.TestHelper.setup_transaction_violation_check!()

    on_exit(fn ->
      Enum.each(original_config, fn {key, value} ->
        Application.put_env(:bunker, key, value)
      end)
    end)

    :ok
  end

  describe "telemetry integration with gRPC" do
    test "allows gRPC calls when not in transaction" do
      # Should not log - no transaction
      log =
        capture_log(fn ->
          :telemetry.execute(
            [:grpc, :client, :rpc, :start],
            %{system_time: System.system_time()},
            %{service: "Test", method: "test"}
          )
        end)

      refute log =~ "Transaction violation"
    end

    test "detects and stores gRPC client call violations in transaction" do
      # The violation will be raised automatically by the on_exit callback from setup
      with_mock_transaction(fn ->
        :telemetry.execute(
          [:grpc, :client, :rpc, :start],
          %{system_time: System.system_time()},
          %{service: "Users", method: "GetUser"}
        )
      end)

      # Verify violation was detected and stored in app env (will be raised by on_exit)
      violations = Application.get_env(:bunker, :test_violations, [])
      assert length(violations) > 0
      [violation | _] = violations
      assert violation.message =~ "Users.GetUser"

      # Clear manually for this test only (normally violations would fail the test)
      Application.put_env(:bunker, :test_violations, [])
    end

  end

  describe "configuration" do
    test "respects enabled flag" do
      Application.put_env(:bunker, :enabled, false)

      with_mock_transaction(fn ->
        # Should not log when disabled
        log =
          capture_log(fn ->
            :telemetry.execute(
              [:grpc, :client, :rpc, :start],
              %{system_time: System.system_time()},
              %{service: "Test", method: "test"}
            )
          end)

        refute log =~ "Transaction violation"
      end)
    end

    test "respects disabled/1 function" do
      with_mock_transaction(fn ->
        # Should not log when using disabled/1
        log =
          Bunker.disabled(fn ->
            capture_log(fn ->
              :telemetry.execute(
                [:grpc, :client, :rpc, :start],
                %{system_time: System.system_time()},
                %{service: "Test", method: "test"}
              )
            end)
          end)

        refute log =~ "Transaction violation"
      end)
    end
  end

  describe "multiple calls in transaction" do
    test "detects multiple gRPC calls in single transaction" do
      with_mock_transaction(fn ->
        :telemetry.execute(
          [:grpc, :client, :rpc, :start],
          %{system_time: System.system_time()},
          %{service: "Users", method: "GetUser"}
        )

        :telemetry.execute(
          [:grpc, :client, :rpc, :start],
          %{system_time: System.system_time()},
          %{service: "Orders", method: "CreateOrder"}
        )
      end)

      # Both violations should be stored
      violations = Application.get_env(:bunker, :test_violations, [])
      assert length(violations) == 2

      messages = Enum.map(violations, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "Users.GetUser"))
      assert Enum.any?(messages, &String.contains?(&1, "Orders.CreateOrder"))

      # Clear for this test
      Application.put_env(:bunker, :test_violations, [])
    end
  end

  describe "handler persistence" do
    test "handlers remain attached and detect multiple violations in sequence" do
      # First violation - verify it's detected
      with_mock_transaction(fn ->
        :telemetry.execute(
          [:grpc, :client, :rpc, :start],
          %{system_time: System.system_time()},
          %{service: "Users", method: "GetUser"}
        )
      end)

      violations = Application.get_env(:bunker, :test_violations, [])
      assert length(violations) > 0
      [first_violation | _] = violations
      assert first_violation.message =~ "Users.GetUser"

      # Clear to test second violation independently
      Application.put_env(:bunker, :test_violations, [])

      # Second violation should also work (handlers remain attached after storing violations)
      with_mock_transaction(fn ->
        :telemetry.execute(
          [:grpc, :client, :rpc, :start],
          %{system_time: System.system_time()},
          %{service: "Orders", method: "ListOrders"}
        )
      end)

      violations = Application.get_env(:bunker, :test_violations, [])
      assert length(violations) > 0
      [second_violation | _] = violations
      assert second_violation.message =~ "Orders.ListOrders"

      # Clear manually for this test only
      Application.put_env(:bunker, :test_violations, [])
    end
  end

  ## Helpers

  # Ensure handlers are attached (idempotent)
  defp ensure_handlers_attached do
    adapters = Bunker.adapters()

    events =
      adapters
      |> Enum.flat_map(& &1.events())
      |> Enum.uniq()

    # Check if already attached
    handlers = :telemetry.list_handlers(events)

    bunker_attached? =
      Enum.any?(handlers, fn handler ->
        handler.id == "bunker-handler"
      end)

    unless bunker_attached? do
      # Attach handlers
      :telemetry.attach_many(
        "bunker-handler",
        events,
        &Bunker.Handler.handle_event/4,
        adapters
      )
    end
  catch
    _, _ -> :ok
  end

  # Mock transaction by injecting a test repo that always reports in_transaction?
  defp with_mock_transaction(fun) do
    # Define a test repo module that simulates being in a transaction
    defmodule MockRepo do
      def __adapter__, do: Ecto.Adapters.Postgres
    end

    # Add MockRepo to the repos list
    original_repos = Application.get_env(:bunker, :repos, [])
    Application.put_env(:bunker, :repos, [MockRepo])

    # Mock the Ecto.Adapter.lookup_meta to return mock adapter data
    # that reports as being in a transaction
    stub(Ecto.Adapter, :lookup_meta, fn MockRepo ->
      %{pid: self(), opts: [], repo: MockRepo}
    end)

    stub(Ecto.Adapters.Postgres, :in_transaction?, fn _meta ->
      true
    end)

    try do
      # No need to check violations manually - they're raised synchronously
      fun.()
    after
      Application.put_env(:bunker, :repos, original_repos)
    end
  end
end
