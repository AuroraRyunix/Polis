defmodule Polis.UpdatesTest do
  @moduledoc """
  The update check: the download each system asks for, by the name the
  release gives it; versions compared as versions; and the one thing an
  update must not cut off - a sheet half out of the printer.
  """

  use Polis.StationCase, async: false

  alias Polis.{FakeReleases, Updates}

  setup do
    start_supervised!(FakeReleases)
    FakeReleases.install()

    on_exit(fn ->
      FakeReleases.uninstall()
      Application.put_env(:polis, :install_kind, :manual)
      Application.delete_env(:polis, :updates_stop_fun)
      Polis.Updates.Checker.forget()
    end)

    :ok
  end

  defp newer do
    v = Version.parse!(Updates.current_version())
    "#{v.major}.#{v.minor + 1}.0"
  end

  test "each system asks for the download of its own" do
    v = newer()
    assert Updates.asset_name(:velopack, v) == "PolisApp-#{v}-full.nupkg"
    assert Updates.asset_name(:manual, v, {:win32, :nt}) == "polis-windows-x86_64-portable.zip"

    assert Updates.asset_name(:manual, v, {:unix, :linux}) =~
             ~r/^polis-linux-(x86_64|aarch64)\.tar\.gz$/

    assert Updates.asset_name(:manual, v, {:unix, :darwin}) in [nil, "polis-macos-aarch64.zip"]
  end

  test "a newer release is found, with the size of what this copy would download" do
    FakeReleases.publish(newer())
    assert {:ok, info, etag} = Updates.check()
    assert info.version == newer()
    assert info.asset == Updates.asset_name(:manual, newer())
    assert is_integer(info.size)
    assert is_binary(etag)

    # The same answer again costs a 304.
    assert :not_modified = Updates.check(etag)
  end

  test "versions are compared as versions, not as text" do
    v = Version.parse!(Updates.current_version())
    FakeReleases.publish("#{v.major}.#{v.minor}.#{v.patch}")
    assert {:current, _} = Updates.check()

    # 0.10.0 is newer than 0.9.0, which text would get wrong.
    FakeReleases.publish("#{v.major}.#{v.minor + 10}.0")
    assert {:ok, %{version: version}, _} = Updates.check()
    assert Version.compare(version, Updates.current_version()) == :gt

    FakeReleases.publish("#{max(v.major - 1, 0)}.0.0-rc.1")
    assert {:current, _} = Updates.check()
  end

  test "no connection is silence, not an error on the page" do
    FakeReleases.mode(:down)
    assert :error = Updates.check()
  end

  test "an update waits while a sheet is printing, unless forced" do
    Application.put_env(:polis, :install_kind, :velopack)
    Application.put_env(:polis, :updates_stop_fun, fn code -> send(self(), {:stopped, code}) end)
    FakeReleases.publish(newer())
    {:ok, info, _} = Updates.check()
    Polis.Updates.Checker.put(info)

    # A printer that never answers: the job stays "printing".
    Application.put_env(:polis, :printer_backend, Polis.SlowPrinter)
    Station.choose_printer("Hall printer")
    Queue.test_print()
    eventually(fn -> Queue.busy?() end)

    assert {:error, :busy} = Updates.apply()
    assert :ok = Updates.apply(force: true)
  end
end
