defmodule KirbsWeb.AboutLive.Index do
  @moduledoc "Introduces the Kirbs concept (second-hand kids' clothes, sold for you), `/meist`."
  use KirbsWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Kuidas Kirbs töötab | Kirbs")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <article id="about-page" class="mx-auto max-w-3xl">
        <h1 class="text-4xl font-black tracking-tight text-stone-900">
          Kvaliteetsed lasteriided uue elu ootel
        </h1>
        <p class="mt-4 text-lg leading-relaxed text-stone-700">
          Lapsed kasvavad riietest välja kiiremini, kui need katki lähevad. Kirbs annab heale
          riidele teise ringi: me võtame vastu kasutatud lasteriided, valime välja head, pildistame
          need ja müüme edasi.
        </p>

        <div class="mt-10 grid gap-6 sm:grid-cols-2">
          <section id="about-buyers" class="rounded-2xl border border-orange-100 bg-white p-6">
            <h2 class="text-xl font-bold text-stone-900">Ostjale</h2>
            <p class="mt-2 leading-relaxed text-stone-700">
              Iga ese on päris ja ainulaadne: pildid on tehtud just sellest riidest ning seisukord
              on kirjas. Vali, maksa pangalingiga ja saad paki pakiautomaati.
            </p>
            <.link
              navigate={~p"/"}
              id="about-shop-link"
              class="mt-4 inline-block rounded-full bg-orange-500 px-4 py-1.5 text-sm font-semibold text-white transition hover:bg-orange-600"
            >
              Vaata poodi
            </.link>
          </section>

          <section id="about-sellers" class="rounded-2xl border border-orange-100 bg-white p-6">
            <h2 class="text-xl font-bold text-stone-900">Müüjale</h2>
            <p class="mt-2 leading-relaxed text-stone-700">
              Sa ei pea ise pildistama, hindama ega pakkima. Anna riided meile, meie tegeleme müügiga
              ja sa saad oma osa, kui ese on müüdud.
            </p>
            <.link
              navigate={~p"/muuda"}
              id="about-sell-link"
              class="mt-4 inline-block rounded-full border border-orange-300 px-4 py-1.5 text-sm font-semibold text-orange-600 transition hover:bg-orange-50"
            >
              Müü meiega
            </.link>
          </section>
        </div>

        <h2 class="mt-12 text-2xl font-bold text-stone-900">Kuidas see käib</h2>
        <ol id="about-steps" class="mt-4 space-y-4 text-stone-700">
          <li :for={
            {title, text} <- [
              {"Riided jõuavad meieni", "Müüja annab kasutatud lasteriided meile."},
              {"Valime ja pildistame", "Head esemed saavad pildid, kirjelduse ja hinna."},
              {"Sa ostad", "Maksad Montonio kaudu, kaup on sinu jaoks reserveeritud."},
              {"Pakk teele", "Saadame paki sinu valitud pakiautomaati."}
            ]
          }>
            <span class="font-bold text-stone-900">{title}.</span> {text}
          </li>
        </ol>
      </article>
    </Layouts.app>
    """
  end
end
