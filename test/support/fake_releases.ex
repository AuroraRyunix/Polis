defmodule Polis.FakeReleases do
  @moduledoc """
  GitHub's "latest release" for the tests: the one request
  `Polis.Updates.check/1` makes, answered the way GitHub answers it - a
  release with its assets and an ETag, a 304 for a request that carries
  that ETag, a 404 for a repository that has released nothing, no
  connection at all. It proves the station reads such an answer; it proves
  nothing about github.com.
  """

  use Agent

  def start_link(_opts \\ []),
    do: Agent.start_link(fn -> %{release: nil, mode: :ok} end, name: __MODULE__)

  def install, do: Application.put_env(:polis, :updates_req_options, plug: &__MODULE__.call/1)
  def uninstall, do: Application.delete_env(:polis, :updates_req_options)

  def publish(version) do
    assets = [
      {"PolisApp-#{version}-full.nupkg", 41_000_000},
      {"Polis-Setup.exe", 42_000_000},
      {"polis-windows-x86_64-portable.zip", 50_000_000},
      {"polis-linux-x86_64.tar.gz", 30_000_000},
      {"polis-linux-aarch64.tar.gz", 29_000_000},
      {"polis-macos-aarch64.zip", 28_000_000}
    ]

    release = %{
      "tag_name" => "v#{version}",
      "html_url" => "https://github.com/AuroraRyunix/Polis/releases/tag/v#{version}",
      "draft" => false,
      "prerelease" => false,
      "assets" => Enum.map(assets, fn {name, size} -> %{"name" => name, "size" => size} end)
    }

    Agent.update(__MODULE__, &%{&1 | release: release})
  end

  def mode(mode), do: Agent.update(__MODULE__, &%{&1 | mode: mode})

  def call(conn) do
    %{release: release, mode: mode} = Agent.get(__MODULE__, & &1)
    asked = List.first(Plug.Conn.get_req_header(conn, "if-none-match"))
    etag = release && ~s(W/"#{:erlang.phash2(release)}")

    cond do
      mode == :down -> Req.Test.transport_error(conn, :nxdomain)
      release == nil -> json(conn, 404, %{"message" => "Not Found"})
      asked == etag -> Plug.Conn.send_resp(conn, 304, "")
      true -> conn |> Plug.Conn.put_resp_header("etag", etag) |> json(200, release)
    end
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
