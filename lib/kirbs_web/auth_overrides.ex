defmodule KirbsWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  override AshAuthentication.Phoenix.Components.SignIn do
    set :header_text, "Employee Entrance"
  end
end
