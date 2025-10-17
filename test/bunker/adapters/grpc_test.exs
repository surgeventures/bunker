defmodule Bunker.Adapters.GRPCTest do
  use ExUnit.Case, async: true

  alias Bunker.Adapters.GRPC

  describe "events/0" do
    test "returns grpc client telemetry events only" do
      events = GRPC.events()

      assert [:grpc, :client, :rpc, :start] in events
    end
  end

  describe "handle_event/4 for client calls" do
    test "extracts metadata from client RPC start event" do
      metadata = %{
        service: "Orders",
        method: "CreateOrder"
      }

      assert {
               :ok,
               :grpc_client_call,
               %{
                 service: "Orders",
                 method: "CreateOrder"
               }
             } =
               GRPC.handle_event(
                 [:grpc, :client, :rpc, :start],
                 %{},
                 metadata,
                 nil
               )
    end
  end

  describe "handle_event/4 for other events" do
    test "ignores unknown events" do
      assert :ignore ==
               GRPC.handle_event([:unknown, :event], %{}, %{}, nil)
    end
  end
end
