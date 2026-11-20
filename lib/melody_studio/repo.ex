defmodule MelodyStudio.Repo do
  use Ecto.Repo,
    otp_app: :melody_studio,
    adapter: Ecto.Adapters.Postgres
end
