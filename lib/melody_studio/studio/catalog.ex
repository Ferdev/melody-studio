defmodule MelodyStudio.Studio.Catalog do
  @moduledoc """
  The fixed choices that people can make in the studio: genres, instruments,
  keys, and the built-in rhythm ideas that are used when the AI is not set up.
  """

  # Each genre has a `family`: the group of built-in rhythms and sounds that
  # the app uses for it when the AI is not set up.
  @genres [
    # Pop and dance
    %{
      id: "pop",
      name: "Pop",
      emoji: "🎤",
      group: "Pop and dance",
      family: "pop",
      blurb: "Catchy, bright and easy to sing along to."
    },
    %{
      id: "kpop",
      name: "K-pop",
      emoji: "💫",
      group: "Pop and dance",
      family: "pop",
      blurb: "Polished, punchy and full of hooks."
    },
    %{
      id: "city_pop",
      name: "City pop",
      emoji: "🌃",
      group: "Pop and dance",
      family: "funk",
      blurb: "Smooth 80s Japanese pop with groovy bass."
    },
    %{
      id: "future_funk",
      name: "Future funk",
      emoji: "🪩",
      group: "Pop and dance",
      family: "funk",
      blurb: "Chopped disco samples, filters and a bouncy beat."
    },
    %{
      id: "disco",
      name: "Disco",
      emoji: "🕺",
      group: "Pop and dance",
      family: "funk",
      blurb: "Four on the floor, strings and open hi-hats."
    },
    %{
      id: "funk",
      name: "Funk",
      emoji: "🎺",
      group: "Pop and dance",
      family: "funk",
      blurb: "Tight drums and a bass line that makes you move."
    },
    # Electronic
    %{
      id: "electronic",
      name: "Electronic",
      emoji: "🎛️",
      group: "Electronic",
      family: "electronic",
      blurb: "Synths and a steady dance beat."
    },
    %{
      id: "house",
      name: "House",
      emoji: "🏠",
      group: "Electronic",
      family: "electronic",
      blurb: "Warm club music with a kick on every beat."
    },
    %{
      id: "techno",
      name: "Techno",
      emoji: "🔊",
      group: "Electronic",
      family: "electronic",
      blurb: "Hypnotic, driving and machine-made."
    },
    %{
      id: "synthwave",
      name: "Synthwave",
      emoji: "🌆",
      group: "Electronic",
      family: "electronic",
      blurb: "Retro 80s synths and neon nights."
    },
    %{
      id: "drum_and_bass",
      name: "Drum and bass",
      emoji: "⚡",
      group: "Electronic",
      family: "dnb",
      blurb: "Fast breakbeats and deep bass."
    },
    %{
      id: "chiptune",
      name: "Chiptune",
      emoji: "👾",
      group: "Electronic",
      family: "chiptune",
      blurb: "8-bit bleeps and bloops from old game consoles."
    },
    # Hip hop and soul
    %{
      id: "lofi",
      name: "Lo-fi",
      emoji: "📼",
      group: "Hip hop and soul",
      family: "lofi",
      blurb: "Warm, dusty and relaxed beats."
    },
    %{
      id: "hip_hop",
      name: "Hip hop",
      emoji: "🧢",
      group: "Hip hop and soul",
      family: "hiphop",
      blurb: "Head-nodding drums and a strong groove."
    },
    %{
      id: "trap",
      name: "Trap",
      emoji: "💎",
      group: "Hip hop and soul",
      family: "hiphop",
      blurb: "Booming 808s and rolling hi-hats."
    },
    %{
      id: "rnb",
      name: "R&B",
      emoji: "💜",
      group: "Hip hop and soul",
      family: "hiphop",
      blurb: "Smooth chords and a soulful, laid-back feel."
    },
    %{
      id: "gospel",
      name: "Gospel",
      emoji: "🙌",
      group: "Hip hop and soul",
      family: "pop",
      blurb: "Big, joyful chords and a lift in every chorus."
    },
    # Rock
    %{
      id: "rock",
      name: "Rock",
      emoji: "🎸",
      group: "Rock",
      family: "rock",
      blurb: "Loud guitars and big drums."
    },
    %{
      id: "indie",
      name: "Indie",
      emoji: "🌻",
      group: "Rock",
      family: "rock",
      blurb: "Jangly guitars and a homemade charm."
    },
    %{
      id: "punk",
      name: "Punk",
      emoji: "🧷",
      group: "Rock",
      family: "rock",
      blurb: "Fast, loud and a little messy."
    },
    %{
      id: "metal",
      name: "Metal",
      emoji: "🤘",
      group: "Rock",
      family: "rock",
      blurb: "Heavy guitars and thundering drums."
    },
    # Jazz, blues and world
    %{
      id: "jazz",
      name: "Jazz",
      emoji: "🎷",
      group: "Jazz, blues and world",
      family: "jazz",
      blurb: "Rich chords and a swinging feel."
    },
    %{
      id: "blues",
      name: "Blues",
      emoji: "🎙️",
      group: "Jazz, blues and world",
      family: "jazz",
      blurb: "Soulful, shuffling and full of feeling."
    },
    %{
      id: "bossa_nova",
      name: "Bossa nova",
      emoji: "🏖️",
      group: "Jazz, blues and world",
      family: "latin",
      blurb: "Gentle Brazilian rhythm and soft guitar."
    },
    %{
      id: "reggae",
      name: "Reggae",
      emoji: "🌴",
      group: "Jazz, blues and world",
      family: "latin",
      blurb: "Laid-back offbeat chords and a warm bass."
    },
    %{
      id: "latin",
      name: "Latin",
      emoji: "💃",
      group: "Jazz, blues and world",
      family: "latin",
      blurb: "Lively percussion that makes you dance."
    },
    %{
      id: "afrobeats",
      name: "Afrobeats",
      emoji: "🌍",
      group: "Jazz, blues and world",
      family: "latin",
      blurb: "Bright, bouncy West African grooves."
    },
    # Calm and acoustic
    %{
      id: "acoustic",
      name: "Acoustic",
      emoji: "🪕",
      group: "Calm and acoustic",
      family: "acoustic",
      blurb: "Gentle, natural instruments."
    },
    %{
      id: "folk",
      name: "Folk",
      emoji: "🍂",
      group: "Calm and acoustic",
      family: "acoustic",
      blurb: "Simple songs with guitars and stories."
    },
    %{
      id: "country",
      name: "Country",
      emoji: "🤠",
      group: "Calm and acoustic",
      family: "acoustic",
      blurb: "Twangy guitars and a steady beat."
    },
    %{
      id: "ambient",
      name: "Ambient",
      emoji: "🌌",
      group: "Calm and acoustic",
      family: "ambient",
      blurb: "Floating sounds with very little beat."
    },
    # Film and games
    %{
      id: "cinematic",
      name: "Cinematic",
      emoji: "🎬",
      group: "Film and games",
      family: "ambient",
      blurb: "Big, emotional music like a movie score."
    },
    %{
      id: "classical",
      name: "Classical",
      emoji: "🎻",
      group: "Film and games",
      family: "ambient",
      blurb: "Orchestral and elegant."
    },
    %{
      id: "video_game",
      name: "Video game",
      emoji: "🎮",
      group: "Film and games",
      family: "electronic",
      blurb: "Upbeat adventure music for a modern game."
    }
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

  @max_custom_genre 40

  def genres, do: @genres
  def genre_ids, do: Enum.map(@genres, & &1.id)
  def genre(id), do: Enum.find(@genres, &(&1.id == id))
  def max_custom_genre, do: @max_custom_genre

  @doc "The genres in their display groups, keeping the order of the list."
  def genre_groups(genres \\ @genres) do
    genres
    |> Enum.chunk_by(& &1.group)
    |> Enum.map(fn [first | _] = items -> {first.group, items} end)
  end

  @doc "The genres whose name, group or description contains the search text."
  def search_genres(query) do
    case query |> to_string() |> String.trim() |> String.downcase() do
      "" ->
        @genres

      query ->
        Enum.filter(@genres, fn genre ->
          [genre.name, genre.group, genre.blurb]
          |> Enum.any?(&String.contains?(String.downcase(&1), query))
        end)
    end
  end

  @doc """
  The display name of a genre. A genre that is not in the list is a style
  that the person typed, so its name is the text itself.
  """
  def genre_name(nil), do: "No style yet"
  def genre_name(id), do: (genre(id) || %{name: id}).name

  def genre_emoji(nil), do: "🎵"
  def genre_emoji(id), do: (genre(id) || %{emoji: "✨"}).emoji

  def custom_genre?(nil), do: false
  def custom_genre?(id), do: is_nil(genre(id))

  @doc """
  Turns a typed style into a genre: a known name or id gives its id, other
  text stays as the person wrote it.
  """
  def normalize_genre(text) when is_binary(text) do
    text = text |> String.trim() |> String.replace(~r/\s+/, " ")
    down = String.downcase(text)

    case Enum.find(@genres, &(&1.id == down or String.downcase(&1.name) == down)) do
      nil -> text
      genre -> genre.id
    end
  end

  def normalize_genre(other), do: other

  @doc "The family of built-in rhythms and sounds for a genre."
  def genre_family(id), do: (genre(id) || %{family: "pop"}).family

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
    Map.get(presets(), genre_family(genre), presets()["pop"])
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
      ],
      "funk" => [
        rhythm("Disco strut", "Kick on every beat and open hats on the offbeat.",
          kick: "1000100010001000",
          snare: "0000100000001000",
          hihat: "0010001000100010"
        ),
        rhythm("Funky sixteenths", "Busy hats and a syncopated kick that bounce.",
          kick: "1000001000100100",
          snare: "0000100100001000",
          hihat: "1111111111111111"
        ),
        rhythm("Filter house bounce", "A French-touch groove for chopped samples.",
          kick: "1000100010001000",
          snare: "0000100000001001",
          hihat: "1010111010101110"
        )
      ],
      "hiphop" => [
        rhythm("Head nod", "A classic boom bap groove.",
          kick: "1000000010100000",
          snare: "0000100000001000",
          hihat: "1010101010101010"
        ),
        rhythm("Rolling trap", "Half-time snare with fast, rolling hi-hats.",
          kick: "1000000100100000",
          snare: "0000000010000000",
          hihat: "1111101111111011"
        ),
        rhythm("Slow jam", "Smooth and spacious for soulful songs.",
          kick: "1000000000100000",
          snare: "0000100000001000",
          hihat: "1010101010101010",
          feel: "swing"
        )
      ],
      "latin" => [
        rhythm("Bossa nova", "A gentle Brazilian groove.",
          kick: "1001100110011001",
          snare: "1001001000100100",
          hihat: "1111111111111111"
        ),
        rhythm("One drop", "The reggae beat with the kick on beat 3.",
          kick: "0000000010000000",
          snare: "0000000010000000",
          hihat: "1010101010101010",
          feel: "swing"
        ),
        rhythm("Dembow", "A bouncy dance rhythm.",
          kick: "1000100010001000",
          snare: "0001001000010010",
          hihat: "1010101010101010"
        )
      ],
      "chiptune" => [
        rhythm("Level one", "A cheerful 8-bit beat for the first stage.",
          kick: "1000100010001000",
          snare: "0000100000001000",
          hihat: "1010101010101010"
        ),
        rhythm("Boss fight", "Fast and urgent, with a busy kick.",
          kick: "1010101010101010",
          snare: "0000100000001000",
          hihat: "1111111111111111"
        ),
        rhythm("Overworld march", "A bouncy beat for exploring.",
          kick: "1000001010000000",
          snare: "0000100000001000",
          hihat: "1000100010001000"
        )
      ],
      "dnb" => [
        rhythm("Two-step", "The classic drum and bass break.",
          kick: "1000000000100000",
          snare: "0000100000001000",
          hihat: "1010101010101010"
        ),
        rhythm("Amen-style break", "A chopped, busy break with ghost snares.",
          kick: "1010000000110000",
          snare: "0000100101001001",
          hihat: "1010101010101010"
        ),
        rhythm("Liquid roll", "Smooth and rolling for melodic songs.",
          kick: "1000000000100000",
          snare: "0000100000001000",
          hihat: "1111111111111111"
        )
      ],
      "ambient" => [
        rhythm("Heartbeat", "A soft pulse that stays in the background.",
          kick: "1000000010000000",
          snare: "0000000000000000",
          hihat: "0000000000000000"
        ),
        rhythm("Gentle tick", "Light ticks that keep time quietly.",
          kick: "1000000000000000",
          snare: "0000000000000000",
          hihat: "1000100010001000"
        ),
        rhythm("Epic build", "Slow, heavy hits for big moments.",
          kick: "1000000010000000",
          snare: "0000000000001000",
          hihat: "0000000000000000"
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
