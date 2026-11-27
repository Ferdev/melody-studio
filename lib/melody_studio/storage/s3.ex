defmodule MelodyStudio.Storage.S3 do
  @moduledoc """
  Stores files in an S3-compatible bucket. Files are private; the app gives the
  browser a signed link that works for a limited time.

  Set `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`
  and, for storage that is not AWS, `S3_HOST`.
  """
  @behaviour MelodyStudio.Storage

  @url_ttl 6 * 60 * 60

  @impl true
  def put(path, binary, content_type) do
    bucket()
    |> ExAws.S3.put_object(path, binary, content_type: content_type)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @impl true
  def get(path) do
    case bucket() |> ExAws.S3.get_object(path) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      error -> error
    end
  end

  @impl true
  def url(path) do
    {:ok, url} =
      ExAws.Config.new(:s3)
      |> ExAws.S3.presigned_url(:get, bucket(), path, expires_in: @url_ttl)

    url
  end

  @impl true
  def delete(path) do
    case bucket() |> ExAws.S3.delete_object(path) |> ExAws.request() do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp bucket do
    Application.fetch_env!(:melody_studio, __MODULE__) |> Keyword.fetch!(:bucket)
  end
end
