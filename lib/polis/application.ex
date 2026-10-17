defmodule Polis.Application do
  @moduledoc false

  # The order is the order of need: the state file before anything that
  # reads it, the queue before the lines that fill it, the page last.
  # `rest_for_one`, so a state process that falls over takes down what
  # holds a stale view of it, and only that.

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Polis.PubSub},
        {Task.Supervisor, name: Polis.TaskSupervisor},
        Polis.State,
        {Registry, keys: :unique, name: Polis.LinkRegistry},
        {DynamicSupervisor, name: Polis.Links, strategy: :one_for_one},
        Polis.Queue,
        Polis.LauncherDetails,
        {Polis.Updates.Checker, timer: Application.get_env(:polis, :updates_timer, true)}
      ] ++
        links() ++ [PolisWeb.Endpoint]

    Supervisor.start_link(children, strategy: :rest_for_one, name: Polis.Supervisor)
  end

  # The lines to the joined tournaments, started once everything they call
  # is up. A task, so a station with ten tournaments and no network does
  # not hold the page up while it finds out.
  defp links do
    if Application.get_env(:polis, :autostart_links, true) do
      [
        Supervisor.child_spec({Task, &Polis.Station.start_links/0},
          id: :start_links,
          restart: :temporary
        )
      ]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    PolisWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
