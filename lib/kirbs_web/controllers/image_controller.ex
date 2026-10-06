defmodule KirbsWeb.ImageController do
  @moduledoc """
  Public shop images. Serves JPEG thumbnails of item photos of published items at a
  whitelisted width, generated on first request and cached on disk next to the originals.
  Binary delivery is the one place a controller beats a LiveView.
  """
  use KirbsWeb, :controller

  alias Kirbs.Resources.Image

  @widths [320, 640, 960, 1280]

  def widths, do: @widths

  def show(conn, %{"width" => width, "id" => id}) do
    with {:ok, width} <- parse_width(width),
         {:ok, image} <- Image.get_public(id),
         {:ok, path} <- thumbnail(image, width) do
      conn
      |> put_resp_content_type("image/jpeg")
      |> put_resp_header("cache-control", "public, max-age=604800")
      |> send_file(200, path)
    else
      _ -> conn |> put_status(404) |> text("Not found")
    end
  end

  defp parse_width(width) do
    case Integer.parse(width) do
      {width, ""} when width in @widths -> {:ok, width}
      _ -> :error
    end
  end

  defp thumbnail(image, width) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")
    source = Path.join(upload_dir, image.path)
    thumbs_dir = Path.join(upload_dir, "thumbs")
    target = Path.join(thumbs_dir, "#{image.id}_#{width}.jpg")

    cond do
      File.exists?(target) -> {:ok, target}
      not File.exists?(source) -> :error
      true -> generate(source, thumbs_dir, target, width)
    end
  end

  defp generate(source, thumbs_dir, target, width) do
    File.mkdir_p!(thumbs_dir)
    tmp = target <> ".#{System.unique_integer([:positive])}.tmp.jpg"

    with {:ok, thumb} <- Vix.Vips.Operation.thumbnail(source, width, size: :VIPS_SIZE_DOWN),
         :ok <- Vix.Vips.Image.write_to_file(thumb, tmp, Q: 80, strip: true),
         :ok <- File.rename(tmp, target) do
      {:ok, target}
    else
      _ ->
        File.rm(tmp)
        :error
    end
  end
end
