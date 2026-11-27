defmodule MelodyStudio.Stems do
  @moduledoc """
  Generates audio stems with a hosted AI music model. The provider is a module
  that implements this behaviour, so it can be swapped:

      config :melody_studio, MelodyStudio.Stems, provider: MelodyStudio.Stems.Replicate
  """

  @type request :: %{
          prompt: String.t(),
          duration: pos_integer(),
          melody_audio: binary() | nil
        }

  @doc "Starts a generation and returns the id of the remote job."
  @callback start(request()) :: {:ok, String.t()} | {:error, term()}

  @doc "Reads the state of a remote job."
  @callback status(String.t()) ::
              :processing | {:succeeded, String.t()} | {:failed, String.t()} | {:error, term()}

  @doc "Downloads the finished audio file."
  @callback download(String.t()) :: {:ok, binary()} | {:error, term()}

  @callback configured?() :: boolean()

  def provider do
    Application.get_env(:melody_studio, __MODULE__, [])
    |> Keyword.get(:provider, MelodyStudio.Stems.Replicate)
  end

  def configured?, do: provider().configured?()
  def start(request), do: provider().start(request)
  def status(id), do: provider().status(id)
  def download(url), do: provider().download(url)

  @doc "The longest stem, in seconds, that the provider makes."
  def max_duration do
    Application.get_env(:melody_studio, __MODULE__, []) |> Keyword.get(:max_duration, 30)
  end
end
