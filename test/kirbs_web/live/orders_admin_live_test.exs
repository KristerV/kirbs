defmodule KirbsWeb.OrdersAdminLiveTest do
  use KirbsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{Item, Order}

  @buyer %{
    buyer_name: "Mari Maasikas",
    buyer_email: "mari@example.com",
    buyer_phone: "5551234",
    delivery_method: :dpd_parcel_machine,
    pickup_point_id: "dpd-tartu-tasku"
  }

  setup do
    seed_shop!()
    item = item!(bag!(), %{listed_price: 20})
    {:ok, order} = Order.start([item.id])
    {:ok, order} = Order.submit(order, @buyer)
    %{item: item, order: order}
  end

  defp admin_conn(conn) do
    user =
      Ash.create!(
        Kirbs.Accounts.User,
        %{
          email: "admin#{System.unique_integer([:positive])}@example.com",
          password: "supersecret123",
          password_confirmation: "supersecret123"
        },
        action: :register_with_password,
        authorize?: false
      )

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  test "requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/orders")
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/orders/shipping")
  end

  describe "orders list" do
    test "lists orders and marks one paid", %{conn: conn, order: order, item: item} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/orders")
      assert has_element?(view, "#orders tr", order.reference)

      view |> element("#mark-paid-#{order.id}") |> render_click()

      assert Order.get!(order.id).status == :paid
      assert Item.get!(item.id).kirbs_status == :sold
      refute has_element?(view, "#mark-paid-#{order.id}")
    end

    test "cancel releases the item", %{conn: conn, order: order, item: item} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/orders")
      view |> element("#cancel-#{order.id}") |> render_click()
      assert Order.get!(order.id).status == :cancelled
      assert Item.get!(item.id).kirbs_status == :available
    end

    test "filters", %{conn: conn, order: order} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/orders?filter=paid")
      refute has_element?(view, "#orders tr", order.reference)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/orders?filter=awaiting_payment")
      assert has_element?(view, "#orders tr", order.reference)
    end
  end

  describe "manual postage" do
    test "only paid orders are listed; shipping records the tracking number", %{
      conn: conn,
      order: order
    } do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/orders/shipping")
      refute has_element?(view, "#orders-#{order.id}")

      {:ok, _} = Order.mark_paid(order)
      {:ok, view, _html} = live(admin_conn(conn), ~p"/orders/shipping")
      assert has_element?(view, "#orders-#{order.id}", "Tasku Pickup")

      view
      |> form("#ship-form-#{order.id}", ship: %{tracking_number: "CC9EE"})
      |> render_submit(%{id: order.id})

      shipped = Order.get!(order.id)
      assert shipped.status == :shipped
      assert shipped.tracking_number == "CC9EE"
      refute has_element?(view, "#orders-#{order.id}")
    end
  end
end
