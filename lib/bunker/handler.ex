defmodule Bunker.Handler do
  @moduledoc """
  Detects and logs external operations performed within database transactions.
  """

  require Logger

  @doc """
  Handles telemetry events by routing them to the appropriate adapter.

  When a violation is detected:
  - In test env: stored in Application process for test helper to raise
  - In other envs: logged at configured level
  """
  @spec handle_event(
          event :: [atom()],
          measurements :: map(),
          metadata :: map(),
          adapters :: [module()]
        ) :: :ok | no_return()
  def handle_event(event, measurements, metadata, adapters) do
    do_handle_event(Bunker.enabled?(), event, measurements, metadata, adapters)
  end

  defp do_handle_event(false, _event, _measurements, _metadata, _adapters), do: :ok

  defp do_handle_event(true, event, measurements, metadata, adapters) do
    adapters
    |> find_violation(event, measurements, metadata)
    |> handle_violation()
  end

  defp find_violation(adapters, event, measurements, metadata) do
    Enum.find_value(adapters, :no_violation, fn adapter ->
      call_adapter(adapter, event, measurements, metadata)
    end)
  end

  defp call_adapter(adapter, event, measurements, metadata) do
    adapter
    |> apply(:handle_event, [event, measurements, metadata, nil])
    |> handle_adapter_response(adapter)
  end

  defp handle_adapter_response({:ok, operation_type, operation_metadata}, adapter) do
    {:violation, operation_type, operation_metadata, adapter}
  end

  defp handle_adapter_response(:ignore, _adapter), do: nil

  defp handle_violation(:no_violation), do: :ok

  defp handle_violation({:violation, operation_type, operation_metadata, adapter}) do
    operation_type
    |> check_transaction(operation_metadata)
    |> handle_result(adapter)
  end

  defp check_transaction(operation_type, metadata) do
    case Bunker.in_transaction?() do
      {true, repo} -> {:violation, operation_type, metadata, repo}
      false -> :ok
    end
  end

  defp handle_result(:ok, _adapter), do: :ok

  defp handle_result({:violation, operation_type, metadata, repo}, adapter) do
    message =
      operation_type
      |> adapter.format_operation(metadata)
      |> build_message(repo, metadata)

    error = %Bunker.ViolationError{message: message}

    # Store for test helpers or log in other environments
    handle_by_env(error, message)
    :ok
  end

  defp handle_by_env(error, message) do
    if Mix.env() == :test do
      # Store in application env for test helper to check via on_exit callback
      violations = Application.get_env(:bunker, :test_violations, [])
      Application.put_env(:bunker, :test_violations, [error | violations])
    else
      # Log in non-test environments
      log_violation(message)
    end
  end

  ## Message Formatting

  defp build_message(operation, repo, metadata) do
    """
    [Bunker] ⚠️  Transaction violation detected!

    Operation: #{operation}
    Repo: #{inspect(repo)}
    Details: #{inspect(metadata)}

    An external operation was detected within an active database transaction.
    This can lead to deadlocks, connection pool exhaustion, and long-running transactions.

    Consider moving this operation outside the transaction.
    """
  end

  defp log_violation(message) do
    if Bunker.log?() do
      Logger.log(Bunker.log_level(), message)
    end
  end
end
