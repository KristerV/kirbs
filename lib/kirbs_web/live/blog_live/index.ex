defmodule KirbsWeb.BlogLive.Index do
  use KirbsWeb, :live_view

  on_mount {KirbsWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    articles = load_articles()

    {:ok,
     socket
     |> assign(:page_title, "Uudised - Kirbs")
     |> assign(:articles, articles)}
  end

  defp load_articles do
    blog_dir = Application.app_dir(:kirbs, "priv/blog")

    blog_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(fn filename ->
      path = Path.join(blog_dir, filename)
      content = File.read!(path)
      Jason.decode!(content)
    end)
    |> Enum.sort_by(& &1["date"], :desc)
  end
end
