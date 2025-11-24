defmodule Kirbs.Services.ImageCompress do
  @moduledoc """
  Service for compressing a single image.
  Resizes to max 1920px on longest side and saves at 85% JPEG quality.
  """

  alias Vix.Vips.{Image, Operation}

  @max_dimension 1920
  @jpeg_quality 85

  def run(image) do
    with {:ok, file_path} <- get_file_path(image),
         {:ok, vips_image} <- Image.new_from_file(file_path),
         {:ok, resized} <- resize_if_needed(vips_image),
         :ok <- save_image(resized, file_path),
         {:ok, image} <- mark_compressed(image) do
      {:ok, image}
    end
  end

  defp get_file_path(image) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir)
    file_path = Path.join(upload_dir, image.path)

    if File.exists?(file_path) do
      {:ok, file_path}
    else
      {:error, "File not found: #{file_path}"}
    end
  end

  defp resize_if_needed(vips_image) do
    width = Image.width(vips_image)
    height = Image.height(vips_image)
    longest_side = max(width, height)

    if longest_side > @max_dimension do
      Operation.thumbnail_image(vips_image, @max_dimension, size: :VIPS_SIZE_DOWN)
    else
      {:ok, vips_image}
    end
  end

  defp save_image(vips_image, file_path) do
    case Image.write_to_file(vips_image, file_path, Q: @jpeg_quality, strip: true) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to save image: #{inspect(reason)}"}
    end
  end

  defp mark_compressed(image) do
    Kirbs.Resources.Image.update(image, %{compressed: true})
  end
end
