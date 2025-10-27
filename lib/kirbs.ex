defmodule Kirbs do
  use Ash.Domain, otp_app: :kirbs, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Kirbs.Resources.Client
    resource Kirbs.Resources.Bag
    resource Kirbs.Resources.Item
    resource Kirbs.Resources.Image
    resource Kirbs.Resources.Settings
  end
end
