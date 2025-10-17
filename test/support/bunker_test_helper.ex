defmodule Bunker.TestHelper do
  @moduledoc """
  Test helpers for Bunker to make testing violations easier.
  """

  import ExUnit.Callbacks

  @doc """
  Creates a mock transaction for testing.

  This function sets up a mock repository that always reports as being in a
  transaction, allowing you to test violation detection.

  ## Example

      test "detects violations in transaction" do
        with_mock_transaction(fn ->
          :telemetry.execute([:grpc, :client, :rpc, :start], %{}, metadata)
          # This will be detected as a violation
        end)
      end
  """
  @spec with_mock_transaction((-> any())) :: any()
  def with_mock_transaction(fun) when is_function(fun, 0) do
    # Define a test repo module that simulates being in a transaction
    defmodule MockRepo do
      def __adapter__, do: Ecto.Adapters.Postgres
    end

    # Add MockRepo to the repos list
    original_repos = Application.get_env(:bunker, :repos, [])
    Application.put_env(:bunker, :repos, [MockRepo])

    # Mock the Ecto.Adapter.lookup_meta to return mock adapter data
    # that reports as being in a transaction
    Mimic.stub(Ecto.Adapter, :lookup_meta, fn MockRepo ->
      %{pid: self(), opts: [], repo: MockRepo}
    end)

    Mimic.stub(Ecto.Adapters.Postgres, :in_transaction?, fn _meta ->
      true
    end)

    try do
      fun.()
    after
      Application.put_env(:bunker, :repos, original_repos)
    end
  end

  @doc """
  Sets up automatic violation checking for ALL tests.

  This helper should be called in your test/support/case.ex setup block to automatically raise
  Bunker.ViolationError when violations are detected during ANY test.

  This works by:
  1. Clearing any previous violations before each test
  2. Checking for violations after each test completes
  3. Raising the first violation found (if any)

  ## Usage

      # In your test/support/case.ex
      defmodule MyApp.DataCase do
        use ExUnit.CaseTemplate
        import Bunker.TestHelper

        setup do
          # Configure bunker for your application
          Application.put_env(:bunker, :repos, [MyApp.Repo])

          # Set up automatic violation checking
          setup_transaction_violation_check!()

          :ok
        end
      end

      # Now ALL tests will automatically raise exceptions when violations are detected
      test "my test" do
        MyApp.Repo.transaction(fn ->
          # This will be detected and raised automatically at test end
          MyGrpcClient.call_service()
        end)
      end
  """
  @spec setup_transaction_violation_check! :: :ok
  def setup_transaction_violation_check! do
    # Clear any previous violations before test starts
    clear_violations()

    # Check for violations after test completes
    on_exit(:isolator_violation_check, fn ->
      check_and_raise_violations()
    end)

    :ok
  end

  # Clear all violation storage
  defp clear_violations do
    Application.put_env(:bunker, :test_violations, [])
  end

  # Check for violations and raise if any found
  # NOTE: This runs in the on_exit callback, which is a SEPARATE PROCESS from the test.
  # Therefore, it can ONLY access the Application environment, not the process dictionary!
  defp check_and_raise_violations do
    # Check application environment (this is the only reliable storage for on_exit)
    # The process dictionary from the test process is NOT accessible here!
    app_violations = Application.get_env(:bunker, :test_violations, [])

    # Clear violations for next test
    Application.put_env(:bunker, :test_violations, [])

    # Raise the first violation found
    case app_violations do
      [] -> :ok
      [violation | _] -> raise violation
    end
  end

end
