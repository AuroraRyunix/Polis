defmodule PolisWeb.Locale do
  @moduledoc """
  Which language the page speaks. The visitor's choice (the `locale` of the
  session, set by `/lang/:code`) wins; until there is one, the browser's
  `Accept-Language`; failing both, English. The result goes into the
  session too, so the LiveView, which sees only the session, speaks the
  same language.

  The printed sheets do not follow this: they speak the language the
  tournament was published in (the round's `locale`), because the players
  read them, not whoever has this page open.
  """

  import Plug.Conn

  @locales ~w(en nl)

  def locales, do: @locales

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      case get_session(conn, "locale") do
        locale when locale in @locales -> locale
        _none -> from_browser(conn)
      end

    Gettext.put_locale(PolisWeb.Gettext, locale)
    conn |> put_session("locale", locale) |> assign(:locale, locale)
  end

  @doc "`on_mount` for the LiveViews: the session's language."
  def on_mount(:default, _params, session, socket) do
    locale = if session["locale"] in @locales, do: session["locale"], else: "en"
    Gettext.put_locale(PolisWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  defp from_browser(conn) do
    header = conn |> get_req_header("accept-language") |> List.first() || ""

    if header |> String.downcase() |> String.trim_leading() |> String.starts_with?("nl"),
      do: "nl",
      else: "en"
  end
end
