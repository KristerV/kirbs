defmodule Kirbs.Repo do
  use Ecto.Repo,
    otp_app: :kirbs,
    adapter: Ecto.Adapters.Postgres
end
