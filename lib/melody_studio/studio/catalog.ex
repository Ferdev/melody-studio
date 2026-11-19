defmodule MelodyStudio.Studio.Catalog do
  @moduledoc """
  The fixed choices that people can make in the studio: genres, instruments,
  keys, and the built-in rhythm ideas that are used when the AI is not set up.
  """

  @genres [
    %{id: "pop", name: "Pop", emoji: "🎤", blurb: "Catchy, bright and easy to sing along to."},
    %{id: "rock", name: "Rock", emoji: "🎸", blurb: "Loud guitars and big drums."},
    %{id: "lofi", name: "Lo-fi", emoji: "📼", blurb: "Warm, dusty and relaxed beats."},
    %{id: "electronic", name: "Electronic", emoji: "🎛️", blurb: "Synths and a steady dance beat."},
    %{id: "jazz", name: "Jazz", emoji: "🎷", blurb: "Rich chords and a swinging feel."},
    %{id: "acoustic", name: "Acoustic", emoji: "🪕", blurb: "Gentle, natural instruments."}
  ]

  @instruments [
    %{id: "drums", name: "Drums", emoji: "🥁", role: "rhythm"},
    %{id: "bass", name: "Bass", emoji: "🎻", role: "bass"},
    %{id: "keys", name: "Keys", emoji: "🎹", role: "chords"},
    %{id: "guitar", name: "Guitar", emoji: "🎸", role: "chords"},
    %{id: "strings", name: "Strings", emoji: "🎼", role: "texture"},
    %{id: "pads", name: "Pads", emoji: "☁️", role: "texture"}
  ]

  @notes ~w(C C# D Eb E F F# G Ab A Bb B)

  def genres, do: @genres
  def genre_ids, do: Enum.map(@genres, & &1.id)
  def genre(id), do: Enum.find(@genres, &(&1.id == id))
  def genre_name(id), do: (genre(id) || %{name: "No style yet"}).name

  def instruments, do: @instruments
  def instrument_ids, do: Enum.map(@instruments, & &1.id)
  def instrument(id), do: Enum.find(@instruments, &(&1.id == id))

  def instrument_name("melody"), do: "Your melody"
  def instrument_name(id), do: (instrument(id) || %{name: String.capitalize(id)}).name

  def instrument_emoji("melody"), do: "🎵"
  def instrument_emoji(id), do: (instrument(id) || %{emoji: "🎵"}).emoji

  def default_role(id), do: (instrument(id) || %{role: "texture"}).role

  def keys do
    for scale <- ["major", "minor"], note <- @notes, do: "#{note} #{scale}"
  end

  def key_options do
    Enum.map(keys(), fn key -> {key, key} end)
  end

  @doc """
  Built-in rhythm ideas for each genre. Each step list has 16 steps (one bar
  of sixteenth notes): 1 means hit, 0 means rest.
  """
  def preset_rhythms(genre) do
    Map.get(presets(), genre, presets()["pop"])
  end

  defp presets do
    %{
      "pop" => [
        rhythm("Four on the floor", "A steady kick on every beat with claps on 2 and 4.",
          kick: "1000100010001000",
          snare: "0000100000001000",
          hihat: "1010101010101010"
        ),
        rhythm("Bouncy pop", "A skipping kick that makes the song feel light.",
          kick: "1000001010000000",
          snare: "0000100000001000",
          hihat: "1111111111111111"
        ),
        rhythm("Half-time ballad", "Slow and spacious, good for emotional songs.",
          kick: "1000000000100000",
          snare: "0000000010000000",
          hihat: "1000100010001000"
        )
      ],
      "rock" => [
        rhythm("Classic rock beat", "Kick on 1 and 3, snare on 2 and 4, driving eighths.",
          kick: "1000000010000000",
          snare: "0000100000001000",
          hihat: "1010101010101010"
        ),
        rhythm("Driving rock", "Busy kick for an energetic chorus.",
          kick: "1000001010100000",
          snare: "0000100000001000",
          hihat: "1010101010101010"
        ),
        rhythm("Stomp", "Heavy and simple, made for clapping along.",
          kick: "1000100010001000",
          snare: "0000100000001000",
          hihat: "0000000000000000"
        )
      ],
      "lofi" => [
        rhythm("Lazy boom bap", "A laid-back hip hop groove with a late snare feel.",
          kick: "1000000100100000",
          snare: "0000100000001000",
          hihat: "1010101010101010",
          feel: "swing"
        ),
        rhythm("Dusty shuffle", "Soft and swung, like an old tape.",
          kick: "1000001000000000",
          snare: "0000100000001000",
          hihat: "1011101110111011",
          feel: "swing"
        ),
        rhythm("Sleepy", "Very few hits for a calm mood.",
          kick: "1000000000000000",
          snare: "0000000010000000",
          hihat: "1000100010001000",
          feel: "swing"
        )
      ],
      "electronic" => [
        rhythm("House", "Kick on every beat with open hats between them.",
          kick: "1000100010001000",
          snare: "0000100000001000",
          hihat: "0010001000100010"
        ),
        rhythm("Breakbeat", "Broken kicks for a funky, energetic feel.",
          kick: "1000000000100100",
          snare: "0000100000001000",
          hihat: "1010101010101010"
        ),
        rhythm("Synthwave", "A retro 80s beat with a big snare.",
          kick: "1000100010001000",
          snare: "0000100000001000",
          hihat: "1111111111111111"
        )
      ],
      "jazz" => [
        rhythm("Swing ride", "The classic jazz pattern on the ride cymbal.",
          kick: "1000000000000000",
          snare: "0000000000000000",
          hihat: "1000101110001011",
          feel: "swing"
        ),
        rhythm("Bossa nova", "A gentle Brazilian groove.",
          kick: "1001100110011001",
          snare: "1001001000100100",
          hihat: "1111111111111111"
        ),
        rhythm("Brushes ballad", "Soft and slow with light touches.",
          kick: "1000000010000000",
          snare: "0000100000001000",
          hihat: "1000100010001000",
          feel: "swing"
        )
      ],
      "acoustic" => [
        rhythm("Folk strum", "A simple, natural beat for strummed guitars.",
          kick: "1000000010000000",
          snare: "0000100000001000",
          hihat: "1010101010101010"
        ),
        rhythm("Campfire", "Kick and clap only, like playing with friends.",
          kick: "1000001010000000",
          snare: "0000100000001000",
          hihat: "0000000000000000"
        ),
        rhythm("Waltz", "A soft three-feel that sways.",
          kick: "1000000000001000",
          snare: "0000100010000000",
          hihat: "1010101010101010"
        )
      ]
    }
  end

  defp rhythm(name, description, opts) do
    %{
      "name" => name,
      "description" => description,
      "feel" => Keyword.get(opts, :feel, "straight"),
      "steps" => %{
        "kick" => steps(opts[:kick]),
        "snare" => steps(opts[:snare]),
        "hihat" => steps(opts[:hihat])
      }
    }
  end

  defp steps(pattern) do
    pattern |> String.graphemes() |> Enum.map(&String.to_integer/1)
  end
end
