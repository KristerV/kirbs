defmodule Kirbs.Accounts do
  use Ash.Domain, otp_app: :kirbs, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Kirbs.Accounts.Token
    resource Kirbs.Accounts.User
  end
end
