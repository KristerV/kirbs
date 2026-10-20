defmodule KirbsWeb.LegalLive.Privacy do
  @moduledoc "Privaatsuspoliitika (privacy policy), `/privaatsus`."
  use KirbsWeb, :live_view

  import KirbsWeb.LegalComponents

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Privaatsuspoliitika | Kirbs",
       company: KirbsWeb.Company.details()
     )}
  end

  def render(assigns) do
    ~H"""
    <.legal_page id="privacy-page" title="Privaatsuspoliitika" flash={@flash}>
      <%!-- TODO(lawyer): this whole page is a draft and needs GDPR sign-off before launch. --%>
      <h2>Vastutav töötleja</h2>
      <p>
        Isikuandmete vastutav töötleja on {@company.name} (kontaktandmed lehe jaluses). Küsimuste ja
        päringute korral kirjuta aadressil {@company.email}.
      </p>

      <h2>Milliseid andmeid me kogume</h2>
      <ul>
        <li>
          <strong>Tellimus:</strong> nimi, e-posti aadress, telefon, tarneaadress või pakiautomaat,
          tellitud kaubad ja makse olek.
        </li>
        <li>
          <strong>Müüjad (riiete müümine):</strong> nimi, kontaktandmed ja pangakonto number
          väljamaksete tegemiseks.
        </li>
        <li>
          <strong>Veebilehe kasutus:</strong> anonüümne külastaja tunnus, vaadatud lehed ja
          sündmused (nt toote vaatamine, ostukorvi minek), reklaamikampaania parameetrid (UTM).
        </li>
      </ul>

      <h2>Küpsised ja analüütika</h2>
      <%!-- TODO(lawyer): confirm whether a cookie consent banner is required for the analytics cookie
           (ePrivacy / Eesti elektroonilise side seadus) and add one if so. --%>
      <p>
        Kasutame vajalikke küpsiseid (sessioon, ostukorv) ning lisaks analüütika- ja A/B-testimise
        küpsist, mis salvestab juhuslikult genereeritud külastaja tunnuse. Selle abil mõõdame, kuidas
        pood toimib ja milline lehe versioon töötab paremini. Tunnus ei ole seotud sinu nimega, välja
        arvatud juhul, kui esitad tellimuse, mille e-posti aadressiga me külastuse seome.
      </p>
      <%!-- TODO(owner): this section applies only while the Meta pixel is enabled (config :kirbs, :meta_pixel). --%>
      <p>
        Kui reklaamiküpsised on lubatud, laadib leht Meta (Facebook) pikslit, mis edastab Metale
        andmeid lehe külastuse ja ostusündmuste kohta reklaamide tulemuslikkuse mõõtmiseks. Meta
        töötleb neid andmeid oma privaatsuspoliitika alusel.
      </p>

      <h2>Mis eesmärgil ja õiguslikul alusel</h2>
      <ul>
        <li>Tellimuse täitmine ja kliendisuhtlus (lepingu täitmine).</li>
        <li>Raamatupidamiskohustuste täitmine (õiguslik kohustus, säilitame arveid 7 aastat).</li>
        <li>Veebilehe analüüs ja arendamine (õigustatud huvi).</li>
        <li>Reklaamide mõõtmine (nõusolek).</li>
      </ul>

      <h2>Kellele andmeid edastame</h2>
      <%!-- TODO(owner): keep this list in sync with the processors actually used (email provider, hosting). --%>
      <ul>
        <li>
          <strong>Montonio Finance OÜ</strong> - makseteenuse osutaja ja (kui kasutusel)
          tarneteenuse vahendaja; saab makse- ja tarneandmed.
        </li>
        <li>
          Transpordiettevõtted (nt pakiautomaadi operaatorid) - tarneandmed pakkide kohaletoimetamiseks.
        </li>
        <li>Meie IT-teenuste pakkujad (veebimajutus, e-posti saatmine, andmebaas).</li>
        <li>Meta - ainult juhul, kui reklaamipiksel on sisse lülitatud.</li>
      </ul>
      <p>Andmeid ei müüda kolmandatele isikutele.</p>

      <h2>Kui kaua andmeid säilitame</h2>
      <p>
        Tellimuse andmeid säilitame seni, kuni see on vajalik lepingu täitmiseks ja
        raamatupidamisseadusest tulenevate kohustuste täitmiseks (kuni 7 aastat). Analüütika andmeid
        säilitame piiratud aja ja kustutame või anonüümistame need, kui neid pole enam vaja.
      </p>
      <%!-- TODO(owner): confirm actual analytics retention period. --%>

      <h2>Sinu õigused</h2>
      <p>
        Sul on õigus tutvuda oma andmetega, neid parandada, kustutada, töötlemist piirata, esitada
        töötlemisele vastuväide ning taotleda andmete ülekandmist. Nõusoleku võid igal ajal tagasi
        võtta. Päringud saada aadressil {@company.email}. Kui leiad, et sinu õigusi on rikutud, võid
        pöörduda Andmekaitse Inspektsiooni
        (<a href="https://www.aki.ee" rel="noopener" target="_blank">aki.ee</a>) poole.
      </p>
    </.legal_page>
    """
  end
end
