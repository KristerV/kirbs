defmodule Kirbs.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :kirbs

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    seed_categories()
  end

  @doc "Idempotently seeds the own-shop category tree and Yaga category mappings."
  def seed_categories do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          {:ok, :seeded} = Kirbs.Services.Categories.SeedTree.run()
          {:ok, _count} = Kirbs.Services.Search.SeedSynonyms.run()
        end)
    end

    :ok
  end

  @doc """
  Seeds the type-only category tree, re-points items from the old gender-split leaves and
  removes the obsolete categories (idempotent). Prints and returns the summary.
  """
  def migrate_category_tree do
    load_app()

    for repo <- repos() do
      {:ok, summary, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          {:ok, :seeded} = Kirbs.Services.Categories.SeedTree.run()
          {:ok, summary} = Kirbs.Services.Categories.MigrateTree.run()
          IO.inspect(summary, label: "MigrateTree", limit: :infinity)
          summary
        end)

      summary
    end
  end

  @doc "One-off: aligns Item.kirbs_status with Item.status == :sold (idempotent)."
  def repair_kirbs_status do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          {:ok, _counts} = Kirbs.Services.Channels.RepairKirbsStatus.run()
        end)
    end

    :ok
  end

  @doc """
  Enqueues the categorization backfill on a running release, e.g.
  `bin/kirbs eval 'Kirbs.Release.enqueue_categorize_backfill()'`. Dry run unless `apply: true`.
  """
  def enqueue_categorize_backfill(opts \\ []) do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)
    Kirbs.Services.Backfill.EnqueueCategorize.run(opts)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
