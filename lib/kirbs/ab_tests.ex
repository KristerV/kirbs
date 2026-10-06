defmodule Kirbs.ABTests do
  @moduledoc """
  Experiments run by ab_funnel. Dashboard: /admin/ab.

  ## :shop

  WHAT IS BEING TESTED (default, TBD by owner): the ad-landing headline and layout shown
  to visitors arriving from Meta ads. `:control` is the current landing page, `:treatment`
  is the challenger headline/layout. Branch in LiveViews with

      AbFunnel.variant(socket, :shop) == "treatment"

  or `@ab_funnel_variant` in templates. Change the variants below once the owner decides
  what is actually being compared; the funnel steps stay the same.

  Funnel: shop_viewed (entry) -> item_viewed -> reserved -> checkout_started -> paid (goal).
  See docs/tracking.md for where each event is fired.
  """
  use AbFunnel.Experiments

  def experiments do
    [
      %{
        key: :shop,
        label: "Shop landing",
        variants: [:control, :treatment],
        steps: ~w(shop_viewed item_viewed reserved checkout_started paid),
        entry: "shop_viewed",
        goal: "paid"
      }
    ]
  end
end
