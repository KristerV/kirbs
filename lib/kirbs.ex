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
    resource Kirbs.Resources.Payout
    resource Kirbs.Resources.YagaListing
    resource Kirbs.Resources.Category
    resource Kirbs.Resources.YagaCategoryMapping
    resource Kirbs.Resources.CategorizationProposal
    resource Kirbs.Resources.SearchSynonym
    resource Kirbs.Resources.Order
    resource Kirbs.Resources.OrderItem
    resource Kirbs.Resources.OrderEvent
  end
end
