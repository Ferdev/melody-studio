defmodule MelodyStudio.Stems.Replicate do
  @moduledoc """
  Generates stems with MusicGen (melody model) on Replicate. The recorded
  melody guides the generated audio.

  Set `REPLICATE_API_TOKEN`. The model version can be changed with
  `REPLICATE_MUSICGEN_VERSION`.
  """
  @behaviour MelodyStudio.Stems

  require Logger

  @base_url "https://api.replicate.com/v1"
  @default_version "671ac645ce5e552cc63a54a2bbff63fcf798043055d2dac5fc9e36a837eedcfb"

  @impl true
  def configured?, do: is_binary(token()) and token() != ""

  @impl true
  def start(%{prompt: prompt, duration: duration} = request) do
    with {:ok, melody_url} <- upload_melody(request[:melody_audio]) do
      input =
        %{
          "model_version" => "stereo-melody-large",
          "prompt" => prompt,
          "duration" => duration,
          "output_format" => "wav",
          "normalization_strategy" => "peak",
          "continuation" => false
        }
        |> maybe_put("input_audio", melody_url)

      case post("/predictions", json: %{"version" => version(), "input" => input}) do
        {:ok, %{status: status, body: %{"id" => id}}} when status in 200..201 -> {:ok, id}
        other -> error(other)
      end
    end
  end

  @impl true
  def status(id) do
    case req() |> Req.get(url: "/predictions/#{id}") do
      {:ok, %{status: 200, body: %{"status" => "succeeded", "output" => output}}} ->
        case output do
          url when is_binary(url) -> {:succeeded, url}
          [url | _] when is_binary(url) -> {:succeeded, url}
          _ -> {:failed, "The music model returned no audio."}
        end

      {:ok, %{status: 200, body: %{"status" => status} = body}}
      when status in ["failed", "canceled"] ->
        {:failed, to_string(body["error"] || "The music model could not make this track.")}

      {:ok, %{status: 200}} ->
        :processing

      other ->
        error(other)
    end
  end

  @impl true
  def download(url) do
    case Req.get(url, Keyword.merge([receive_timeout: 120_000], req_options())) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      other -> error(other)
    end
  end

  defp upload_melody(nil), do: {:ok, nil}

  defp upload_melody(binary) do
    form = [content: {binary, filename: "melody.wav", content_type: "audio/wav"}]

    case post("/files", form_multipart: form) do
      {:ok, %{status: status, body: %{"urls" => %{"get" => url}}}} when status in 200..201 ->
        {:ok, url}

      other ->
        error(other)
    end
  end

  defp post(path, opts), do: req() |> Req.post([url: path] ++ opts)

  defp req do
    Req.new(
      base_url: @base_url,
      auth: {:bearer, token()},
      receive_timeout: 60_000,
      retry: :transient
    )
    |> Req.merge(req_options())
  end

  defp error({:ok, %{status: status, body: body}}) do
    Logger.warning("Replicate returned #{status}: #{inspect(body)}")
    {:error, {:http_error, status}}
  end

  defp error({:error, exception}) do
    Logger.warning("Replicate request failed: #{Exception.message(exception)}")
    {:error, :network}
  end

  defp error(other), do: {:error, other}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp config, do: Application.get_env(:melody_studio, __MODULE__, [])
  defp token, do: config()[:api_token]
  defp version, do: config()[:version] || @default_version
  defp req_options, do: config()[:req_options] || []
end
