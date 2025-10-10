defmodule Kirbs.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Kirbs.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:kirbs, :token_signing_secret)
  end
end
