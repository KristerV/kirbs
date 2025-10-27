defmodule Kirbs.Repo.Migrations.DropYagaMetadataTable do
  use Ecto.Migration

  def up do
    drop table(:yaga_metadata)
  end

  def down do
    create table(:yaga_metadata, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :metadata_type, :string, null: false
      add :yaga_id, :bigint, null: false
      add :name, :string, null: false
      add :name_en, :string
      add :parent_id, :bigint
      add :metadata_json, :map
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:yaga_metadata, [:metadata_type, :yaga_id])
  end
end
