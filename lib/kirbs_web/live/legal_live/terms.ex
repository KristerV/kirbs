defmodule KirbsWeb.LegalLive.Terms do
  @moduledoc "Müügitingimused (terms of sale), `/tingimused`."
  use KirbsWeb, :live_view

  import KirbsWeb.LegalComponents

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, page_title: "Müügitingimused | Kirbs", company: KirbsWeb.Company.details())}
  end

  def render(assigns) do
    ~H"""
    <.legal_page id="terms-page" title="Müügitingimused" flash={@flash}>
      <%!-- TODO(lawyer): this whole page is a draft and needs legal sign-off before launch. --%>
      <h2>1. Müüja</h2>
      <p>
        Veebipoodi kirbs.ee haldab ja kaupa müüb {@company.name} (edaspidi müüja). Müüja andmed on
        toodud lehe jaluses. Kirbs müüb kasutatud lasteriideid ja -tarvikuid.
      </p>

      <h2>2. Kaubad ja hinnad</h2>
      <%!-- TODO(owner): confirm VAT status; wording below assumes prices are final for consumers. --%>
      <p>
        Kõik kaubad on kasutatud, kui pole märgitud teisiti. Iga kauba seisukord on toote lehel
        kirjeldatud ja pildistatud; igast tootest on müügil üks eksemplar. Hinnad on eurodes ja
        sisaldavad kehtivaid makse. Tarneviis ja tarne hind lisatakse tellimuse vormistamisel enne
        makset.
      </p>

      <h2>3. Tellimine ja leping</h2>
      <p>
        Leping tekib, kui tellimus on vormistatud ja makse laekunud. Kuna iga kaup on ühekordne,
        reserveerime kauba ostukorvi vormistamise ajaks piiratud ajaks. Kui makset selle aja jooksul
        ei tehta, reservatsioon tühistatakse ja kaup läheb uuesti müüki. Kui kaup osutub vahepeal
        siiski müüdud olevaks, teavitame sind viivitamatult ja tagastame makstud summa.
      </p>

      <h2>4. Makse</h2>
      <%!-- TODO(owner): list the payment methods that are actually enabled at launch. --%>
      <p>
        Makseid vahendab Montonio Finance OÜ (pangalingid ja kaardimaksed). Kirbs ei salvesta sinu
        pangakaardi andmeid. Võimalik on ka ülekanne müüja arvelduskontole vastavalt tellimuse
        kinnituses toodud juhistele.
      </p>

      <h2>5. Tarne</h2>
      <%!-- TODO(owner): confirm carriers, delivery times and prices. --%>
      <p>
        Kaup saadetakse pakiautomaati või kulleriga tellimuse vormistamisel valitud viisil. Tavaliselt
        antakse kaup transpordiettevõttele üle paari tööpäeva jooksul pärast makse laekumist. Kauba
        riski kannab müüja kuni kauba üleandmiseni sinule.
      </p>

      <h2>6. Taganemisõigus ja kaebused</h2>
      <p>
        Tarbijana on sul õigus lepingust taganeda 14 päeva jooksul. Täpsemad tingimused leiad lehelt <.link navigate={
          ~p"/tagastus"
        }>Tagastus ja taganemisõigus</.link>.
      </p>
      <%!-- TODO(lawyer): the statutory conformity (non-conformity) liability period for used goods
           and whether it may be shortened to 1 year in B2C (VÕS § 218) must be confirmed. --%>
      <p>
        Müüja vastutab kauba lepingutingimustele mittevastavuse eest seaduses sätestatud korras.
        Kuna kaup on kasutatud, on tavapärane kulumine kirjeldatud seisukorra osa ega ole puudus.
        Kaebuse korral kirjuta aadressil {@company.email}.
      </p>

      <h2>7. Vaidluste lahendamine</h2>
      <p>
        Kui me ei jõua kaebuse osas kokkuleppele, võid pöörduda Tarbijavaidluste komisjoni
        (<a href="https://komisjon.ee" rel="noopener" target="_blank">komisjon.ee</a>) poole.
      </p>

      <h2>8. Isikuandmed</h2>
      <p>
        Isikuandmete töötlemist kirjeldab <.link navigate={~p"/privaatsus"}>privaatsuspoliitika</.link>.
      </p>

      <h2>9. Kohaldatav õigus</h2>
      <p>Lepingule kohaldatakse Eesti Vabariigi õigust.</p>
    </.legal_page>
    """
  end
end
