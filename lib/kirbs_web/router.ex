defmodule KirbsWeb.Router do
  use KirbsWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KirbsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", KirbsWeb do
    pipe_through :browser

    live "/", LandingLive.Index, :index

    ash_authentication_live_session :authenticated_routes,
      on_mount: {KirbsWeb.LiveUserAuth, :live_user_required} do
      live "/dashboard", DashboardLive.Index, :index
      live "/bags", BagLive.Index, :index
      live "/bags/capture", BagLive.Capture, :capture
      live "/bags/:id", BagLive.Show, :show
      live "/items/:id", ItemLive.Show, :show
      live "/review", ReviewLive.Index, :index
      live "/settings", SettingsLive.Index, :index
    end
  end

  scope "/", KirbsWeb do
    pipe_through :browser

    get "/uploads/:filename", PageController, :serve_upload
    auth_routes AuthController, Kirbs.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route path: "/login",
                  register_path: nil,
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{KirbsWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    KirbsWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  KirbsWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Kirbs.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [KirbsWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Kirbs.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [KirbsWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", KirbsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:kirbs, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KirbsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:kirbs, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
