defmodule PolisWeb do
  @moduledoc """
  The station's page: the joined tournaments, the field that joins one, the
  printer, and the queue. And the help. Nothing else, on purpose: the
  tournaments are OpenPairings'.
  """

  def static_paths, do: ~w(app.js app.css)

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html]
      import Plug.Conn
      use Gettext, backend: PolisWeb.Gettext
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView
      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Gettext, backend: PolisWeb.Gettext
      import PolisWeb.Components
      alias PolisWeb.Layouts
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
