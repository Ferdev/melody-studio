defmodule MelodyStudio.AI do
  @moduledoc """
  The musical ideas of the app: rhythm ideas, the arrangement plan of a song and
  mix settings. Claude writes them when an Anthropic API key is set. Without a
  key, the app uses simple built-in ideas so that every step still works.
  """

  alias MelodyStudio.AI.Claude
  alias MelodyStudio.Studio.{Catalog, Melody, Track}

  @note_names ~w(C C# D Eb E F F# G Ab A Bb B)
  @chord_regex ~r/^[A-G](#|b)?(maj7|m7|m|dim|aug|sus2|sus4|7|6|9|add9)?(\/[A-G](#|b)?)?$/

  defdelegate configured?, to: Claude

  # ---------------------------------------------------------------------------
  # Rhythm ideas

  @rhythm_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["rhythms"],
    "properties" => %{
      "rhythms" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["name", "description", "feel", "kick", "snare", "hihat"],
          "properties" => %{
            "name" => %{"type" => "string"},
            "description" => %{"type" => "string"},
            "feel" => %{"type" => "string", "enum" => ["straight", "swing"]},
            "kick" => %{"type" => "array", "items" => %{"type" => "integer"}},
            "snare" => %{"type" => "array", "items" => %{"type" => "integer"}},
            "hihat" => %{"type" => "array", "items" => %{"type" => "integer"}}
          }
        }
      }
    }
  }

  @doc """
  Returns `{:ok, rhythms, source}` where `source` is `:ai` or `:builtin`.
  """
  def rhythm_ideas(song) do
    genre = song.genre || "pop"

    system = """
    You are a friendly drummer and producer. You suggest drum patterns for people
    who love music but do not know music software. Write names and descriptions in
    plain, warm words, with no technical jargon.
    """

    prompt = """
    Suggest 3 different drum patterns for a #{Catalog.genre_name(genre)} song at #{song.tempo} BPM \
    in #{song.key}.

    Each pattern is one bar of 4/4 split into 16 sixteenth-note steps. Give the kick, snare \
    and hi-hat as lists of exactly 16 numbers, 1 for a hit and 0 for a rest. Step 1 is the \
    first beat; steps 5, 9 and 13 are beats 2, 3 and 4.

    Give each pattern a short catchy name (at most 4 words) and one sentence that says how \
    it feels. Make the 3 patterns clearly different: for example calm, medium and energetic.
    """

    with {:ok, %{"rhythms" => [_ | _] = rhythms}} <-
           Claude.structured(system, prompt, @rhythm_schema, effort: "low", max_tokens: 8_000) do
      {:ok, rhythms |> Enum.take(4) |> Enum.map(&normalize_rhythm/1), :ai}
    else
      _ -> {:ok, Catalog.preset_rhythms(genre), :builtin}
    end
  end

  def normalize_rhythm(rhythm) do
    steps = rhythm["steps"] || rhythm

    %{
      "name" => String.slice(to_string(rhythm["name"] || "Rhythm"), 0, 40),
      "description" => String.slice(to_string(rhythm["description"] || ""), 0, 200),
      "feel" => if(rhythm["feel"] == "swing", do: "swing", else: "straight"),
      "steps" => %{
        "kick" => normalize_steps(steps["kick"]),
        "snare" => normalize_steps(steps["snare"]),
        "hihat" => normalize_steps(steps["hihat"])
      }
    }
  end

  defp normalize_steps(list) when is_list(list) do
    list
    |> Enum.map(fn v -> if v in [1, "1", true], do: 1, else: 0 end)
    |> Enum.concat(List.duplicate(0, 16))
    |> Enum.take(16)
  end

  defp normalize_steps(_), do: List.duplicate(0, 16)

  # ---------------------------------------------------------------------------
  # Arrangement plan

  @arrangement_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["summary", "sections", "tracks"],
    "properties" => %{
      "summary" => %{"type" => "string"},
      "sections" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["name", "chords", "energy", "melody"],
          "properties" => %{
            "name" => %{"type" => "string"},
            "chords" => %{"type" => "array", "items" => %{"type" => "string"}},
            "energy" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
            "melody" => %{"type" => "boolean"}
          }
        }
      },
      "tracks" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["instrument", "role", "prompt"],
          "properties" => %{
            "instrument" => %{"type" => "string"},
            "role" => %{"type" => "string"},
            "prompt" => %{"type" => "string"}
          }
        }
      }
    }
  }

  @doc """
  Builds the arrangement plan of a song from its melody and style choices.
  Returns `{:ok, plan, source}` where `source` is `:ai` or `:builtin`.
  """
  def arrangement(song, notes) do
    bars = section_bars(notes)

    system = """
    You are an experienced music producer and arranger. You turn a simple melody into a
    full song arrangement. You know harmony well: pick chords that fit the notes of the
    melody in each bar, and keep the harmony natural for the genre.
    """

    prompt = """
    Arrange a full song around this melody.

    Genre: #{Catalog.genre_name(song.genre)}
    Tempo: #{song.tempo} BPM, 4/4 time
    Key: #{song.key}
    Drum pattern chosen by the user: #{rhythm_name(song)}
    Instruments for the new tracks: #{Enum.map_join(song.instruments, ", ", &Catalog.instrument_name/1)}

    The melody is #{Melody.bars(notes)} bar(s) long. Each note is written as
    note name and octave, start beat (0 is the first beat of bar 1), and length in beats:
    #{describe_notes(notes)}

    Write 4 to 6 sections (for example Intro, Verse, Chorus, Bridge, Outro). Every section
    is exactly #{bars} bars long, so give exactly #{bars} chord symbols per section: one chord
    per bar. Use simple chord symbols such as C, Am, F, G7, Dm7, Fmaj7, Bb, F#m, Esus4.
    In sections where the melody plays (`melody: true`), the chords must fit the melody notes
    of each bar. Set `energy` to low, medium or high.

    Write one track for each instrument listed above, using the instrument id exactly as
    given here: #{Enum.join(song.instruments, ", ")}. For each track, write `role` (a few words,
    such as "steady groove" or "warm chords") and `prompt`: a text prompt for an AI music
    model that will record this instrument alone. The prompt must name the genre, the
    instrument, the tempo, the key, the main chords and the mood, and say that it is a solo
    instrumental stem with no vocals. Keep each prompt under 60 words.

    Write `summary`: two friendly sentences for the user that describe the song you planned,
    in plain words with no music jargon.
    """

    case Claude.structured(system, prompt, @arrangement_schema, effort: "medium") do
      {:ok, plan} -> {:ok, normalize_arrangement(plan, song, bars), :ai}
      _ -> {:ok, basic_arrangement(song, notes), :builtin}
    end
  end

  @doc "Section length in bars: the melody length, at least 4 bars."
  def section_bars(notes), do: max(Melody.bars(notes), 4)

  defp rhythm_name(%{rhythm: %{"name" => name}}), do: name
  defp rhythm_name(_), do: "none, choose one that fits"

  defp describe_notes(notes) do
    notes
    |> Enum.take(400)
    |> Enum.map_join("\n", fn n ->
      "#{note_name(n["pitch"])} start #{n["start"]} length #{n["duration"]}"
    end)
  end

  def note_name(pitch) do
    "#{Enum.at(@note_names, rem(pitch, 12))}#{div(pitch, 12) - 1}"
  end

  def normalize_arrangement(plan, song, bars) do
    tonic = song.key |> String.split(" ") |> hd()
    tonic_chord = if String.ends_with?(song.key, "minor"), do: tonic <> "m", else: tonic

    sections =
      (plan["sections"] || [])
      |> Enum.take(8)
      |> Enum.map(fn section ->
        chords =
          (section["chords"] || [])
          |> Enum.map(&clean_chord(&1, tonic_chord))
          |> fit_length(bars, tonic_chord)

        %{
          "name" => String.slice(to_string(section["name"] || "Section"), 0, 30),
          "bars" => bars,
          "chords" => chords,
          "energy" =>
            if(section["energy"] in ~w(low medium high), do: section["energy"], else: "medium"),
          "melody" => section["melody"] != false
        }
      end)

    sections = if sections == [], do: basic_sections(song, bars), else: sections
    by_instrument = Map.new(plan["tracks"] || [], &{&1["instrument"], &1})

    tracks =
      Enum.map(song.instruments, fn instrument ->
        track = Map.get(by_instrument, instrument, %{})

        %{
          "instrument" => instrument,
          "role" =>
            String.slice(to_string(track["role"] || Catalog.default_role(instrument)), 0, 40),
          "prompt" => track["prompt"] || default_prompt(song, instrument, sections)
        }
      end)

    %{
      "summary" => to_string(plan["summary"] || ""),
      "sections" => sections,
      "tracks" => tracks
    }
  end

  defp clean_chord(chord, fallback) do
    chord = chord |> to_string() |> String.trim()
    if Regex.match?(@chord_regex, chord), do: chord, else: fallback
  end

  defp fit_length([], bars, fallback), do: List.duplicate(fallback, bars)

  defp fit_length(chords, bars, _fallback) do
    chords |> Stream.cycle() |> Enum.take(bars)
  end

  @doc "A simple arrangement that works without the AI."
  def basic_arrangement(song, notes) do
    bars = section_bars(notes)
    sections = basic_sections(song, bars)

    %{
      "summary" =>
        "A simple #{Catalog.genre_name(song.genre)} song built around your melody, with a quiet start, " <>
          "two big choruses and a soft ending.",
      "sections" => sections,
      "tracks" =>
        Enum.map(song.instruments, fn instrument ->
          %{
            "instrument" => instrument,
            "role" => Catalog.default_role(instrument),
            "prompt" => default_prompt(song, instrument, sections)
          }
        end)
    }
  end

  defp basic_sections(song, bars) do
    chords = basic_progression(song.key) |> Stream.cycle() |> Enum.take(bars)

    [
      {"Intro", "low", false},
      {"Verse", "medium", true},
      {"Chorus", "high", true},
      {"Verse", "medium", true},
      {"Chorus", "high", true},
      {"Outro", "low", false}
    ]
    |> Enum.map(fn {name, energy, melody} ->
      %{
        "name" => name,
        "bars" => bars,
        "chords" => chords,
        "energy" => energy,
        "melody" => melody
      }
    end)
  end

  @doc "A common four-chord progression in the given key, such as I V vi IV."
  def basic_progression(key) do
    [tonic, scale] = String.split(key, " ")
    root = Enum.find_index(@note_names, &(&1 == tonic)) || 0

    degrees =
      if scale == "minor",
        do: [{0, "m"}, {8, ""}, {3, ""}, {10, ""}],
        else: [{0, ""}, {7, ""}, {9, "m"}, {5, ""}]

    Enum.map(degrees, fn {interval, quality} ->
      Enum.at(@note_names, rem(root + interval, 12)) <> quality
    end)
  end

  @doc "A text prompt for the AI music model when no plan gives one."
  def default_prompt(song, instrument, sections) do
    chords =
      sections
      |> Enum.flat_map(& &1["chords"])
      |> Enum.uniq()
      |> Enum.take(6)
      |> Enum.join(" ")

    "#{Catalog.genre_name(song.genre)} #{Catalog.instrument_name(instrument) |> String.downcase()}, " <>
      "#{song.tempo} bpm, key of #{song.key}, chords #{chords}, solo instrumental stem, " <>
      "no vocals, clean studio recording"
  end

  # ---------------------------------------------------------------------------
  # Mix suggestions

  @mix_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["summary", "tracks"],
    "properties" => %{
      "summary" => %{"type" => "string"},
      "tracks" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ~w(id volume pan reverb delay low mid high punch),
          "properties" => %{
            "id" => %{"type" => "integer"},
            "volume" => %{"type" => "integer"},
            "pan" => %{"type" => "integer"},
            "reverb" => %{"type" => "integer"},
            "delay" => %{"type" => "integer"},
            "low" => %{"type" => "integer"},
            "mid" => %{"type" => "integer"},
            "high" => %{"type" => "integer"},
            "punch" => %{"type" => "integer"}
          }
        }
      }
    }
  }

  @doc """
  Suggests mix settings for the tracks of a song. Returns
  `{:ok, %{"summary" => text, "tracks" => %{track_id => mix}}, source}`.
  """
  def mix_suggestion(song, tracks) do
    system = """
    You are a mixing engineer who helps beginners. You set levels, stereo position and
    simple effects so that every instrument can be heard and the song sounds full and clear.
    """

    prompt = """
    Suggest mix settings for this #{Catalog.genre_name(song.genre)} song at #{song.tempo} BPM.

    The settings and their ranges:
    - volume: 0 to 100 (80 is normal)
    - pan: -100 (left) to 100 (right), 0 is the middle
    - reverb: 0 to 100 (amount of room sound)
    - delay: 0 to 100 (amount of echo)
    - low, mid, high: -12 to 12 (EQ in dB for bass, middle and treble)
    - punch: 0 to 100 (amount of compression)

    Tracks (id, instrument, role, current settings):
    #{Enum.map_join(tracks, "\n", fn t -> "#{t.id}: #{Catalog.instrument_name(t.instrument)} (#{t.role}) #{Jason.encode!(t.mix)}" end)}

    Keep the user's melody clear and in front. Keep the bass and kick in the middle.
    Give settings for every track id. Write `summary`: two friendly sentences in plain
    words that say what you changed and why.
    """

    case Claude.structured(system, prompt, @mix_schema, effort: "low", max_tokens: 8_000) do
      {:ok, %{"tracks" => suggested} = result} ->
        ids = MapSet.new(tracks, & &1.id)

        mixes =
          suggested
          |> Enum.filter(&MapSet.member?(ids, &1["id"]))
          |> Map.new(fn t ->
            current = Enum.find(tracks, &(&1.id == t["id"])).mix
            {to_string(t["id"]), Track.normalize_mix(Map.merge(current, Map.delete(t, "id")))}
          end)

        {:ok, %{"summary" => to_string(result["summary"]), "tracks" => mixes}, :ai}

      _ ->
        {:ok, basic_mix(tracks), :builtin}
    end
  end

  @basic_mix %{
    "melody" => %{
      "volume" => 88,
      "pan" => 0,
      "reverb" => 25,
      "delay" => 15,
      "high" => 2,
      "punch" => 25
    },
    "drums" => %{"volume" => 80, "pan" => 0, "reverb" => 10, "punch" => 55, "low" => 2},
    "bass" => %{
      "volume" => 78,
      "pan" => 0,
      "reverb" => 0,
      "punch" => 45,
      "low" => 2,
      "high" => -3
    },
    "keys" => %{"volume" => 66, "pan" => -25, "reverb" => 25, "mid" => -1},
    "guitar" => %{"volume" => 64, "pan" => 30, "reverb" => 20, "low" => -3},
    "strings" => %{"volume" => 58, "pan" => -40, "reverb" => 45, "low" => -4},
    "pads" => %{"volume" => 54, "pan" => 40, "reverb" => 50, "delay" => 10, "low" => -4}
  }

  defp basic_mix(tracks) do
    mixes =
      Map.new(tracks, fn track ->
        preset = Map.get(@basic_mix, track.instrument, %{})
        mix = Track.normalize_mix(Map.merge(Track.mix_defaults(), preset))
        {to_string(track.id), Map.merge(mix, Map.take(track.mix, ["mute", "solo"]))}
      end)

    %{
      "summary" =>
        "Your melody sits in front, the drums and bass stay in the middle, and the other " <>
          "instruments are spread to the left and right so each one has its own space.",
      "tracks" => mixes
    }
  end
end
