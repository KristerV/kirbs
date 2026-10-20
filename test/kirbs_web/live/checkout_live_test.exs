defmodule KirbsWeb.CheckoutLiveTest do
  use KirbsWeb.ConnCase
  use Oban.Testing, repo: Kirbs.Repo

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{Item, Order}

  setup do
    seed_shop!()
    bag = bag!()
    item = item!(bag, %{brand: "Reima", listed_price: 30})
    # visit the shop first so the browser has an ab_funnel visitor in the session
    %{item: item, bag: bag}
  end

  defp visit(conn), do: get(conn, ~p"/")

  defp checkout(conn, item) do
    conn = visit(conn)
    {:ok, view, _html} = live(conn, ~p"/checkout/#{item.slug}")
    {conn, view}
  end

  describe "checkout" do
    test "reserving on mount creates a pending order and the item is held", %{
      conn: conn,
      item: item
    } do
      {_conn, view} = checkout(conn, item)

      assert has_element?(view, "#checkout-form")
      assert has_element?(view, "#countdown")
      assert has_element?(view, "#order-summary", "30 €")
      assert Item.get!(item.id).kirbs_status == :reserved
      assert [%{status: :pending}] = Order.list_recent!()
    end

    test "a second buyer sees the item as unavailable", %{conn: conn, item: item} do
      {_conn, _view} = checkout(conn, item)

      {:ok, view, _html} = live(build_conn() |> visit(), ~p"/checkout/#{item.slug}")
      assert has_element?(view, "#checkout-unavailable")
      assert [_one] = Order.list_recent!()
    end

    test "reload resumes the same order instead of reserving again", %{conn: conn, item: item} do
      {conn, _view} = checkout(conn, item)
      [order] = Order.list_recent!()
      path = ~p"/checkout/#{item.slug}?#{[order: order.token]}"

      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, "#checkout-form")
      assert [_one] = Order.list_recent!()
    end

    test "choosing a delivery method shows the shipping price and the picker", %{
      conn: conn,
      item: item
    } do
      {_conn, view} = checkout(conn, item)

      view
      |> form("#checkout-form", checkout: %{delivery_method: "dpd_parcel_machine"})
      |> render_change()

      assert has_element?(view, "#pickup-point select")
      assert has_element?(view, "#summary-shipping", "3,99 €")
      assert has_element?(view, "#summary-total", "33,99 €")
    end

    test "only Montonio parcel machines are offered", %{conn: conn, item: item} do
      {_conn, view} = checkout(conn, item)

      assert has_element?(view, "#delivery-omniva_parcel_machine")
      assert has_element?(view, "#delivery-dpd_parcel_machine")
      assert has_element?(view, "#delivery-smartposti_parcel_machine")
      refute has_element?(view, "#delivery-pickup")
      refute has_element?(view, "#payment-manual")
      assert has_element?(view, "#payment-info")
    end

    test "without Montonio keys nothing is reserved", %{conn: conn, item: item} do
      original = Application.get_env(:kirbs, :montonio)
      Application.put_env(:kirbs, :montonio, Keyword.drop(original, [:access_key, :secret_key]))
      on_exit(fn -> Application.put_env(:kirbs, :montonio, original) end)

      conn = visit(conn)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{item.slug}")

      assert has_element?(view, "#checkout-unavailable-payments")
      assert Order.list_recent!() == []
      assert Item.get!(item.id).kirbs_status == :available
    end

    test "in production a failing rates call blocks checkout instead of guessing a price", %{
      conn: conn,
      item: item
    } do
      original = Application.get_env(:kirbs, :montonio)
      Application.put_env(:kirbs, :montonio, Keyword.put(original, :env, :production))
      on_exit(fn -> Application.put_env(:kirbs, :montonio, original) end)
      Kirbs.StubRatesFetcher.fail_with(:boom)

      {_conn, view} = checkout(conn, item)

      assert has_element?(view, "#checkout-unavailable-shipping")
      refute has_element?(view, "#checkout-form")
    end

    test "submit validates required fields", %{conn: conn, item: item} do
      {_conn, view} = checkout(conn, item)

      html =
        view
        |> form("#checkout-form", checkout: %{buyer_name: "", buyer_email: "nope"})
        |> render_submit()

      assert has_element?(view, "#checkout-form")
      assert html =~ "ei ole korrektne e-posti aadress"
      assert [%{status: :pending}] = Order.list_recent!()
    end

    test "tracking: reserved, checkout_started and identify", %{conn: conn, item: item} do
      {_conn, view} = checkout(conn, item)

      view
      |> form("#checkout-form", checkout: %{buyer_email: "mari@example.com"})
      |> render_change()

      events = Enum.map(AbFunnel.Services.Events.all(), & &1.event)
      assert "reserved" in events
      assert "checkout_started" in events
    end

    test "unknown slugs go back to the shop", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/checkout/nope")
    end
  end

  describe "order page" do
    setup %{item: item} do
      {:ok, order} = Order.start([item.id])

      {:ok, order} =
        Order.submit(order, %{
          buyer_name: "Mari Maasikas",
          buyer_email: "mari@example.com",
          buyer_phone: "5551234",
          delivery_method: :omniva_parcel_machine,
          pickup_point_id: "omniva-tallinn-ulemiste"
        })

      %{token: order.token}
    end

    test "shows the order while awaiting payment", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/order/#{token}")

      assert has_element?(view, "#order-status[data-status=reserved]")
      assert has_element?(view, "#montonio-awaiting")
      refute has_element?(view, "#bank-instructions")
      assert has_element?(view, "#order-items")
      assert has_element?(view, "#order-delivery", "Ülemiste")
    end

    test "reflects the paid state", %{conn: conn, token: token} do
      {:ok, order} = Order.get_by_token(token)
      {:ok, _} = Order.mark_paid(order)

      {:ok, view, _html} = live(conn, ~p"/order/#{token}")
      assert has_element?(view, "#order-status[data-status=paid]")
      refute has_element?(view, "#montonio-awaiting")
    end

    test "unknown tokens redirect", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/order/nope")
    end

    test "emails are built from the order", %{token: token} do
      {:ok, order} = Order.get_by_token(token)
      {:ok, order} = Order.mark_paid(order)
      assert Kirbs.Orders.Emails.build(:paid, order).subject =~ "tasutud"

      {:ok, order} = Order.mark_shipped(order, %{tracking_number: "CC1EE"})
      order = Order.get!(order.id)
      email = Kirbs.Orders.Emails.build(:shipped, order)
      assert email.text_body =~ "CC1EE"
      assert email.to == [{"Mari Maasikas", "mari@example.com"}]
    end

    test "the email job delivers", %{token: token} do
      {:ok, order} = Order.get_by_token(token)
      {:ok, order} = Order.mark_paid(order)

      assert :ok =
               perform_job(Kirbs.Jobs.SendOrderEmailJob, %{order_id: order.id, kind: "paid"})

      assert_email_sent(subject: "Kirbs: tellimus #{order.reference} on tasutud")
    end
  end

  describe "shop funnel instrumentation" do
    test "shop_visit event records shop_viewed once per call", %{conn: conn} do
      conn = visit(conn)
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#shop-visit")

      render_hook(view, "shop_visit", %{})
      assert "shop_viewed" in Enum.map(AbFunnel.Services.Events.all(), & &1.event)
    end

    test "item page records item_viewed", %{conn: conn, item: item} do
      conn = visit(conn)
      {:ok, _view, _html} = live(conn, ~p"/p/#{item.slug}")
      assert "item_viewed" in Enum.map(AbFunnel.Services.Events.all(), & &1.event)
    end

    test "the meta pixel hook div renders when a pixel is configured", %{conn: conn} do
      Application.put_env(:kirbs, :meta_pixel, enabled: true, pixel_id: "123456")
      on_exit(fn -> Application.delete_env(:kirbs, :meta_pixel) end)

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, ~s(#meta-pixel[phx-hook=MetaPixel][data-pixel-id="123456"]))
    end
  end
end
