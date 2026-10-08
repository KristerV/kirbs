defmodule Mix.Tasks.Kirbs.Montonio.SmokeTest do
  use Kirbs.DataCase, async: false

  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{Order, OrderEvent}
  alias Mix.Tasks.Kirbs.Montonio.Smoke

  setup {Req.Test, :set_req_test_from_context}

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  test "refuses without credentials and prints instructions" do
    original = Application.get_env(:kirbs, :montonio)
    Application.put_env(:kirbs, :montonio, Keyword.drop(original, [:access_key, :secret_key]))
    on_exit(fn -> Application.put_env(:kirbs, :montonio, original) end)

    error = assert_raise Mix.Error, fn -> Smoke.run([]) end
    assert error.message =~ "MONTONIO_ACCESS_KEY"
    assert error.message =~ "mix kirbs.montonio.smoke"
  end

  test "creates a payment and --check prints the timeline" do
    seed_shop!()
    item!(bag!(), %{listed_price: 30})

    Req.Test.stub(Kirbs.Montonio, fn conn ->
      Req.Test.json(conn, %{"uuid" => "mont-smoke", "paymentUrl" => "https://pay.example/smoke"})
    end)

    Smoke.run([])
    assert_received {:mix_shell, :info, [message]}
    assert message =~ "https://pay.example/smoke"

    [order] = Order.list_recent!()
    assert order.payment_method == :montonio
    assert order.montonio_order_ref == "mont-smoke"

    assert [:status_changed, :payment_created] =
             Enum.map(OrderEvent.list_for_order!(order.id), & &1.kind)

    Smoke.run(["--check", order.reference])
    assert_received {:mix_shell, :info, [report]}
    assert report =~ "payment_created"
    assert report =~ order.reference
  end

  test "--check of an unknown reference raises" do
    assert_raise Mix.Error, fn -> Smoke.run(["--check", "K0000000"]) end
  end
end
