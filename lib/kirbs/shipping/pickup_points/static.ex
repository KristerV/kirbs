defmodule Kirbs.Shipping.PickupPoints.Static do
  @moduledoc "Hardcoded stand-in until the Montonio pickup-point sync exists (Phase 6)."
  @behaviour Kirbs.Shipping.PickupPoints.Provider

  @points [
    %{
      id: "omniva-tallinn-ulemiste",
      carrier: :omniva,
      name: "Ülemiste keskuse pakiautomaat",
      address: "Suur-Sõjamäe 4, Tallinn"
    },
    %{
      id: "omniva-tartu-lounakeskus",
      carrier: :omniva,
      name: "Lõunakeskuse pakiautomaat",
      address: "Ringtee 75, Tartu"
    },
    %{
      id: "omniva-parnu-kvartal",
      carrier: :omniva,
      name: "Kvartali pakiautomaat",
      address: "Pikk 20a, Pärnu"
    },
    %{
      id: "dpd-tallinn-rocca",
      carrier: :dpd,
      name: "Rocca al Mare Pickup",
      address: "Paldiski mnt 102, Tallinn"
    },
    %{
      id: "dpd-tartu-tasku",
      carrier: :dpd,
      name: "Tasku Pickup",
      address: "Narva mnt 2, Tartu"
    },
    %{
      id: "smartposti-tallinn-viru",
      carrier: :smartposti,
      name: "Viru keskuse pakiautomaat",
      address: "Viru väljak 4, Tallinn"
    },
    %{
      id: "smartposti-tartu-kvartal",
      carrier: :smartposti,
      name: "Kvartali pakiautomaat",
      address: "Küüni 7, Tartu"
    }
  ]

  @impl true
  def list(carrier), do: Enum.filter(@points, &(&1.carrier == carrier))

  @impl true
  def get(carrier, id) do
    case Enum.find(@points, &(&1.carrier == carrier and &1.id == id)) do
      nil -> :error
      point -> {:ok, point}
    end
  end
end
