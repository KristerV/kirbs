defmodule KirbsWeb.CheckoutMontonioTest do
  use KirbsWeb.ConnCase
  use Oban.Testing, repo: Kirbs.Repo

  import Phoenix.LiveViewTest
  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{Item, Order}

  setup {Req.Test, :set_req_test_from_context}

  setup do
    seed_shop!()
    item = item!(bag!(), %{listed_price: 30})
    %{item: item}
  end

  defp checkout(conn, item) do
    conn = get(conn, ~p"/")
    {:ok, view, _html} = live(conn, ~p"/checkout/#{item.slug}")
    view
  end

  defp params(overrides \\ %{}) do
    Map.merge(
      %{
        "buyer_name" => "Mari Maasikas",
        "buyer_email" => "mari@example.com",
        "buyer_phone" => "5551234",
        "delivery_method" => "omniva_parcel_machine",
        "pickup_point_id" => "omniva-tallinn-ulemiste",
        "payment_method" => "montonio"
      },
      overrides
    )
  end

  defp stub_create_order do
    test_pid = self()

    Req.Test.stub(Kirbs.Montonio, fn conn ->
      assert conn.request_path == "/api/orders"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      %{"data" => jwt} = Jason.decode!(raw)
      send(test_pid, {:create_order, Kirbs.MontonioHelpers.decode_unverified(jwt)})

      Req.Test.json(conn, %{"uuid" => "mont-1", "paymentUrl" => "https://pay.example/mont-1"})
    end)
  end

  test "the Montonio option is offered when configured and submit redirects to the bank", %{
    conn: conn,
    item: item
  } do
    stub_create_order()
    view = checkout(conn, item)
    assert has_element?(view, "#payment-montonio")
    assert has_element?(view, "#payment-manual")

    view
    |> form("#checkout-form", checkout: %{delivery_method: "omniva_parcel_machine"})
    |> render_change()

    assert {:error, {:redirect, %{to: "https://pay.example/mont-1"}}} =
             view |> form("#checkout-form", checkout: params()) |> render_submit()

    assert_received {:create_order, claims}
    [order] = Order.list_recent!()
    assert order.status == :reserved
    assert order.payment_method == :montonio
    assert order.montonio_order_ref == "mont-1"
    assert order.montonio_payment_url == "https://pay.example/mont-1"
    assert claims["merchantReference"] == order.reference
    assert claims["grandTotal"] == 33.49
    assert claims["returnUrl"] =~ "/checkout/montonio/return"
    assert claims["notificationUrl"] =~ "/webhooks/montonio"
    refute_enqueued(worker: Kirbs.Jobs.SendOrderEmailJob, args: %{kind: "received"})
  end

  test "Montonio failure cancels the order and frees the item", %{conn: conn, item: item} do
    Req.Test.stub(Kirbs.Montonio, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "down"})
    end)

    view = checkout(conn, item)

    view
    |> form("#checkout-form", checkout: %{delivery_method: "omniva_parcel_machine"})
    |> render_change()

    view |> form("#checkout-form", checkout: params()) |> render_submit()

    assert has_element?(view, "#checkout-payment-failed")
    assert has_element?(view, "#retry-checkout")
    assert [%{status: :cancelled}] = Order.list_recent!()
    assert Item.get!(item.id).kirbs_status == :available
  end

  test "without Montonio keys only bank transfer is offered and montonio is coerced", %{
    conn: conn,
    item: item
  } do
    original = Application.get_env(:kirbs, :montonio)
    Application.put_env(:kirbs, :montonio, Keyword.drop(original, [:access_key, :secret_key]))
    on_exit(fn -> Application.put_env(:kirbs, :montonio, original) end)

    view = checkout(conn, item)
    refute has_element?(view, "#payment-montonio")
    assert has_element?(view, "#payment-manual")

    view
    |> form("#checkout-form", checkout: %{delivery_method: "omniva_parcel_machine"})
    |> render_change()

    assert {:error, {:live_redirect, %{to: "/order/" <> _}}} =
             view |> element("#checkout-form") |> render_submit(%{"checkout" => params()})

    assert [%{payment_method: :manual}] = Order.list_recent!()
  end

  describe "searchable pickup points (Montonio provider)" do
    setup do
      Application.put_env(:kirbs, :pickup_points_provider, Kirbs.Shipping.PickupPoints.Montonio)
      Kirbs.MontonioHelpers.reset_store()

      on_exit(fn ->
        Application.put_env(:kirbs, :pickup_points_provider, Kirbs.Shipping.PickupPoints.Static)
        Kirbs.MontonioHelpers.reset_store()
      end)

      Req.Test.stub(Kirbs.Montonio, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        points =
          case conn.params["carrierCode"] do
            "omniva" ->
              [
                %{
                  "id" => "pp-tln",
                  "name" => "Ülemiste",
                  "type" => "parcelMachine",
                  "streetAddress" => "Suur-Sõjamäe 4",
                  "locality" => "Tallinn",
                  "carrierCode" => "omniva"
                },
                %{
                  "id" => "pp-tartu",
                  "name" => "Lõunakeskus",
                  "type" => "parcelMachine",
                  "streetAddress" => "Ringtee 75",
                  "locality" => "Tartu",
                  "carrierCode" => "omniva"
                }
              ]

            _ ->
              []
          end

        Req.Test.json(conn, %{"pickupPoints" => points})
      end)

      :ok
    end

    test "filters by typed text", %{conn: conn, item: item} do
      view = checkout(conn, item)

      view
      |> form("#checkout-form", checkout: %{delivery_method: "omniva_parcel_machine"})
      |> render_change()

      assert has_element?(view, "#pickup-point option", "Ülemiste")
      assert has_element?(view, "#pickup-point option", "Lõunakeskus")

      view
      |> element("#checkout-form")
      |> render_change(%{
        "checkout" => %{"delivery_method" => "omniva_parcel_machine"},
        "point_search" => "tartu"
      })

      refute has_element?(view, "#pickup-point option", "Ülemiste")
      assert has_element?(view, "#pickup-point option", "Ringtee 75, Tartu")

      view
      |> element("#checkout-form")
      |> render_change(%{
        "checkout" => %{"delivery_method" => "omniva_parcel_machine"},
        "point_search" => "zzz"
      })

      assert has_element?(view, "#no-pickup-points")
    end

    test "Order.submit validates the point through the provider", %{item: item} do
      {:ok, order} = Order.start([item.id])

      attrs = %{
        buyer_name: "A B",
        buyer_email: "a@b.ee",
        buyer_phone: "5551234",
        delivery_method: :omniva_parcel_machine
      }

      assert {:error, _} = Order.submit(order, Map.put(attrs, :pickup_point_id, "nope"))
      assert {:ok, _} = Order.submit(order, Map.put(attrs, :pickup_point_id, "pp-tln"))
    end
  end

  test "shipping price depends on the parcel size", %{conn: conn} do
    big = item!(bag!(), %{listed_price: 30, parcel_size: :l})
    view = checkout(conn, big)

    view
    |> form("#checkout-form", checkout: %{delivery_method: "dpd_parcel_machine"})
    |> render_change()

    assert has_element?(view, "#summary-shipping", "5,49 €")
  end
end
