defmodule MelodyStudio.AI.Claude do
  @moduledoc """
  A small client for the Anthropic Messages API. Elixir has no official
  Anthropic SDK, so this module calls the HTTP API with Req.

  Every call asks for structured output: Claude must answer with JSON that
  matches the given JSON schema.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2026-10-21"
  @fallback_beta "server-side-fallback-2026-07-01"

  @doc "True when an API key is set."
  def configured?, do: is_binary(api_key()) and api_key() != ""

  @doc """
  Sends one request and returns the decoded JSON object.

  Options: `:effort` (`"low"`, `"medium"` or `"high"`), `:max_tokens`.
  """
  def structured(system, prompt, schema, opts \\ []) do
    if configured?() do
      body = %{
        model: model(),
        max_tokens: Keyword.get(opts, :max_tokens, 16_000),
        system: system,
        messages: [%{role: "user", content: prompt}],
        output_config: %{
          effort: Keyword.get(opts, :effort, "medium"),
          format: %{type: "json_schema", schema: schema}
        },
        # Retry on another model when a safety classifier declines the request.
        fallbacks: "default"
      }

      request(body)
    else
      {:error, :not_configured}
    end
  end

  defp request(body) do
    [
      url: @api_url,
      json: body,
      headers: [
        {"x-api-key", api_key()},
        {"anthropic-version", @api_version},
        {"anthropic-beta", @fallback_beta}
      ],
      receive_timeout: 300_000,
      retry: :transient,
      max_retries: 2
    ]
    |> Keyword.merge(req_options())
    |> Req.post()
    |> handle_response()
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: %{"stop_reason" => "refusal"}}}) do
    {:error, :refused}
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: %{"stop_reason" => "max_tokens"}}}) do
    {:error, :too_long}
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: %{"content" => content}}}) do
    text =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("", & &1["text"])

    case Jason.decode(text) do
      {:ok, %{} = json} -> {:ok, json}
      _ -> {:error, :invalid_json}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    Logger.warning("Anthropic API returned #{status}: #{inspect(body)}")
    {:error, {:http_error, status}}
  end

  defp handle_response({:error, exception}) do
    Logger.warning("Anthropic API request failed: #{Exception.message(exception)}")
    {:error, :network}
  end

  defp config, do: Application.get_env(:melody_studio, __MODULE__, [])
  defp api_key, do: config()[:api_key]
  defp model, do: config()[:model] || "claude-sonnet-5-5"
  defp req_options, do: config()[:req_options] || []
end
