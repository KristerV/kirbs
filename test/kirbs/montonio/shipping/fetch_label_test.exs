defmodule Kirbs.Montonio.Shipping.FetchLabelTest do
  use ExUnit.Case, async: false

  alias Kirbs.Montonio.Shipping.FetchLabel

  test "returns the url from a synchronous label file" do
    Req.Test.stub(Kirbs.Montonio, fn conn ->
      assert conn.request_path == "/api/v2/label-files"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert %{"shipmentIds" => ["s1"], "synchronous" => true} = Jason.decode!(raw)
      Req.Test.json(conn, %{"id" => "lf1", "status" => "ready", "labelFileUrl" => "https://l.test/a.pdf"})
    end)

    assert {:ok, "https://l.test/a.pdf"} = FetchLabel.run(%{shipment_ids: ["s1"]})
  end

  test "polls when pending" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(Kirbs.Montonio, fn conn ->
      case {conn.method, Agent.get_and_update(counter, &{&1, &1 + 1})} do
        {"POST", _} ->
          Req.Test.json(conn, %{"id" => "lf1", "status" => "pending", "labelFileUrl" => nil})

        {"GET", 1} ->
          assert conn.request_path == "/api/v2/label-files/lf1"
          Req.Test.json(conn, %{"id" => "lf1", "status" => "pending", "labelFileUrl" => nil})

        {"GET", _} ->
          Req.Test.json(conn, %{"id" => "lf1", "status" => "ready", "labelFileUrl" => "https://l.test/b.pdf"})
      end
    end)

    assert {:ok, "https://l.test/b.pdf"} = FetchLabel.run(%{shipment_ids: ["s1"]})
  end

  test "fails when never ready or failed" do
    Req.Test.stub(Kirbs.Montonio, fn conn ->
      Req.Test.json(conn, %{"id" => "lf1", "status" => "pending", "labelFileUrl" => nil})
    end)

    assert {:error, :label_not_ready} = FetchLabel.run(%{shipment_ids: ["s1"]})

    Req.Test.stub(Kirbs.Montonio, fn conn ->
      Req.Test.json(conn, %{"id" => "lf1", "status" => "failed", "labelFileUrl" => nil})
    end)

    assert {:error, :label_creation_failed} = FetchLabel.run(%{shipment_ids: ["s1"]})
    assert {:error, :missing_shipment_ids} = FetchLabel.run(%{shipment_ids: []})
  end
end
