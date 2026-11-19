defmodule MelodyStudio.Storage.Local do
  @moduledoc """
  Keeps files under `priv/static/uploads`, served by `Plug.Static` at `/uploads`.
  File names have a random part, so other people cannot guess them.
  """
  @behaviour MelodyStudio.Storage

  @impl true
  def put(path, binary, _content_type) do
    full = full_path(path)

    with :ok <- File.mkdir_p(Path.dirname(full)) do
      File.write(full, binary)
    end
  end

  @impl true
  def get(path), do: File.read(full_path(path))

  @impl true
  def url(path), do: "/uploads/" <> path

  @impl true
  def delete(path) do
    case File.rm(full_path(path)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  def root do
    Application.get_env(:melody_studio, __MODULE__, [])
    |> Keyword.get_lazy(:root, fn ->
      Application.app_dir(:melody_studio, "priv/static/uploads")
    end)
  end

  defp full_path(path) do
    if String.contains?(path, ".."), do: raise(ArgumentError, "invalid storage path")
    Path.join(root(), path)
  end
end
