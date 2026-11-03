defmodule Kirbs.Services.Ai.ItemInfoExtract do
  @moduledoc """
  Extracts item information from ALL item photos.
  Uses the OpenRouter vision model with web search to identify: brand, size, colors, materials,
  description, quality, suggested_category, price.
  """

  require Logger

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Ai.OpenrouterChat
  alias Kirbs.YagaTaxonomy

  @system_prompt """
  You extract item information from photos of used children's clothing.
  Use web search to find prices of comparable used items on yaga.ee (then vinted.ee)
  before deciding the price.
  """

  def run(item_id) do
    with {:ok, item} <- load_item(item_id),
         {:ok, images} <- get_item_photos(item),
         {:ok, _} <- validate_has_images(images),
         {:ok, extracted} <- extract_with_ai(images),
         {:ok, validated} <- validate_extracted_data(extracted),
         {:ok, updated_item} <- update_item(item, validated) do
      {:ok, updated_item}
    end
  end

  defp load_item(item_id) do
    case Ash.get(Item, item_id, load: [:images]) do
      {:ok, item} -> {:ok, item}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp get_item_photos(%{images: images}) do
    {:ok, images}
  end

  defp validate_has_images([]), do: {:error, "No photos found for item"}
  defp validate_has_images(_), do: {:ok, :valid}

  defp extract_with_ai(images) do
    with {:ok, encoded_images} <- encode_images(images),
         {:ok, result} <- call_llm(encoded_images) do
      parse_response(result)
    end
  end

  defp encode_images(images) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")

    encoded =
      Enum.map(images, fn image ->
        full_path = Path.join(upload_dir, image.path)

        case File.read(full_path) do
          {:ok, image_data} ->
            {:ok, Base.encode64(image_data)}

          {:error, reason} ->
            {:error, "Failed to read image #{image.path}: #{inspect(reason)}"}
        end
      end)

    # Check if any encoding failed
    case Enum.find(encoded, &match?({:error, _}, &1)) do
      {:error, reason} -> {:error, reason}
      nil -> {:ok, Enum.map(encoded, fn {:ok, data} -> data end)}
    end
  end

  defp call_llm(encoded_images) do
    # Get valid options from taxonomy
    kids_categories = YagaTaxonomy.kids_categories() |> Enum.map(& &1.name) |> Enum.uniq()
    colors = YagaTaxonomy.all_colors() |> Enum.map(& &1.name)
    materials = YagaTaxonomy.all_materials() |> Enum.map(& &1.name)
    sizes = YagaTaxonomy.all_sizes() |> Enum.map(& &1.name)
    brands = YagaTaxonomy.all_brands() |> Enum.map(& &1.name) |> Enum.sort()

    prompt = """
    KONTEKST: Sa hindad KASUTATUD laste rõivaid Eesti second-hand turule (yaga.ee).

    TÄHTIS: Pildil võib olla MITU asja korraga - see on komplekt! Kui näed mitut eset (nt body + püksid, või 2-3 bodyt koos), siis käsitle neid koos ühe komplektina.

    HINNAKUJUNDUS:
    - Need on KASUTATUD riided, mitte uued!
    - Uued laste rõivad maksavad €3-10, kasutatud peaksid olema 20-40% uuest hinnast
    - Tüüpilised yaga.ee hinnad: bodyd €1-2, pluusid €2-3, püksid €3-4, joped €5-8
    - Komplekti puhul: liida üksikute asjade hinnad kokku (nt 2 bodyt = €3-4)
    - Otsi ESMALT yaga.ee (site:yaga.ee), seejärel vinted.ee
    - Väldi eBay'i ja USA hindu täielikult

    Analüüsi neid laste rõivaste fotosid ja eralda järgmine informatsioon:

    - brand: AINULT trükitud brändisildilt. Vaata kas on TÄPSELT loendis: #{Enum.join(brands, ", ")}. Kui ei ole loendis VÕI on käsitsi kirjutatud VÕI puudub, kasuta "Muu".
    - size: Suurus. Vaata sildilt ja vali kõige lähedasem neist: #{Enum.join(sizes, ", ")}. TÄHTIS: Kui suurus on piiri peal (nt 128), vali ALATI vahemik kus see number on ALUMINE piir (nt 128/134, MITTE 122/128), et laps kasvades ikka ära mahub.
    - colors: Värvide loend EESTI KEELES. Vali ainult nendest: #{Enum.join(colors, ", ")}. MAKSIMAALSELT 2 värvi! Vali 1-2 kõige domineerivat värvi.
    - materials: Materjalide loend EESTI KEELES. Vali ainult nendest: #{Enum.join(materials, ", ")}
    - description: EESTI KEELES lühike kirjeldus (1-2 lauset) sõbralikus, jutustavas stiilis. Kirjuta nagu räägiks inimene teisele - kasuta igapäevaseid sõnu ja loomuliku vestlustoon. KUI ON MITU ASJA, alusta "Komplekt:" ja nimeta asjad. Näited üksikute asjade kohta: "Armas body, kergelt kantud, aga väga heas seisukorras", "Mõnus pehme dressipluus, kergete kasutusjälgedega". Näited komplekti kohta: "Komplekt: 2 armsat bodyt, mõlemad väga heas seisukorras", "Komplekt: body ja püksid, natuke kantud aga kenasti hoitud", "Komplekt: 3 bodyt erinevatest brändidest, kergete kasutusjälgedega". Maini defekte loomulikult, aga ära kõla nagu robot!
    - quality: Seisukord. Vali TÄPSELT üks nendest valikutest:
      * "Uus" - Täielikult originaalseisukorras või pakendis/siltidega. TÄHTIS: Kui fotodel on näha poesilt (label/tag) kinnitatud riidele, see tähendab et ese on UUS ja müümata - vali alati "Uus"!
      * "Uueväärne" - Minimaalselt või üldse mitte kasutatud, defektide ja kasutusjälgedeta
      * "Hea" - Võivad esineda vähesed kasutusjäljed, mis on välja toodud kirjelduses
      * "Keskmine" - Märgatavate kasutusjälgedega, mis on välja toodud kirjelduses
      OLE RANGE - enamik kasutatud riideid on "Uueväärne" või "Hea", mitte "Keskmine"! Aga kui on sildid/label'id küljes → "Uus"!
    - suggested_category: Kategooria EESTI KEELES. Vali TÄPSELT üks nendest: #{Enum.join(kids_categories, ", ")}
    - price: KASUTATUD eseme müügihind eurodes yaga.ee turul. Search "site:yaga.ee [brand] [category] laste" to find actual yaga.ee listings. Kasutatud riided on 20-40% uue hinnast. Bodyd tavaliselt €1-2, pluusid €2-3. Kui ei leia yaga.ee hindu, kasuta vinted.ee või üldist Eesti second-hand hinnataset. Kui ei suuda hinnata, tagasta null.
    - price_explanation: English explanation (1-2 sentences) for the price. Mention if you found similar listings on yaga.ee or vinted.ee with prices, or if you estimated based on typical Estonian second-hand prices. Example: "Found similar bodysuits on yaga.ee for €1-2." or "No exact matches, estimated €1.50 based on typical used bodysuit prices on yaga.ee."

    Näited:
    Üks asi: {"brand": "H&M", "size": "74/80", "colors": ["Sinine"], "materials": ["Puuvill"], "description": "Armas sinine body, kergelt kantud aga väga heas seisukorras", "quality": "Hea", "suggested_category": "Bodyd", "price": 1.50, "price_explanation": "Found similar H&M bodysuits on yaga.ee for €1-2."}
    Komplekt: {"brand": "Muu", "size": "74/80", "colors": ["Sinine", "Valge"], "materials": ["Puuvill"], "description": "Komplekt: 2 armsat bodyt, üks sinine ja üks valge, mõlemad hästi hoitud", "quality": "Hea", "suggested_category": "Bodyd", "price": 3.00, "price_explanation": "Set of 2 bodysuits, priced at €1.50 each based on typical yaga.ee prices."}

    Kui mingit välja ei saa piltidelt määrata, kasuta null.
    Massiivide puhul (colors, materials) tagasta tühi massiiv [] kui ei saa määrata.
    Hinna puhul tagasta number (nt 5.50) või null.
    Hinna selgitus peab alati olema, kui hind on määratud.

    OLULINE:
    - KOMPLEKT: Kui pildil on mitu asja, käsitle neid ühe komplektina! Kirjelduses alusta "Komplekt:" ja nimeta asjad. Hind = üksikute asjade hinnad kokku.
    - Bränd: IGNOREERI käsitsi kirjutatud teksti! Kasuta AINULT trükitud brändisildilt. Kui käsitsi kirjutatud VÕI ei ole loendis → "Muu". Komplekti puhul kui erinevad brändid → "Muu"
    - Suurus: vali kõige lähedasem loendist (nt kui sildil on "80cm", vali "74/80"). TÄHTIS: Kui suurus on piiri peal (nt 128), vali ALATI vahemik kus see number on ALUMINE piir (nt 128/134, MITTE 122/128), et laps kasvades ikka ära mahub. Komplekti puhul kui sama suurus → see suurus, kui erinevad → vanim/väiksem suurus
    - Värvid: AINULT eestikeelsed valikud ülaltoodud loendist. MAKSIMAALSELT 2 värvi! Vali domineerivad värvid.
    - Materjalid: AINULT eestikeelsed valikud ülaltoodud loendist
    - Kirjeldus: SÕBRALIK, LOOMULIK, JUTUSTAV stiil. Kirjuta nagu inimene inimesele, mitte nagu robot! Komplekt → alusta "Komplekt:" ja kirjelda mida kuulub
    - Kvaliteet: OLE RANGE! Kui fotodel on näha poesilt/label kinnitatud riidele → alati "Uus"! Kui riie on praktiliselt uus või väga vähe kantud → "Uueväärne". Ainult väheste kasutusjälgedega → "Hea". Ainult päris kulunud/kahjustatud → "Keskmine"
    - Kvaliteet ja kategooria TÄPSELT loendist, mitte sinu enda sõnadega
    - Hind: KRIITILINE! KASUTATUD riie hind! Search "site:yaga.ee" first! Used baby clothes are CHEAP: bodysuits €1-2, NOT €4-5! These are 20-40% of new price. KOMPLEKTI puhul liida üksikute asjade hinnad kokku! Don't use eBay or foreign prices!
    """

    OpenrouterChat.run(prompt,
      images: encoded_images,
      system: @system_prompt,
      json_schema: schema(kids_categories, colors, materials, sizes),
      web_search: true
    )
  end

  @doc false
  def schema(categories, colors, materials, sizes) do
    nullable_enum = fn values ->
      %{"type" => ["string", "null"], "enum" => Enum.uniq(values) ++ [nil]}
    end

    conditions = Enum.map(YagaTaxonomy.all_conditions(), & &1.name)

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" =>
        ~w(brand size colors materials description quality suggested_category price price_explanation),
      "properties" => %{
        "brand" => %{"type" => ["string", "null"]},
        "size" => nullable_enum.(sizes),
        "colors" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => Enum.uniq(colors)}
        },
        "materials" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => Enum.uniq(materials)}
        },
        "description" => %{"type" => ["string", "null"]},
        "quality" => nullable_enum.(conditions),
        "suggested_category" => nullable_enum.(categories),
        "price" => %{"type" => ["number", "null"]},
        "price_explanation" => %{"type" => ["string", "null"]}
      }
    }
  end

  defp parse_response(response_text) do
    case Jason.decode(response_text) do
      {:ok, data} ->
        parse_extracted_data(data)

      {:error, error} ->
        {:cancel,
         "Could not parse AI response JSON: #{inspect(error)}. Response: #{String.slice(response_text, 0..500)}"}
    end
  end

  defp parse_extracted_data(data) when is_map(data) do
    {:ok,
     %{
       brand: data["brand"],
       size: data["size"],
       colors: data["colors"] || [],
       materials: data["materials"] || [],
       description: data["description"],
       quality: data["quality"],
       suggested_category: data["suggested_category"],
       price: data["price"],
       price_explanation: data["price_explanation"]
     }}
  end

  defp parse_extracted_data(data) do
    Logger.error(
      "Expected map but got invalid data structure from AI: #{inspect(data, pretty: true, limit: :infinity)}"
    )

    {:error, "Invalid data structure received from AI"}
  end

  defp validate_extracted_data(extracted) do
    valid_sizes = YagaTaxonomy.all_sizes() |> Enum.map(& &1.name)

    price = validate_price(extracted.price)

    validated = %{
      brand: validate_brand(extracted.brand),
      size: validate_size(extracted.size, valid_sizes),
      colors: validate_colors(extracted.colors),
      materials: validate_materials(extracted.materials),
      description: extracted.description,
      quality: validate_quality(extracted.quality),
      suggested_category: validate_category(extracted.suggested_category),
      ai_suggested_price: price,
      ai_price_explanation: extracted.price_explanation,
      listed_price: price
    }

    {:ok, validated}
  end

  defp validate_brand(nil), do: nil

  defp validate_brand(brand) do
    if YagaTaxonomy.brand_to_id(brand), do: brand, else: nil
  end

  defp validate_size(nil, _), do: nil

  defp validate_size(size, valid_sizes) do
    if size in valid_sizes, do: size, else: nil
  end

  defp validate_colors(nil), do: []

  defp validate_colors(colors) when is_list(colors) do
    colors
    |> Enum.filter(fn color -> YagaTaxonomy.color_to_id(color) != nil end)
  end

  defp validate_materials(nil), do: []

  defp validate_materials(materials) when is_list(materials) do
    materials
    |> Enum.filter(fn material -> YagaTaxonomy.material_to_id(material) != nil end)
  end

  defp validate_quality(nil), do: nil

  defp validate_quality(quality) do
    if YagaTaxonomy.condition_to_id(quality), do: quality, else: nil
  end

  defp validate_category(nil), do: nil

  defp validate_category(category) do
    if YagaTaxonomy.category_to_id(category), do: category, else: nil
  end

  defp validate_price(nil), do: nil

  defp validate_price(price) when is_number(price) and price > 0 do
    Decimal.new(to_string(price))
  end

  defp validate_price(_), do: nil

  defp update_item(item, extracted) do
    Ash.update(item, extracted)
  end
end
