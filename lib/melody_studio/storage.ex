defmodule MelodyStudio.Storage do
  @moduledoc """
  Stores audio files. Development and tests use the local disk; production can
  use any S3-compatible object storage.

  Configure the adapter with:

      config :melody_studio, MelodyStudio.Storage, adapter: MelodyStudio.Storage.Local
  """

  @callback put(path :: String.t(), binary :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}
  @callback get(path :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback url(path :: String.t()) :: String.t()
  @callback delete(path :: String.t()) :: :ok | {:error, term()}

  def put(path, binary, content_type \\ "audio/wav"),
    do: adapter().put(path, binary, content_type)

  def get(path), do: adapter().get(path)
  def url(nil), do: nil
  def url(path), do: adapter().url(path)
  def delete(nil), do: :ok
  def delete(path), do: adapter().delete(path)

  @doc "Builds a unique storage path for a file of a song."
  def song_path(song_id, name, ext \\ "wav") do
    "songs/#{song_id}/#{name}-#{System.unique_integer([:positive])}-#{random()}.#{ext}"
  end

  defp random, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  defp adapter do
    Application.get_env(:melody_studio, __MODULE__, [])
    |> Keyword.get(:adapter, MelodyStudio.Storage.Local)
  end
end
