defmodule Bunker.Adapter do
  @moduledoc """
  Behaviour for Bunker adapters.

  Adapters define which telemetry events to monitor and how to extract
  operation metadata from those events.
  """

  @doc """
  Returns the list of telemetry event names this adapter monitors.

  ## Example

      def events do
        [
          [:grpc, :server, :rpc, :start],
          [:grpc, :client, :rpc, :start]
        ]
      end
  """
  @callback events() :: [telemetry_event_name :: list(atom())]

  @doc """
  Extracts operation metadata from a telemetry event.

  Returns `{:ok, operation_type, metadata}` or `:ignore` to skip the event.

  ## Example

      def handle_event([:grpc, :client, :rpc, :start], _measurements, metadata, _config) do
        {:ok, :grpc_client_call, %{
          service: metadata.service,
          method: metadata.method
        }}
      end
  """
  @callback handle_event(
              event :: list(atom()),
              measurements :: map(),
              metadata :: map(),
              config :: term()
            ) :: {:ok, operation_type :: atom(), operation_metadata :: map()} | :ignore

  @doc """
  Formats an operation for display in violation messages.

  Returns a human-readable string describing the operation.

  ## Example

      def format_operation(:grpc_client_call, %{service: service, method: method}) do
        "grpc_client_call: \#{service}.\#{method}"
      end
  """
  @callback format_operation(operation_type :: atom(), metadata :: map()) :: String.t()
end
