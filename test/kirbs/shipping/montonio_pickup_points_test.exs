defmodule Kirbs.Shipping.MontonioPickupPointsTest do
  use ExUnit.Case, async: false

  import Kirbs.MontonioHelpers

  alias Kirbs.Shipping.MontonioPickupPoints

  setup do
    reset_store()
    original = Application.get_env(:kirbs, :montonio)
    Application.put_env(:kirbs, :montonio, Keyword.put(original, :carriers, ["omniva", "smartpost"]))
    on_exit(fn -> Application.put_env(:kirbs, :montonio, original) end)

    {:ok, calls} = Agent.start_link(fn -> [] end)

    Req.Test.stub(Kirbs.Montonio, fn conn ->
      assert conn.request_path == "/api/v2/shipping-methods/pickup-points"
      params = Plug.Conn.fetch_query_params(conn).query_params
      Agent.update(calls, &[params | &1])

      points =
        case params["carrierCode"] do
          "omniva" ->
            [
              %{"id" => "o1", "name" => "Telliskivi Selver", "type" => "parcelMachine", "streetAddress" => "Telliskivi 1", "locality" => "Tallinn", "postalCode" => "10111", "carrierCode" => "omniva"},
              %{"id" => "o2", "name" => "Tartu Kvartal", "type" => "parcelMachine", "streetAddress" => "Riia 2", "locality" => "Tartu", "postalCode" => "50000", "carrierCode" => "omniva"}
            ]

          _ ->
            [%{"id" => "s1", "name" => "Posti Tallinn", "type" => "postOffice", "streetAddress" => "Pärnu mnt 5", "locality" => "Tallinn", "postalCode" => "10100", "carrierCode" => "smartpost"}]
        end

      Req.Test.json(conn, %{"pickupPoints" => points, "countryCode" => "ee"})
    end)

    %{calls: calls}
  end

  test "list fetches lazily, filters and caches", %{calls: calls} do
    assert {:ok, [_, _, _]} = MontonioPickupPoints.list()
    assert {:ok, [%{id: "o1"}]} = MontonioPickupPoints.list(carrier: "omniva", search: "telliskivi")
    assert {:ok, [%{id: "o2"}]} = MontonioPickupPoints.list(carrier: "omniva", search: "TARTU")
    assert {:ok, [%{id: "s1"}]} = MontonioPickupPoints.list(type: "postOffice")
    # 2 carriers fetched once, then served from cache
    assert length(Agent.get(calls, & &1)) == 2
    assert Enum.all?(Agent.get(calls, & &1), &(&1["countryCode"] == "ee"))
  end

  test "get finds by id" do
    assert {:ok, %{name: "Posti Tallinn"}} = MontonioPickupPoints.get("s1")
    assert {:error, :not_found} = MontonioPickupPoints.get("nope")
  end

  test "refresh keeps old data on failure" do
    assert {:ok, %{failed: []}} = MontonioPickupPoints.refresh()

    Req.Test.stub(Kirbs.Montonio, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, [_, _]} = MontonioPickupPoints.refresh()
    assert {:ok, [_, _, _]} = MontonioPickupPoints.list()
  end
end
