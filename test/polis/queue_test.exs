defmodule Polis.QueueTest do
  @moduledoc """
  What prints by itself and what does not, through the recording printer:
  a new round once, nothing without a printer until one is chosen, a
  changed round not at all until somebody asks, a reprint when somebody
  does, and the test page.
  """

  use Polis.StationCase, async: false

  defp joined do
    {:ok, id} =
      State.add_tournament(%{
        "socket_url" => "ws://127.0.0.1:1/p/polis/link",
        "key" => "k",
        "server" => "fake",
        "tournament_id" => "t-1",
        "name" => "Club Open"
      })

    id
  end

  defp printed_whats(n) do
    for _ <- 1..n do
      assert_receive {:printed, job}, 2_000
      job
    end
  end

  test "a new round prints its pairings and its place cards, once" do
    Station.choose_printer("Hall printer")
    id = joined()

    assert :printing = Station.round_received(id, FakeServer.payload(1))
    jobs = printed_whats(2)

    assert Enum.map(jobs, & &1.title) |> Enum.sort() == [
             "Club Open - Pairings 1",
             "Club Open - Place cards 1"
           ]

    assert Enum.all?(jobs, &(&1.printer == "Hall printer" and File.exists?(&1.pdf)))

    # The same round again (a reconnect): nothing.
    assert :kept = Station.round_received(id, FakeServer.payload(1))
    :ok = Queue.drain()
    refute_receive {:printed, _}, 200

    assert Enum.all?(Queue.jobs(), &(&1.status == :printed))
    assert Station.status_for(id) == %{"printer" => "Hall printer", "last_printed_round" => 1}
  end

  test "without a printer the jobs wait, and go when one is chosen" do
    id = joined()
    Station.round_received(id, FakeServer.payload(2))

    assert [%{status: :waiting_printer}, %{status: :waiting_printer}] = Queue.jobs()
    assert Queue.pending_count() == 2
    refute_receive {:printed, _}, 200

    Station.choose_printer("Office printer")
    printed_whats(2)
    :ok = Queue.drain()
    assert Enum.all?(Queue.jobs(), &(&1.status == :printed))
    assert Queue.pending_count() == 0
  end

  test "a round changed after printing is not printed again by itself; Reprint does it" do
    Station.choose_printer("Hall printer")
    id = joined()
    Station.round_received(id, FakeServer.payload(3, "r1"))
    printed_whats(2)

    assert :kept = Station.round_received(id, FakeServer.payload(3, "r2"))
    refute_receive {:printed, _}, 300
    assert Station.changed_since_printed?(State.tournament(id))
    assert [%{"changed" => true}] = Station.overview()

    :ok = Station.reprint_round(id)
    printed_whats(2)
    refute Station.changed_since_printed?(State.tournament(id))

    # A newer round is a new round again.
    assert :printing = Station.round_received(id, FakeServer.payload(4, "r1"))
    printed_whats(2)
  end

  test "the switches and the copies are what the next round prints" do
    Station.choose_printer("Hall printer")
    id = joined()
    Station.set_switch(id, "print_placecards", false)
    Station.set_copies(id, 3)

    Station.round_received(id, FakeServer.payload(1))
    assert [%{title: "Club Open - Pairings 1", copies: 3}] = printed_whats(1)
    refute_receive {:printed, _}, 200
  end

  test "a print command from the server prints what it names, for the round held" do
    Station.choose_printer("Hall printer")
    id = joined()
    Station.set_switch(id, "print_pairings", false)
    Station.set_switch(id, "print_placecards", false)
    Station.round_received(id, FakeServer.payload(5))
    refute_receive {:printed, _}, 200

    assert :ok = Station.print_command(id, 5, "placecards")
    assert [%{title: "Club Open - Place cards 5"}] = printed_whats(1)
    assert :unknown_round = Station.print_command(id, 4, "both")
  end

  test "Reprint of a job makes a new job from the same source" do
    Station.choose_printer("Hall printer")
    id = joined()
    Station.set_switch(id, "print_placecards", false)
    Station.round_received(id, FakeServer.payload(1))
    [first] = printed_whats(1)
    :ok = Queue.drain()

    [job] = Queue.jobs()
    assert {:ok, new_id} = Queue.reprint(job.id)
    [again] = printed_whats(1)
    assert again.title == first.title
    assert new_id != job.id
    assert {:ok, path} = Queue.pdf(new_id)
    assert "%PDF-1.4" <> _ = File.read!(path)
  end

  test "the test page goes to the chosen printer" do
    Station.choose_printer("Hall printer")
    Queue.test_print()
    assert [%{title: "Polis test print", printer: "Hall printer", copies: 1}] = printed_whats(1)
  end

  test "a failed print says why, and the round is not counted as printed" do
    RecordingPrinter.fail("out of paper")
    Station.choose_printer("Hall printer")
    id = joined()
    Station.set_switch(id, "print_placecards", false)
    Station.round_received(id, FakeServer.payload(1))
    printed_whats(1)
    :ok = Queue.drain()

    assert [%{status: :failed, error: "out of paper"}] = Queue.jobs()
    assert Station.status_for(id)["last_printed_round"] == nil
  end

  test "the queue keeps the newest fifty" do
    Station.choose_printer("Hall printer")
    for _ <- 1..55, do: Queue.test_print()
    printed_whats(55)
    :ok = Queue.drain()
    assert length(Queue.jobs()) == 50
  end
end
