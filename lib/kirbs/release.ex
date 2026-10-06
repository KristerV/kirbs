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
