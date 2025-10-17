defmodule Bunker do
  require Logger

  @moduledoc """
  Bunker detects dangerous operations within active Ecto transactions.

  This library uses a telemetry-based adapter system to monitor external
  operations and detect when they occur within database transactions.

  ## Quick Start

  Set it up once in your test case and forget about it - all tests will
  automatically fail if violations are detected:

      # test/support/data_case.ex
      defmodule MyApp.DataCase do
        use ExUnit.CaseTemplate
        import Bunker.TestHelper

        setup do
          # This is all you need!
          setup_transaction_violation_check!()

          # ... your other setup code
          :ok
        end
      end

  Now ANY test that makes external calls within a transaction will automatically
  fail with a clear error message.

  ## Configuration

      config :bunker,
        enabled: true,
        repos: [MyApp.Repo],
        adapters: [Bunker.Adapters.GRPC],
        log: true,
        log_level: :error

  ## Usage

      # Automatic detection via telemetry
      Repo.transaction(fn ->
        MyGrpcClient.call(...)  # Detected and raised/logged
      end)

      # Temporary bypass
      Bunker.disabled(fn ->
        Repo.transaction(fn ->
          MyGrpcClient.call(...)  # Allowed
        end)
      end)
  """

  @type repo :: module()
  @type operation_type :: atom()
  @type metadata :: map()

  ## Configuration

  @doc "Returns whether isolation checking is enabled"
  @spec enabled? :: boolean()
  def enabled?, do: get_config(:enabled, true)

  @doc "Returns the list of Ecto repos to monitor"
  @spec repos :: [repo()]
  def repos, do: get_config(:repos, [])

  @doc "Returns the list of configured adapters"
  @spec adapters :: [module()]
  def adapters, do: get_config(:adapters, [Bunker.Adapters.GRPC])

  @doc "Returns whether violations should be logged"
  @spec log? :: boolean()
  def log?, do: get_config(:log, true)

  @doc "Returns the log level for violation messages"
  @spec log_level :: Logger.level()
  def log_level, do: get_config(:log_level, :error)

  defp get_config(key, default) do
    case Application.get_env(:bunker, key) do
      nil -> default
      value -> value
    end
  end

  ## Transaction Detection

  @doc """
  Checks if any configured repo has an active transaction.

  Returns `{true, repo}` if a transaction is active, `false` otherwise.
  """
  @spec in_transaction? :: {true, repo()} | false
  def in_transaction? do
    if disabled?() do
      false
    else
      repos()
      |> List.wrap()
      |> Enum.find_value(false, &check_transaction/1)
    end
  end

  defp check_transaction(repo) do
    repo
    |> in_transaction_for_repo?()
    |> case do
      true -> {true, repo}
      false -> false
    end
  end

  defp in_transaction_for_repo?(repo) do
    repo
    |> get_adapter_meta()
    |> case do
      {:ok, adapter, meta} -> adapter.in_transaction?(meta)
      {:error, _} -> false
    end
  end

  defp get_adapter_meta(repo) do
    adapter = repo.__adapter__()
    meta = Ecto.Adapter.lookup_meta(repo)
    {:ok, adapter, meta}
  rescue
    _ -> {:error, :lookup_failed}
  end

  ## Temporary Bypass

  @doc """
  Executes a function with isolation checks temporarily disabled.

  ## Example

      Bunker.disabled(fn ->
        Repo.transaction(fn ->
          MyGrpcClient.call(...)  # Allowed
        end)
      end)
  """
  @spec disabled((-> result)) :: result when result: any()
  def disabled(fun) when is_function(fun, 0) do
    Process.put(:bunker_disabled, true)

    try do
      fun.()
    after
      Process.delete(:bunker_disabled)
    end
  end

  defp disabled?, do: Process.get(:bunker_disabled, false)
end
