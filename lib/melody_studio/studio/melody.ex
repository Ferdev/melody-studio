defmodule MelodyStudio.Studio.Melody do
  use Ecto.Schema
  import Ecto.Changeset

  @max_notes 2000
  @max_beats 64

  schema "melodies" do
    field :notes, {:array, :map}, default: []
    field :audio_path, :string

    belongs_to :song, MelodyStudio.Studio.Song

    timestamps(type: :utc_datetime)
  end

  def max_beats, do: @max_beats

  def changeset(melody, attrs) do
    melody
    |> cast(attrs, [:notes, :audio_path])
    |> update_change(:notes, &normalize_notes/1)
    |> validate_length(:notes, max: @max_notes)
  end

  @doc """
  Cleans a list of notes sent by the browser. Each note has a MIDI `pitch`,
  a `start` and a `duration` in beats, and a `velocity` from 0 to 1.
  Notes that are not valid are dropped.
  """
  def normalize_notes(notes) when is_list(notes) do
    notes
    |> Enum.flat_map(&normalize_note/1)
    |> Enum.sort_by(&{&1["start"], &1["pitch"]})
  end

  def normalize_notes(_), do: []

  defp normalize_note(%{} = note) do
    with pitch when is_integer(pitch) and pitch in 21..108 <- int(note["pitch"]),
         start when is_number(start) and start >= 0 and start < @max_beats <- num(note["start"]),
         duration when is_number(duration) and duration > 0 <- num(note["duration"]) do
      velocity = num(note["velocity"]) || 0.8

      [
        %{
          "pitch" => pitch,
          "start" => Float.round(start * 1.0, 4),
          "duration" => Float.round(min(duration, @max_beats - start) * 1.0, 4),
          "velocity" => Float.round(min(max(velocity * 1.0, 0.05), 1.0), 3)
        }
      ]
    else
      _ -> []
    end
  end

  defp normalize_note(_), do: []

  defp int(value) when is_integer(value), do: value
  defp int(value) when is_float(value), do: round(value)
  defp int(_), do: nil

  defp num(value) when is_number(value), do: value
  defp num(_), do: nil

  @doc "Length of the melody in bars of 4 beats, rounded up to 1, 2, 4, 8 or 16."
  def bars([]), do: 0

  def bars(notes) when is_list(notes) do
    last_beat = notes |> Enum.map(&(&1["start"] + &1["duration"])) |> Enum.max()
    raw = max(1, ceil(last_beat / 4 - 0.001))
    Enum.find([1, 2, 4, 8, 16], 16, &(&1 >= raw))
  end
end
