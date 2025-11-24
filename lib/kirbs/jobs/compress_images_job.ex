defmodule Kirbs.Jobs.CompressImagesJob do
  @moduledoc """
  Background job to compress images for items uploaded to Yaga.
  Runs daily at 3 AM via Oban cron.
  Processes 50 images per run, reschedules itself if more remain.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger

  alias Kirbs.Resources.Image
  alias Kirbs.Services.ImageCompress

  @batch_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("CompressImagesJob: Starting image compression")

    images = Image.get_uncompressed!(@batch_size)

    if images == [] do
      Logger.info("CompressImagesJob: No images to compress")
      :ok
    else
      {processed, errors} = process_images(images)

      Logger.info("CompressImagesJob: Compressed #{processed} images, #{length(errors)} errors")

      if length(errors) > 0 do
        Logger.warning("CompressImagesJob: Errors: #{inspect(errors)}")
      end

      maybe_reschedule()

      :ok
    end
  end

  defp process_images(images) do
    results =
      Enum.map(images, fn image ->
        case ImageCompress.run(image) do
          {:ok, _} -> {:ok, image.id}
          {:error, reason} -> {:error, {image.id, reason}}
        end
      end)

    processed = Enum.count(results, &match?({:ok, _}, &1))
    errors = Enum.filter(results, &match?({:error, _}, &1)) |> Enum.map(&elem(&1, 1))

    {processed, errors}
  end

  defp maybe_reschedule do
    if Image.get_uncompressed!(1) != [] do
      Logger.info("CompressImagesJob: More images to compress, rescheduling")

      %{}
      |> __MODULE__.new()
      |> Oban.insert!()
    end
  end
end
