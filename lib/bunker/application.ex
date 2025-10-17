defmodule Bunker.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    if Bunker.enabled?() do
      attach_handlers()
    end

    Supervisor.start_link([], strategy: :one_for_one, name: Bunker.Supervisor)
  end

  defp attach_handlers do
    Bunker.adapters()
    |> collect_events()
    |> attach_telemetry()
    |> log_attachment()
  end

  defp collect_events(adapters) do
    events =
      adapters
      |> Enum.flat_map(& &1.events())
      |> Enum.uniq()

    {adapters, events}
  end

  defp attach_telemetry({adapters, events}) do
    :telemetry.attach_many(
      "bunker-handler",
      events,
      &Bunker.Handler.handle_event/4,
      adapters
    )

    {adapters, events}
  end

  defp log_attachment({adapters, events}) do
    Logger.debug(
      "[Bunker] Attached handlers for #{length(events)} event(s) from #{length(adapters)} adapter(s)"
    )

    :ok
  end
end
