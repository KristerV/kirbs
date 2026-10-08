defmodule KirbsWeb.OrdersShowLiveTest do
  use KirbsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{Order, OrderEvent}

  setup do
    seed_shop!()
    item = item!(bag!(), %{listed_price: 20})
    {:ok, order} = Order.start([item.id])

    {:ok, order} =
      Order.submit(order, %{
        buyer_name: "Mari Maasikas",
        buyer_email: "mari@example.com",
        buyer_phone: "5551234",
        delivery_method: :dpd_parcel_machine,
        pickup_point_id: "dpd-tartu-tasku"
      })

    %{order: order}
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

  test "requires login", %{conn: conn, order: order} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/orders/#{order.id}")
  end

  test "list rows link to the detail page", %{conn: conn, order: order} do
    {:ok, view, _} = live(admin_conn(conn), ~p"/orders")
    view |> element("#order-link-#{order.id}") |> render_click()
    assert_redirect(view, ~p"/orders/#{order.id}")
  end

  test "shows facts and timeline, and adds a note", %{conn: conn, order: order} do
    {:ok, view, _} = live(admin_conn(conn), ~p"/orders/#{order.id}")

    assert has_element?(view, "#order-reference", order.reference)
    assert has_element?(view, "#order-buyer", "mari@example.com")
    assert has_element?(view, "#order-delivery")
    assert has_element?(view, "#order-payment")
    assert has_element?(view, "#order-shipment")
    assert has_element?(view, "#order-timeline [data-kind=status_changed]")

    view |> form("#note-form", note: %{summary: "Buyer called"}) |> render_submit()

    assert has_element?(view, "#order-timeline [data-kind=manual_note]", "Buyer called")

    assert [%{kind: :status_changed}, %{kind: :manual_note, source: :admin}] =
             OrderEvent.list_for_order!(order.id)
  end

  test "unknown order redirects back", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/orders"}}} =
             live(admin_conn(conn), ~p"/orders/#{Ecto.UUID.generate()}")
  end
end
