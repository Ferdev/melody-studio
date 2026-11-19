defmodule MelodyStudio.Studio.Track do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending generating ready sketch failed)

  @mix_defaults %{
    "volume" => 80,
    "pan" => 0,
    "mute" => false,
    "solo" => false,
    "reverb" => 15,
    "delay" => 0,
    "low" => 0,
    "mid" => 0,
    "high" => 0,
    "punch" => 20
  }

  @mix_ranges %{
    "volume" => {0, 100},
    "pan" => {-100, 100},
    "reverb" => {0, 100},
    "delay" => {0, 100},
    "low" => {-12, 12},
    "mid" => {-12, 12},
    "high" => {-12, 12},
    "punch" => {0, 100}
  }

  schema "tracks" do
    field :instrument, :string
    field :role, :string
    field :prompt, :string
    field :status, :string, default: "pending"
    field :error, :string
    field :audio_path, :string
    field :prediction_id, :string
    field :mix, :map, default: @mix_defaults
    field :position, :integer, default: 0

    belongs_to :song, MelodyStudio.Studio.Song

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def mix_defaults, do: @mix_defaults

  def changeset(track, attrs) do
    track
    |> cast(attrs, [
      :instrument,
      :role,
      :prompt,
      :status,
      :error,
      :audio_path,
      :prediction_id,
      :mix,
      :position
    ])
    |> validate_required([:instrument, :role])
    |> validate_inclusion(:status, @statuses)
    |> update_change(:mix, &normalize_mix/1)
  end

  @doc "Merges mix values with the defaults and keeps every number in its range."
  def normalize_mix(mix) when is_map(mix) do
    Map.new(@mix_defaults, fn {key, default} ->
      {key, clean_mix_value(key, Map.get(mix, key, default), default)}
    end)
  end

  def normalize_mix(_), do: @mix_defaults

  defp clean_mix_value(key, value, default) when key in ["mute", "solo"] do
    case value do
      v when is_boolean(v) -> v
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp clean_mix_value(key, value, default) do
    {low, high} = Map.fetch!(@mix_ranges, key)

    number =
      case value do
        v when is_integer(v) -> v
        v when is_float(v) -> round(v)
        v when is_binary(v) -> parse_int(v, default)
        _ -> default
      end

    number |> max(low) |> min(high)
  end

  defp parse_int(value, default) do
    case Integer.parse(String.trim(value)) do
      {int, _} -> int
      :error -> default
    end
  end

  def melody?(%__MODULE__{role: "melody"}), do: true
  def melody?(_), do: false

  def busy?(%__MODULE__{status: status}), do: status in ["pending", "generating"]
end
