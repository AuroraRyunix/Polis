defmodule Polis.PrinterTest do
  @moduledoc """
  The two real printer roads, without a printer: what `lp` and `lpstat`
  are asked and how their answers are read, and what PowerShell is given.
  The runners are swapped for recorders; nothing is started and nothing
  prints.
  """

  use ExUnit.Case, async: false

  alias Polis.{FakeServer, Layout}
  alias Polis.Printer.{Cups, Windows}

  @moduletag :tmp_dir

  setup do
    on_exit(fn ->
      Application.delete_env(:polis, :cups_cmd)
      Application.delete_env(:polis, :windows_cmd)
    end)

    me = self()

    recorder = fn answers ->
      fn command, args, opts ->
        send(me, {:ran, command, args, opts})
        Map.get(answers, {command, hd(args)}, {"", 0})
      end
    end

    %{recorder: recorder}
  end

  defp job(dir, overrides \\ %{}) do
    doc = Layout.pairings(FakeServer.payload(4))

    Map.merge(
      %{
        pdf: Path.join(dir, "abc-1234.pdf"),
        layout: doc,
        printer: "Hall printer",
        copies: 2,
        title: "Club Open - Pairings 4",
        paper: :a4
      },
      overrides
    )
  end

  describe "CUPS" do
    test "lp gets the printer, the title, the copies, the paper and the file", %{tmp_dir: dir} do
      assert Cups.print_args(job(dir)) ==
               ["-d", "Hall printer", "-t", "Club Open - Pairings 4", "-n", "2", "-o", "media=A4"] ++
                 [Path.join(dir, "abc-1234.pdf")]

      assert "media=Letter" in Cups.print_args(job(dir, %{paper: :letter}))
    end

    test "a print runs lp and takes exit 0 for done", %{tmp_dir: dir, recorder: recorder} do
      Application.put_env(:polis, :cups_cmd, recorder.(%{}))
      assert :ok = Cups.print(job(dir))
      assert_received {:ran, "lp", ["-d", "Hall printer" | _], _opts}
    end

    test "lp's own words come back when it refuses", %{tmp_dir: dir, recorder: recorder} do
      Application.put_env(
        :polis,
        :cups_cmd,
        recorder.(%{{"lp", "-d"} => {"lp: The printer or class does not exist.\n", 1}})
      )

      assert {:error, "lp: The printer or class does not exist."} = Cups.print(job(dir))
    end

    test "the printer list: lpstat -e, and lpstat -a where -e is too new", %{recorder: recorder} do
      Application.put_env(
        :polis,
        :cups_cmd,
        recorder.(%{{"lpstat", "-e"} => {"Hall\nOffice_2\n", 0}})
      )

      assert {:ok, ["Hall", "Office_2"]} = Cups.printers()

      Application.put_env(
        :polis,
        :cups_cmd,
        recorder.(%{
          {"lpstat", "-e"} => {"lpstat: invalid option -e", 1},
          {"lpstat", "-a"} =>
            {"Hall accepting requests since Sat 17 Oct\nOffice accepting requests since Fri\n", 0}
        })
      )

      assert {:ok, ["Hall", "Office"]} = Cups.printers()
    end

    test "the default printer, or none", %{recorder: recorder} do
      Application.put_env(
        :polis,
        :cups_cmd,
        recorder.(%{{"lpstat", "-d"} => {"system default destination: Hall\n", 0}})
      )

      assert Cups.default_printer() == "Hall"

      Application.put_env(
        :polis,
        :cups_cmd,
        recorder.(%{{"lpstat", "-d"} => {"no system default destination\n", 0}})
      )

      assert Cups.default_printer() == nil
    end
  end

  describe "Windows" do
    test "PowerShell runs the script with no profile, no prompt, and only the job file named" do
      args = Windows.args("print", "C:\\data\\jobs\\abc.print.json")

      assert [
               "-NoProfile",
               "-NonInteractive",
               "-ExecutionPolicy",
               "Bypass",
               "-File",
               script | rest
             ] =
               args

      assert String.ends_with?(script, "print.ps1")
      assert File.exists?(script)
      assert rest == ["-Action", "print", "-Job", "C:\\data\\jobs\\abc.print.json"]
      assert Windows.args("printers") |> Enum.take(-2) == ["-Action", "printers"]
    end

    test "the job file has the printer, copies, title, paper and the whole layout", %{
      tmp_dir: dir
    } do
      job = job(dir, %{printer: "Kantoor – Ūnicode", paper: :letter})
      json = Windows.job_json(job)

      assert json["printer"] == "Kantoor – Ūnicode"
      assert json["copies"] == 2
      assert json["paper"] == "letter"
      assert json["title"] == "Club Open - Pairings 4"
      assert json["layout"] == Layout.to_json(job.layout)
      assert Jason.decode!(Jason.encode!(json)) == json
    end

    test "a print writes the job file, hands its path over, reads ok, and removes the file",
         %{tmp_dir: dir, recorder: recorder} do
      me = self()

      Application.put_env(:polis, :windows_cmd, fn "powershell.exe", args, _opts ->
        file = List.last(args)
        send(me, {:job_file, file, File.read!(file)})
        {"ok\r\n", 0}
      end)

      assert :ok = Windows.print(job(dir))
      assert_received {:job_file, file, body}
      assert file == Path.join(dir, "abc-1234.print.json")
      assert %{"printer" => "Hall printer"} = Jason.decode!(body)
      refute File.exists?(file)

      Application.put_env(:polis, :windows_cmd, recorder.(%{}))
      # Exit 0 without "ok" is not a print.
      assert {:error, _} = Windows.print(job(dir))
    end

    test "the script's last line is the reason when it fails", %{tmp_dir: dir} do
      Application.put_env(:polis, :windows_cmd, fn _cmd, _args, _opts ->
        {"no printer called Hall printer\r\n", 3}
      end)

      assert {:error, "no printer called Hall printer"} = Windows.print(job(dir))
    end

    test "the printer list is one name a line" do
      Application.put_env(:polis, :windows_cmd, fn _cmd, ["-NoProfile" | _], _opts ->
        {"Microsoft Print to PDF\r\nHall printer\r\n\r\n", 0}
      end)

      assert {:ok, ["Microsoft Print to PDF", "Hall printer"]} = Windows.printers()
    end
  end

  test "the dry run is the road in the tests and in development" do
    assert Polis.Printer.backend() in [Polis.Printer.DryRun, Polis.RecordingPrinter]
    assert Polis.Printer.system_backend({:win32, :nt}) == Windows
    assert Polis.Printer.system_backend({:unix, :linux}) == Cups
    assert Polis.Printer.system_backend({:unix, :darwin}) == Cups
  end
end
