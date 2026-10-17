defmodule OpenPairingsPolisWeb do
  @moduledoc """
  `use OpenPairingsPolisWeb, :live_view`: what the core's
  `use PairingsEngineWeb, :live_view` gives a page, with the plugin's own
  message catalogue in place of the core's.
  """

  def live_view do
    quote do
      use Phoenix.LiveView
      use Gettext, backend: OpenPairingsPolis.Gettext

      import PairingsEngineWeb.CoreComponents

      alias PairingsEngineWeb.Layouts

      on_mount OpenPairingsPolisWeb.Locale
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
