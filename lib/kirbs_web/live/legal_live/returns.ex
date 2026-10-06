defmodule KirbsWeb.LegalLive.Returns do
  @moduledoc "Tagastus ja taganemisõigus (returns and 14-day withdrawal), `/tagastus`."
  use KirbsWeb, :live_view

  import KirbsWeb.LegalComponents

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Tagastus ja taganemisõigus | Kirbs",
       company: KirbsWeb.Company.details()
     )}
  end

  def render(assigns) do
    ~H"""
    <.legal_page id="returns-page" title="Tagastus ja taganemisõigus" flash={@flash}>
      <%!-- TODO(lawyer): this whole page is a draft and needs legal sign-off before launch.
           Basis: Võlaõigusseadus § 56 (distance contracts, 14-day withdrawal). --%>
      <h2>14-päevane taganemisõigus</h2>
      <p>
        Tarbijana on sul õigus veebipoest tehtud ostust põhjust esitamata taganeda 14 päeva jooksul
        arvates päevast, mil kaup sinu kätte jõudis (või kolmanda isiku, kes pole vedaja, kätte, kelle
        sa kauba vastuvõtjaks määrasid).
      </p>

      <h2>Kuidas taganeda</h2>
      <p>
        Teata taganemisest enne tähtaja lõppu e-kirjaga aadressil <strong>{@company.email}</strong>. Kirjas märgi oma nimi, tellimuse number ja tagastatav kaup.
        Võid kasutada ka vaba vormiga avaldust.
      </p>
      <%!-- TODO(lawyer): consider attaching the standard EU withdrawal form (VÕS Annex) as a downloadable template. --%>

      <h2>Kauba tagastamine</h2>
      <%!-- TODO(owner/lawyer): decide who bears the return shipping cost. The text below assumes the
           buyer pays (permitted only if stated clearly before the purchase). --%>
      <p>
        Saada kaup meile tagasi hiljemalt 14 päeva jooksul pärast taganemisest teatamist. Kauba
        tagastamise otsesed kulud kannab ostja. Kauba tagastamise aadressi anname taganemisest
        teatamisel.
      </p>

      <h2>Raha tagastamine</h2>
      <p>
        Tagastame sulle kogu tasutud summa (sh tavapärase tarne hinna) 14 päeva jooksul pärast
        taganemisavalduse saamist. Raha tagastatakse samal viisil, mida kasutasid maksmisel. Meil on
        õigus raha tagastamisega oodata, kuni kaup on meile tagasi jõudnud või oled tõendanud kauba
        tagasisaatmist.
      </p>

      <h2>Kasutatud kaup</h2>
      <%!-- TODO(lawyer): confirm wording on diminished value (VÕS § 56 lg 8-9). --%>
      <p>
        Kõik meie kaubad on kasutatud ja on kirjeldatud seisukorras. Kauba tohib kontrollimiseks
        proovida ja katsetada nii, nagu poes seda teha saaks. Kui kaup on kasutatud rohkem kui oli
        vajalik selle omaduste ja toimimise kontrollimiseks (nt pestud, parandatud, kahjustatud või
        määrdunud), vastutad kauba väärtuse vähenemise eest. Tagasta kaup võimalikult samas seisukorras
        nagu see sulle saadeti.
      </p>

      <h2>Puudusega kaup</h2>
      <p>
        Kui kaup ei vasta kirjeldusele, anna sellest teada aadressil {@company.email}. Sellisel juhul
        kanname tagastamise kulud ise. Põhjendamatu kulumine või tootepildil nähtav seisukord ei ole
        puudus.
      </p>

      <p>
        Vaata ka <.link navigate={~p"/tingimused"}>müügitingimusi</.link>.
      </p>
    </.legal_page>
    """
  end
end
