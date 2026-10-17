defmodule Polis.Join do
  @moduledoc """
  Joining a tournament: the whole of it is one link.

  In OpenPairings, the plugin page of a tournament makes a link -
  `https://<server>/p/polis/join/<code>`, good for fifteen minutes and for
  one station - shown as text and as a QR code. The station is given that
  link (pasted into its page) and does the rest: it POSTs to the very same
  address who it is, and the answer is its own long key, where the link's
  socket is, what the server is called and which tournament this is. The
  key is stored in the state file and never shown. Nobody types an
  address; nobody sees a key.

  Any prefix before `/p/` is accepted, so an OpenPairings that lives under
  a sub-path works. A link for the other hall product (`/p/nunki/...`, the
  announcer) is refused in words, before anything is sent.
  """

  alias Polis.Protocol

  @doc """
  `{:ok, attrs}` - what `Polis.State.add_tournament/1` takes - or
  `{:error, reason}`: `:not_a_link`, `{:wrong_product, name}`,
  `:used_or_expired`, `:version`, `:not_a_server`, `:unreachable`.
  """
  def redeem(link, identity, req_options \\ []) do
    with {:ok, uri} <- parse(link) do
      url = URI.to_string(%{uri | query: nil, fragment: nil})

      options =
        Keyword.merge(
          [
            json: identity,
            retry: false,
            receive_timeout: 15_000,
            connect_options: [timeout: 10_000]
          ],
          req_options
        )

      case Req.post(url, options) do
        {:ok,
         %{
           status: 200,
           body: %{"key" => key, "socket" => socket, "tournament" => %{"id" => tid} = t} = body
         }}
        when is_binary(key) and is_binary(socket) ->
          {:ok,
           %{
             "socket_url" => socket_url(uri, socket),
             "key" => key,
             "server" => body["server"] || uri.host,
             "tournament_id" => tid,
             "name" => t["name"] || ""
           }}

        {:ok, %{status: status}} when status in [404, 410] ->
          {:error, :used_or_expired}

        {:ok, %{status: 409}} ->
          {:error, :version}

        {:ok, _other} ->
          {:error, :not_a_server}

        {:error, _exception} ->
          {:error, :unreachable}
      end
    end
  end

  @doc "The join link's parts, `{:error, :not_a_link}` or `{:error, {:wrong_product, id}}`."
  def parse(link) when is_binary(link) do
    with {:ok, %URI{scheme: scheme, host: host, path: path} = uri}
         when scheme in ["http", "https"] and is_binary(host) and host != "" and is_binary(path) <-
           URI.new(String.trim(link)),
         [_, product, code] <- Regex.run(~r{/p/([a-z0-9_-]+)/join/([^/]+)/?$}, path) do
      cond do
        code == "" -> {:error, :not_a_link}
        product == Protocol.product() -> {:ok, uri}
        true -> {:error, {:wrong_product, product}}
      end
    else
      _other -> {:error, :not_a_link}
    end
  end

  def parse(_other), do: {:error, :not_a_link}

  # Where the socket is: the same host and port as the join link, ws for
  # http, wss for https. The path comes from the server (absolute), so a
  # sub-path is the server's to include.
  defp socket_url(uri, path) do
    scheme = if uri.scheme == "https", do: "wss", else: "ws"
    URI.to_string(%URI{scheme: scheme, host: uri.host, port: uri.port, path: path})
  end
end
