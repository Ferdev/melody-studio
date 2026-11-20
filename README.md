# Melody Studio

Melody Studio turns a short melody into a full song. You play a tune on the on-screen piano, your computer keyboard or a MIDI keyboard, pick a style and the instruments you want, and the app builds the rest of the band around your melody. You can then mix the song with simple sliders and download it as a WAV file.

## How a song is made

1. Melody. Press Record and play: by default the take starts with the first note you play, and the metronome follows from there. Turn that off to record after a four-beat count-in instead; notes you play during the count-in are kept. While you record or play back, a playhead moves over the notes and the notes that sound light up. You can play a take back, undo it, record again or clear it. After a take, the note editor below the piano shows each note as a block. Pick notes one by one, with a box or with a lasso, then drag them to move them earlier, later, higher or lower, drag a right edge to change their length, or use the buttons and the arrow keys. All the picked notes change together. Tap a bar number, or drag across several, to move bars earlier or later, repeat them, add an empty bar before them, or remove them. The app stores the notes as MIDI data.
2. Style. Choose from more than 30 styles in groups (from pop, rock and jazz to future funk, chiptune, drum and bass and city pop), search the list, or type any other style. Then choose the instruments that join your melody (drums, bass, keys, guitar, strings and pads). Ask for rhythm ideas, listen to them and pick one.
3. Build. Claude reads the melody and your choices and writes an arrangement plan: the sections of the song, one chord per bar, and a text prompt for each instrument. An AI music model then records each instrument, guided by your melody. The page shows the progress of each track as it happens. You can make one track again, add an instrument or remove one.
4. Mix and export. Each track has loudness, left and right position, mute, solo, reverb, echo, a three-band EQ and compression. The AI mix button suggests settings that you can accept or ignore. The download renders the whole mix in the browser and saves it as a WAV file.

Every step also works without the AI services. Without an Anthropic API key, the app uses built-in rhythm ideas, a common chord progression in the key of the song and a balanced starting mix. Without a Replicate token, each instrument plays with a built-in browser sound that follows the plan, so you can still hear, mix and download the song.

## Running it locally

You need Elixir, Erlang (see `mise.toml`), Node.js and PostgreSQL.

```sh
mix setup
mix phx.server
```

Then open http://localhost:4000 and create an account, or log in with the test account that `mix setup` makes in development: `test@example.com` with the password `melodystudio123`. To add it to an existing database, run `mix run priv/repo/seeds.exs`.

## Configuration

The app reads these environment variables at runtime.

| Variable | What it does |
| --- | --- |
| `ANTHROPIC_API_KEY` | Turns on Claude for rhythm ideas, arrangement plans and mix suggestions. The model is `claude-sonnet-5-5`, set in `config/config.exs`. |
| `REPLICATE_API_TOKEN` | Turns on AI audio for each track with MusicGen (melody model) on Replicate. |
| `REPLICATE_MUSICGEN_VERSION` | Optional. The MusicGen model version to call on Replicate. |
| `S3_BUCKET` | Stores audio files in an S3-compatible bucket instead of the local disk. |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | Credentials for the bucket. |
| `S3_HOST` | Optional. The host of S3-compatible storage that is not AWS. |

In development, audio files go to `priv/static/uploads`, which git ignores.

## Where things live

- `lib/melody_studio/studio.ex` has songs, melodies, tracks and their mix settings.
- `lib/melody_studio/ai.ex` and `lib/melody_studio/ai/claude.ex` have the Claude prompts and the HTTP client. Each request asks for JSON that matches a schema, and the app checks every answer before it uses it.
- `lib/melody_studio/stems.ex` defines the behaviour for AI music providers, and `lib/melody_studio/stems/replicate.ex` implements it. Point `config :melody_studio, MelodyStudio.Stems, provider: ...` at another module to swap the provider.
- `lib/melody_studio/workers` has the Oban jobs that plan the song and make each track.
- `lib/melody_studio_web/live/song_live` has the song list and the studio page.
- `assets/js/audio` and `assets/js/hooks` have the browser audio code: the piano recorder, the song player, the effects and the WAV export, built with Tone.js.

## Tests

```sh
mix test
cd assets && npm run typecheck
```

The tests stub the Anthropic and Replicate APIs, so they need no keys and make no network calls.

## Limits of this version

Replicate makes stems of at most 30 seconds, so on a longer song the AI audio of a track covers only the start of the song. AI stems also do not follow the beat grid exactly. Sharing, vocals, detailed note editing and usage limits are not part of this version.
