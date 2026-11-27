# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# `mix ecto.setup` and `mix ecto.reset` also run it. Running it again is safe.

alias MelodyStudio.Accounts

if Mix.env() == :dev do
  # A test account for development. Log in at /users/log-in with these details.
  email = "test@example.com"
  password = "melodystudio123"

  case Accounts.get_user_by_email(email) do
    nil ->
      {:ok, _user} = Accounts.register_user(%{email: email, password: password})
      IO.puts("Created the test user #{email} with the password #{password}")

    _user ->
      IO.puts("The test user #{email} already exists")
  end
end
