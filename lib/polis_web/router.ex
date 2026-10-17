defmodule PolisWeb.Router do
  use PolisWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PolisWeb.Layouts, :root}
    plug PolisWeb.Locale
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # No accounts: the page answers this machine only, unless POLIS_LISTEN=lan
  # opens it to the hall's network (config/runtime.exs). So one browser
  # pipeline and one live_session, and nothing to log in to.
  scope "/", PolisWeb do
    pipe_through :browser
    get "/lang/:code", LangController, :set
    get "/jobs/:id/pdf", JobController, :pdf

    live_session :default, on_mount: {PolisWeb.Locale, :default} do
      live "/", StationLive, :index
      live "/help", HelpLive, :index
    end
  end
end
