# Bunker

[![Hex.pm](https://img.shields.io/badge/hex-bunker-purple)](https://hex.pm/packages/bunker)

> Automatically detect dangerous operations (like gRPC calls, external APIs) within Ecto transactions using telemetry-based monitoring.

**Set it up once in your test suite, and every test will automatically fail if violations are detected.**

## Why?

Making external calls within database transactions can lead to:
- **Deadlocks** - External services can be slow or hang
- **Connection pool exhaustion** - Transactions hold database connections
- **Long-running transactions** - External latency compounds transaction time
- **Distributed transaction issues** - No atomic rollback across services

## Installation

Add `bunker` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bunker, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Add configuration to test environment

```elixir
# config/test.exs
config :bunker,
  enabled: true,
  repos: [MyApp.Repo],
  adapters: [Bunker.Adapters.GRPC],
  log: true,
  log_level: :error
```

### 2. Set up automatic violation detection in your test case

```elixir
# test/support/data_case.ex
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate
  import Bunker.TestHelper

  setup do
    # This single line enables automatic violation detection!
    setup_transaction_violation_check!()

    # Your other setup code...
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
    :ok
  end
end
```

### 3. That's it! All tests now detect violations automatically

```elixir
# test/my_app/orders_test.exs
defmodule MyApp.OrdersTest do
  use MyApp.DataCase

  test "creating an order" do
    # ❌ This test will raise an error
    MyApp.Repo.transaction(fn ->
      order = MyApp.Repo.insert!(%Order{total: 100})
      # gRPC call detected - test raises Bunker.ViolationError
      MyGrpcClient.notify_payment_service(order.id)
    end)
  end

  test "creating an order correctly" do
    # ✅ This test PASSES - RPC call is outside the transaction
    {:ok, order} = MyApp.Repo.transaction(fn ->
      MyApp.Repo.insert!(%Order{total: 100})
    end)

    # This is fine - no transaction active
    MyGrpcClient.notify_payment_service(order.id)
  end
end
```

## Built-in Adapters

### gRPC Adapter

Monitors outgoing gRPC client calls via telemetry events from the `grpc` library:

```elixir
config :bunker,
  adapters: [Bunker.Adapters.GRPC]
```

The gRPC adapter automatically detects:
- `[:grpc, :client, :rpc, :start]` - Client-side RPC calls (outgoing)

## Creating Custom Adapters

You can create adapters for any library that emits telemetry events (or emit your own):

```elixir
defmodule MyApp.CustomAdapter do
  @behaviour Bunker.Adapter

  @impl true
  def events do
    [
      [:my_library, :operation, :start]
    ]
  end

  @impl true
  def handle_event([:my_library, :operation, :start], _measurements, metadata, _config) do
    {:ok, :custom_operation, %{
      operation: metadata.operation_name,
      target: metadata.target
    }}
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ignore
  end

  @impl true
  def format_operation(:custom_operation, metadata) do
    "custom_operation: #{metadata.operation} on #{metadata.target}"
  end
end
```

Add your custom adapter to the configuration:

```elixir
config :bunker,
  adapters: [
    Bunker.Adapters.GRPC,
    MyApp.CustomAdapter
  ]
```

## Test Helpers

### `setup_transaction_violation_check!/0`

Sets up automatic violation checking for all tests. Violations are automatically raised at the end of each test.

```elixir
setup do
  setup_transaction_violation_check!()
  :ok
end
```

### `with_mock_transaction/1`

Creates a mock transaction environment for unit tests:

```elixir
test "detects violations in mock transaction" do
  with_mock_transaction(fn ->
    :telemetry.execute([:grpc, :client, :rpc, :start], %{}, %{
      service: "Users",
      method: "GetUser"
    })
  end)
  # Violation will be raised automatically if setup_transaction_violation_check!() was called
end
```

## Temporary Bypass

Sometimes you need to make external calls within a transaction:

```elixir
Bunker.disabled(fn ->
  Repo.transaction(fn ->
    user = Repo.insert!(%User{name: "Alice"})
    # External calls allowed here
    MyGrpcClient.notify_user_created(user.id)
  end)
end)
```

## How It Works

1. **Application Start**: Bunker attaches telemetry handlers for all configured adapters
2. **Telemetry Event**: When a monitored library emits an event (e.g., gRPC call starts)
3. **Adapter Processing**: The appropriate adapter extracts operation metadata
4. **Transaction Check**: Bunker checks if any configured repo has an active transaction
5. **Violation Handling**: Stores violation and logs it; test helper raises it at test end

## Architecture

Bunker uses a telemetry-based adapter system:

1. **Adapters** listen to telemetry events
2. **Core** checks if we're in an Ecto transaction when an adapter detects an operation
3. **Handler** stores violations
4. **Test Helper** automatically raises stored violations at test completion

## Running Tests

```bash
# Run all tests
mix test
```
