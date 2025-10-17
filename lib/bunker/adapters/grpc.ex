defmodule Bunker.Adapters.GRPC do
  @moduledoc """
  Adapter for gRPC client operations using the official elixir-grpc library's telemetry events.

  This adapter monitors outgoing gRPC client calls:
  - `[:grpc, :client, :rpc, :start]` - Client-side RPC calls

  Server-side RPC calls are not monitored as they represent incoming requests being processed,
  not outgoing calls made during transactions.

  See: https://github.com/elixir-grpc/grpc/blob/master/lib/grpc/telemetry.ex
  """

  @behaviour Bunker.Adapter

  @impl true
  def events do
    [
      [:grpc, :client, :rpc, :start]
    ]
  end

  @impl true
  def handle_event([:grpc, :client, :rpc, :start], _measurements, metadata, _config) do
    {:ok, :grpc_client_call,
     %{
       service: metadata[:service],
       method: metadata[:method]
     }}
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ignore
  end

  @impl true
  def format_operation(:grpc_client_call, %{service: service, method: method}) do
    "grpc_client_call: #{service}.#{method}"
  end

  def format_operation(operation_type, _metadata) do
    "#{operation_type}"
  end
end
