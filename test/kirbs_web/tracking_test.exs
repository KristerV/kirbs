defmodule KirbsWeb.TrackingTest do
  use KirbsWeb.ConnCase, async: false

  alias KirbsWeb.Plugs.CaptureUtm
  alias KirbsWeb.Track

  test "CaptureUtm extract whitelists and scrubs params" do
    params = %{
      "utm_source" => "facebook",
      "utm_campaign" => "spring<script>",
      "ad_id" => "123",
      "evil" => "x"
    }

    assert CaptureUtm.extract(params) == %{
             "utm_source" => "facebook",
             "utm_campaign" => "springscript",
             "ad_id" => "123"
           }
  end

  test "landing request with utm params stores attribution in session", %{conn: conn} do
    conn = get(conn, "/?utm_source=meta&utm_medium=paid&utm_campaign=autumn&ad_id=42")

    assert get_session(conn, "kirbs_utm") == %{
             "utm_source" => "meta",
             "utm_medium" => "paid",
             "utm_campaign" => "autumn",
             "ad_id" => "42"
           }

    assert get_session(conn, "ab_funnel_visitor_id")
  end

  test "pixel is off by default" do
    assert Track.meta_pixel_id() == nil
  end

  test "shop experiment is declared with the funnel steps" do
    [experiment] = Kirbs.ABTests.experiments()
    assert experiment.key == :shop
    assert experiment.steps == ~w(shop_viewed item_viewed reserved checkout_started paid)
    assert experiment.entry == "shop_viewed"
    assert experiment.goal == "paid"
  end

  test "tracking events cover the funnel" do
    assert Enum.sort(Track.events()) ==
             Enum.sort([:shop_viewed, :item_viewed, :reserved, :checkout_started, :paid])
  end
end
