# Rondar Scratch Project

Create a new project from scratch in this directory.

Project name: Melody Studio
Requested stack: %{"stack" => "Elixir, Phoenix (LiveView) with TypeScript frontend, PostgreSQL"}
Detected language: unknown
Detected framework: unknown
Package manager: unknown
Required services: 

Plan:
# Melody Studio

## Goal
Let people make a full song from a simple melody. They need musical taste, not DAW skills. AI does the hard parts: arrangement, instruments, rhythm, effects and mixing.

## Users
- People who like music but do not know DAWs.
- Hobby musicians who want quick song ideas.

## Features of the first version
1. **Sign in and songs**
   - Email and password sign-in (Phoenix `phx.gen.auth`).
   - Each user has a list of songs. They can create, open, rename and delete songs.
2. **Record a melody**
   - Virtual piano on screen. Play with mouse, touch or computer keyboard.
   - MIDI keyboard input through the Web MIDI API.
   - Set tempo and key. Metronome and count-in.
   - Record, play back, undo and re-record. Store the melody as MIDI notes.
3. **Choose the style**
   - Pick a genre (for example pop, rock, lo-fi, electronic, jazz, acoustic).
   - Pick instruments for new tracks (drums, bass, keys, guitar, strings, pads).
   - AI recommends rhythms and drum patterns that fit the genre and tempo. The user picks one.
4. **AI builds the song**
   - Claude (Anthropic API, model `claude-sonnet-5-5`) reads the melody, genre and choices. It returns a structured arrangement plan: sections, chords, instruments, rhythm and text prompts for each track.
   - An AI music model generates real audio stems for each track, guided by the melody and the plan. Use a hosted model with melody conditioning (for example MusicGen Melody on Replicate). Wrap it behind a provider module so it can be swapped.
   - Generation runs as background jobs (Oban). The page shows live progress through Phoenix channels or LiveView.
   - The user can regenerate one track, add a new track, or remove a track.
5. **Effects and mixing**
   - Per track: volume, pan, mute, solo.
   - Simple effects: reverb, delay, EQ, compression. Built in the browser with the Web Audio API (Tone.js).
   - "AI mix" button: Claude suggests levels and effect settings. The user can accept or adjust with friendly sliders.
6. **Export**
   - Render the mix in the browser (offline audio context) and download as WAV. MP3 if simple to add.

## Stack and services
- **Backend:** Elixir, Phoenix, Phoenix LiveView for pages, Ecto, PostgreSQL.
- **Background jobs:** Oban (uses PostgreSQL).
- **Frontend audio:** TypeScript, Tone.js, Web Audio API, Web MIDI API. Bundled with esbuild (Phoenix default). LiveView hooks connect the audio code to the pages.
- **AI:** Anthropic API for arrangement and mixing ideas. Hosted AI music API (Replicate) for audio stems.
- **File storage:** S3-compatible object storage for audio stems. Use local disk in development.
- **Config:** API keys from environment variables: `ANTHROPIC_API_KEY`, `REPLICATE_API_TOKEN`, storage credentials.

## Data model (first version)
- User
- Song: title, genre, tempo, key, arrangement plan (JSON)
- Melody: MIDI notes (JSON) for a song
- Track: song, instrument, role, prompt, status, audio file path, mix settings (JSON)
- Generation job status for progress display

## Visual style
Bright, playful and simple. Big friendly buttons, rounded shapes, soft bright colors, clear icons. Plain words instead of DAW terms. Tailwind CSS.

## Choices from the conversation
- Web app in the browser.
- Main features: record melody, AI accompaniment, genre/instruments/rhythms, effects and mixing, audio export.
- Hosted AI API (Claude) for arrangement ideas. Users sign in and save songs.
- Sounds come from an AI music model that generates real audio stems (richer, slower, costs more).
- Stack: TypeScript, Elixir Phoenix, PostgreSQL.
- Style: bright, playful and simple.

## Out of scope for now
- Real-time collaboration, sharing and publishing.
- Vocals and lyrics.
- Detailed note editing like a full piano roll.
- Payments and usage limits (add later, since stem generation costs money).
