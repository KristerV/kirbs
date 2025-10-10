defmodule KirbsWeb.PageController do
  use KirbsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
