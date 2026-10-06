defmodule KirbsWeb.SeoComponents do
  @moduledoc """
  Per-page SEO tags. LiveViews assign `:meta` (a map) and the root layout renders it:

      assign(socket, :meta, %{description: "...", path: "/p/slug", image: "/img/640/ID", type: "product"})

  The page title comes from the usual `:page_title` assign.
  """
  use Phoenix.Component

  attr :meta, :map, required: true
  attr :title, :string, default: nil

  def meta_tags(assigns) do
    meta = assigns.meta

    assigns =
      assigns
      |> assign(:description, meta[:description])
      |> assign(:url, absolute(meta[:path]))
      |> assign(:image, absolute(meta[:image]))
      |> assign(:type, meta[:type] || "website")
      |> assign(:robots, meta[:robots])
      |> assign(:jsonld, encode_jsonld(meta[:jsonld]))

    ~H"""
    <meta :if={@description} name="description" content={@description} />
    <meta :if={@robots} name="robots" content={@robots} />
    <link :if={@url} rel="canonical" href={@url} />
    <meta property="og:site_name" content="Kirbs" />
    <meta property="og:locale" content="et_EE" />
    <meta property="og:type" content={@type} />
    <meta :if={@title} property="og:title" content={@title} />
    <meta :if={@description} property="og:description" content={@description} />
    <meta :if={@url} property="og:url" content={@url} />
    <meta :if={@image} property="og:image" content={@image} />
    <meta name="twitter:card" content={if(@image, do: "summary_large_image", else: "summary")} />
    <meta :if={@title} name="twitter:title" content={@title} />
    <meta :if={@description} name="twitter:description" content={@description} />
    <meta :if={@image} name="twitter:image" content={@image} />
    <script :if={@jsonld} type="application/ld+json">
      <%= Phoenix.HTML.raw(@jsonld) %>
    </script>
    """
  end

  defp encode_jsonld(nil), do: nil

  defp encode_jsonld(data) do
    data |> Phoenix.json_library().encode!() |> String.replace("</", "<\\/")
  end

  @doc "Absolute URL for a site path (nil-safe, leaves absolute URLs alone)."
  def absolute(nil), do: nil
  def absolute("http" <> _ = url), do: url
  def absolute(path), do: KirbsWeb.Endpoint.url() <> path
end
