defmodule MelodyStudioWeb.SongLive.StudioComponents do
  @moduledoc """
  The parts of the studio page: one component for each step.
  """
  use MelodyStudioWeb, :html

  alias MelodyStudio.{Storage, Studio}
  alias MelodyStudio.Studio.{Catalog, Melody}

  ## Step navigation

  attr :song, :map, required: true
  attr :step, :string, required: true

  def step_nav(assigns) do
    song = assigns.song

    assigns =
      assign(assigns, :items, [
        {"melody", "Melody", "hero-musical-note", Studio.melody_notes(song) != []},
        {"style", "Style", "hero-swatch", song.genre != nil and song.instruments != []},
        {"build", "Build", "hero-sparkles", song.arrangement != nil},
        {"mix", "Mix & export", "hero-adjustments-horizontal", false}
      ])

    ~H"""
    <nav id="step-nav" class="grid grid-cols-4 gap-2 rounded-box bg-base-100 p-2 shadow-sm">
      <.link
        :for={{{id, label, icon, done?}, index} <- Enum.with_index(@items, 1)}
        id={"step-#{id}"}
        patch={~p"/songs/#{@song}?step=#{id}"}
        class={[
          "flex flex-col items-center gap-1 rounded-2xl px-2 py-2 text-center text-xs font-semibold transition sm:flex-row sm:justify-center sm:text-sm",
          @step == id && "bg-primary text-primary-content shadow",
          @step != id && "hover:bg-base-200"
        ]}
      >
        <span class={[
          "grid size-7 shrink-0 place-items-center rounded-full",
          @step == id && "bg-primary-content/20",
          @step != id && done? && "bg-success text-success-content",
          @step != id && !done? && "bg-base-200"
        ]}>
          <.icon :if={done? and @step != id} name="hero-check" class="size-4" />
          <span :if={!done? or @step == id}>{index}</span>
        </span>
        <span class="hidden sm:inline">{label}</span>
        <span class="sm:hidden">{label |> String.split(" ") |> hd()}</span>
      </.link>
    </nav>
    """
  end

  ## Step 1: melody

  attr :song, :map, required: true
  attr :settings_form, :map, required: true

  def melody_step(assigns) do
    notes = Studio.melody_notes(assigns.song)
    assigns = assign(assigns, notes: notes, keys: piano_keys())

    ~H"""
    <section class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
      <div class="min-w-0 space-y-4 rounded-box bg-base-100 p-5 shadow-sm">
        <div>
          <h2 class="font-display text-xl font-bold">Play your melody</h2>
          <p class="text-base-content/70">
            Press Record and play your tune. Recording starts with the first note you play.
            Press Stop when you are done.
          </p>
        </div>

        <div
          id="melody-recorder"
          phx-hook="MelodyRecorder"
          data-notes={Jason.encode!(@notes)}
          data-tempo={@song.tempo}
          data-max-beats={Melody.max_beats()}
        >
          <div id="melody-recorder-ui" phx-update="ignore" class="space-y-4">
            <div class="flex flex-wrap items-center gap-2">
              <button type="button" data-action="record" class="btn btn-primary rounded-full">
                <span class="inline-block size-3 rounded-full bg-current"></span> Record
              </button>
              <button type="button" data-action="stop" class="btn rounded-full" disabled>
                <.icon name="hero-stop-solid" class="size-4" /> Stop
              </button>
              <button type="button" data-action="play" class="btn btn-secondary rounded-full">
                <.icon name="hero-play-solid" class="size-4" /> Play
              </button>
              <button type="button" data-action="undo" class="btn btn-ghost rounded-full" disabled>
                <.icon name="hero-arrow-uturn-left" class="size-4" /> Undo
              </button>
              <button type="button" data-action="clear" class="btn btn-ghost rounded-full">
                <.icon name="hero-trash" class="size-4" /> Clear
              </button>
            </div>

            <div class="flex flex-wrap gap-x-6 gap-y-2 text-sm">
              <label class="flex cursor-pointer items-center gap-2">
                <input
                  type="checkbox"
                  data-option="metronome"
                  class="toggle toggle-primary toggle-sm"
                  checked
                /> Metronome
              </label>
              <label class="flex cursor-pointer items-center gap-2">
                <input
                  type="checkbox"
                  data-option="waitForNote"
                  class="toggle toggle-primary toggle-sm"
                  checked
                /> Start on my first note
              </label>
              <label
                class="flex cursor-pointer items-center gap-2"
                title="Turn off Start on my first note to use the count-in"
              >
                <input
                  type="checkbox"
                  data-option="countIn"
                  class="toggle toggle-primary toggle-sm"
                  checked
                /> Count-in
              </label>
              <label class="flex cursor-pointer items-center gap-2">
                <input
                  type="checkbox"
                  data-option="snap"
                  class="toggle toggle-primary toggle-sm"
                  checked
                /> Tidy my timing
              </label>
            </div>

            <div
              data-role="status"
              class="flex min-h-12 items-center gap-3 rounded-2xl bg-base-200 px-4 py-2 font-semibold"
              aria-live="polite"
            >
              Ready when you are.
            </div>

            <div class="-mx-5 overflow-x-auto px-5 pb-2">
              <div data-role="keyboard" class="relative mx-auto flex w-max">
                <div
                  :for={key <- @keys}
                  class="piano-key-white"
                  data-pitch={key.pitch}
                  role="button"
                  aria-label={key.name}
                >
                  <span class="pointer-events-none absolute inset-x-0 bottom-2 text-center text-[11px] font-semibold text-neutral/60">
                    <span :if={key.computer} class="hidden lg:block">{key.computer}</span>
                    <span :if={String.starts_with?(key.name, "C")}>{key.name}</span>
                  </span>
                  <div
                    :if={key.black}
                    class="piano-key-black left-full"
                    data-pitch={key.black.pitch}
                    role="button"
                    aria-label={key.black.name}
                  >
                    <span
                      :if={key.black.computer}
                      class="pointer-events-none absolute inset-x-0 bottom-2 hidden text-center text-[10px] font-semibold opacity-70 lg:block"
                    >
                      {key.black.computer}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <p data-role="midi-status" class="text-sm text-base-content/60"></p>

            <div
              data-role="editor"
              class="hidden space-y-3 rounded-2xl border border-base-300 p-4"
            >
              <div>
                <h3 class="font-display text-lg font-bold">Fix your notes</h3>
                <p class="text-sm text-base-content/70">
                  Tap a note to pick it, or draw a box or a lasso around several notes.
                  Drag picked notes to move them, and drag a right edge to change their length.
                  Tap a bar number to work on a whole bar.
                </p>
              </div>

              <div class="flex flex-wrap items-center gap-2">
                <div class="join" role="group" aria-label="Selection tool">
                  <button
                    type="button"
                    data-tool="pointer"
                    class="btn btn-sm join-item btn-active"
                    aria-pressed="true"
                    title="Pick notes one by one. Drag on an empty spot to draw a box."
                  >
                    <.icon name="hero-cursor-arrow-rays" class="size-4" /> Pick
                  </button>
                  <button
                    type="button"
                    data-tool="box"
                    class="btn btn-sm join-item"
                    aria-pressed="false"
                    title="Draw a box around the notes you want"
                  >
                    <svg
                      viewBox="0 0 20 20"
                      class="size-4"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="1.8"
                      stroke-dasharray="3 2"
                      aria-hidden="true"
                    >
                      <rect x="3" y="4" width="14" height="12" rx="1.5" />
                    </svg>
                    Box
                  </button>
                  <button
                    type="button"
                    data-tool="lasso"
                    class="btn btn-sm join-item"
                    aria-pressed="false"
                    title="Draw a free shape around the notes you want"
                  >
                    <svg
                      viewBox="0 0 20 20"
                      class="size-4"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="1.8"
                      stroke-linecap="round"
                      aria-hidden="true"
                    >
                      <path
                        d="M10 3c4.4 0 7 2.2 7 5s-2.6 5-7 5-7-2.2-7-5 2.6-5 7-5Z"
                        stroke-dasharray="3 2"
                      />
                      <path d="M6 12.5c-.8 1.6-.4 3.3 1.2 4 1.3.5 2.2-.3 2-1.5" />
                    </svg>
                    Lasso
                  </button>
                </div>
                <button type="button" data-select="all" class="btn btn-sm btn-ghost">
                  Select all
                </button>
                <button type="button" data-select="none" class="btn btn-sm btn-ghost" disabled>
                  Select none
                </button>
              </div>

              <div class="overflow-x-auto rounded-xl bg-base-200/70">
                <div data-role="roll" class="relative select-none" style="touch-action: pan-x;"></div>
              </div>

              <div class="flex flex-wrap items-center gap-2">
                <span data-role="selection" class="w-full text-sm font-semibold" aria-live="polite">
                  No notes picked yet.
                </span>
                <div class="join">
                  <button type="button" data-edit="earlier" class="btn btn-sm join-item" disabled>
                    <.icon name="hero-arrow-left" class="size-4" /> Earlier
                  </button>
                  <button type="button" data-edit="later" class="btn btn-sm join-item" disabled>
                    Later <.icon name="hero-arrow-right" class="size-4" />
                  </button>
                </div>
                <div class="join">
                  <button type="button" data-edit="shorter" class="btn btn-sm join-item" disabled>
                    <.icon name="hero-minus" class="size-4" /> Shorter
                  </button>
                  <button type="button" data-edit="longer" class="btn btn-sm join-item" disabled>
                    <.icon name="hero-plus" class="size-4" /> Longer
                  </button>
                </div>
                <div class="join">
                  <button type="button" data-edit="lower" class="btn btn-sm join-item" disabled>
                    <.icon name="hero-arrow-down" class="size-4" /> Lower
                  </button>
                  <button type="button" data-edit="higher" class="btn btn-sm join-item" disabled>
                    <.icon name="hero-arrow-up" class="size-4" /> Higher
                  </button>
                </div>
                <button
                  type="button"
                  data-edit="delete"
                  class="btn btn-sm btn-ghost text-error"
                  disabled
                >
                  <.icon name="hero-trash" class="size-4" /> Delete
                </button>
              </div>

              <div
                data-role="bar-tools"
                class="hidden flex-wrap items-center gap-2 rounded-xl bg-secondary/10 p-3"
              >
                <span data-role="bar-label" class="w-full text-sm font-semibold"></span>
                <div class="join">
                  <button type="button" data-bar-edit="earlier" class="btn btn-sm join-item">
                    <.icon name="hero-arrow-left" class="size-4" /> Move earlier
                  </button>
                  <button type="button" data-bar-edit="later" class="btn btn-sm join-item">
                    Move later <.icon name="hero-arrow-right" class="size-4" />
                  </button>
                </div>
                <button type="button" data-bar-edit="duplicate" class="btn btn-sm">
                  <.icon name="hero-document-duplicate" class="size-4" /> Repeat
                </button>
                <button type="button" data-bar-edit="insert" class="btn btn-sm">
                  <.icon name="hero-plus" class="size-4" /> Add an empty bar before
                </button>
                <button type="button" data-bar-edit="delete" class="btn btn-sm btn-ghost text-error">
                  <.icon name="hero-trash" class="size-4" /> Remove
                </button>
                <p data-role="bar-hint" class="w-full text-xs text-base-content/60"></p>
              </div>

              <p class="hidden text-xs text-base-content/60 lg:block">
                Shortcuts: arrow keys move the picked notes, Shift with the left and right arrows
                changes their length, Delete removes them, Ctrl or Cmd with A picks all, and Esc
                picks none. Hold Shift while you tap or draw to add to the notes you picked.
              </p>
            </div>
          </div>
        </div>
      </div>

      <aside class="space-y-4">
        <.form
          for={@settings_form}
          id="song-settings-form"
          phx-change="update_settings"
          class="space-y-2 rounded-box bg-base-100 p-5 shadow-sm"
        >
          <h3 class="font-display text-lg font-bold">Speed and key</h3>
          <label for="song-tempo" class="block text-sm font-semibold">
            Speed: <span id="tempo-value">{@settings_form[:tempo].value}</span> BPM
          </label>
          <input
            id="song-tempo"
            type="range"
            min="50"
            max="200"
            name={@settings_form[:tempo].name}
            value={@settings_form[:tempo].value}
            class="range range-primary range-sm"
            phx-debounce="300"
          />
          <.input
            field={@settings_form[:key]}
            type="select"
            label="Key"
            options={Catalog.key_options()}
          />
        </.form>

        <div class="rounded-box bg-base-100 p-5 text-sm shadow-sm">
          <h3 class="mb-2 font-display text-lg font-bold">Tips</h3>
          <ul class="list-disc space-y-1 pl-5 text-base-content/75">
            <li>Tap the piano keys with your mouse or finger.</li>
            <li class="hidden lg:list-item">
              On a computer, the letters <kbd class="kbd kbd-sm">A</kbd>
              to <kbd class="kbd kbd-sm">;</kbd>
              play the white keys. <kbd class="kbd kbd-sm">Z</kbd>
              and <kbd class="kbd kbd-sm">X</kbd>
              move one octave down or up.
            </li>
            <li>Connect a MIDI keyboard to play with real keys.</li>
            <li>Keep it short: 2 to 8 bars is perfect. The AI repeats it through the song.</li>
            <li>After you record, you can fix any note below the piano.</li>
          </ul>
        </div>
      </aside>
    </section>
    """
  end

  @computer_keys %{
    60 => "A",
    61 => "W",
    62 => "S",
    63 => "E",
    64 => "D",
    65 => "F",
    66 => "T",
    67 => "G",
    68 => "Y",
    69 => "H",
    70 => "U",
    71 => "J",
    72 => "K",
    73 => "O",
    74 => "L",
    75 => "P",
    76 => ";"
  }

  defp piano_keys do
    for pitch <- 60..83, white?(pitch) do
      black = pitch + 1

      %{
        pitch: pitch,
        name: MelodyStudio.AI.note_name(pitch),
        computer: @computer_keys[pitch],
        black:
          if(black <= 83 and not white?(black),
            do: %{
              pitch: black,
              name: MelodyStudio.AI.note_name(black),
              computer: @computer_keys[black]
            }
          )
      }
    end
  end

  defp white?(pitch), do: rem(pitch, 12) in [0, 2, 4, 5, 7, 9, 11]

  ## Step 2: style

  attr :song, :map, required: true
  attr :ai?, :boolean, required: true
  attr :rhythm_source, :atom, default: nil
  attr :loading?, :boolean, default: false
  attr :genre_query, :string, default: ""
  attr :custom_genre_error, :string, default: nil

  def style_step(assigns) do
    genres = Catalog.search_genres(assigns.genre_query)
    assigns = assign(assigns, groups: Catalog.genre_groups(genres), no_match?: genres == [])

    ~H"""
    <section class="space-y-4">
      <div class="rounded-box bg-base-100 p-5 shadow-sm">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 class="font-display text-xl font-bold">What style is your song?</h2>
            <p class="text-base-content/70">
              Pick one from the list, or type any style you like. You can change it later.
            </p>
          </div>
          <form
            id="genre-search"
            phx-change="search_genres"
            phx-submit="search_genres"
            class="w-full sm:w-64"
          >
            <label class="input w-full rounded-full">
              <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
              <input
                type="search"
                name="query"
                value={@genre_query}
                placeholder="Search styles"
                aria-label="Search styles"
                autocomplete="off"
                phx-debounce="200"
              />
            </label>
          </form>
        </div>

        <div
          :if={Catalog.custom_genre?(@song.genre)}
          id="custom-genre-chosen"
          class="mt-4 flex items-center gap-3 rounded-box border-2 border-primary bg-primary/10 p-4"
        >
          <span class="text-3xl">✨</span>
          <div>
            <div class="text-sm text-base-content/70">Your own style</div>
            <div class="font-display text-lg font-bold">{@song.genre}</div>
          </div>
        </div>

        <div id="genres" class="mt-4 space-y-5">
          <div :for={{group, genres} <- @groups}>
            <h3 class="mb-2 text-sm font-bold uppercase tracking-wide text-base-content/60">
              {group}
            </h3>
            <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-4">
              <button
                :for={genre <- genres}
                id={"genre-#{genre.id}"}
                type="button"
                phx-click="choose_genre"
                phx-value-genre={genre.id}
                aria-pressed={to_string(@song.genre == genre.id)}
                class={[
                  "rounded-box border-2 p-3 text-left transition sm:p-4",
                  @song.genre == genre.id && "border-primary bg-primary/10",
                  @song.genre != genre.id && "border-base-200 hover:border-primary/40"
                ]}
              >
                <div class="text-2xl sm:text-3xl">{genre.emoji}</div>
                <div class="font-display font-bold sm:text-lg">{genre.name}</div>
                <div class="hidden text-sm text-base-content/70 sm:block">{genre.blurb}</div>
              </button>
            </div>
          </div>
          <p :if={@no_match?} id="genres-empty" class="text-base-content/70">
            No style in our list matches "{@genre_query}". You can still use it: type it below.
          </p>
        </div>

        <.form
          for={%{}}
          as={:custom}
          id="custom-genre-form"
          phx-submit="custom_genre"
          class="mt-5 rounded-box bg-base-200/60 p-4"
        >
          <label for="custom-genre-input" class="mb-2 block font-semibold">
            Don't see your style? Type it here.
          </label>
          <div class="flex flex-col gap-2 sm:flex-row">
            <input
              id="custom-genre-input"
              type="text"
              name="genre"
              value={if Catalog.custom_genre?(@song.genre), do: @song.genre, else: @genre_query}
              maxlength={Catalog.max_custom_genre()}
              placeholder="For example vaporwave, sea shanty or 90s eurodance"
              class={["input w-full rounded-full", @custom_genre_error && "input-error"]}
              autocomplete="off"
            />
            <button class="btn btn-primary rounded-full">Use this style</button>
          </div>
          <p :if={@custom_genre_error} class="mt-2 text-sm text-error">{@custom_genre_error}</p>
          <p class="mt-2 text-sm text-base-content/60">
            The AI writes the chords and records the band in the style you type.
          </p>
        </.form>
      </div>

      <div class="rounded-box bg-base-100 p-5 shadow-sm">
        <h2 class="font-display text-xl font-bold">Who plays in your band?</h2>
        <p class="mb-4 text-base-content/70">Choose the instruments that join your melody.</p>
        <div id="instruments" class="flex flex-wrap gap-2">
          <button
            :for={instrument <- Catalog.instruments()}
            id={"instrument-#{instrument.id}"}
            type="button"
            phx-click="toggle_instrument"
            phx-value-instrument={instrument.id}
            aria-pressed={to_string(instrument.id in @song.instruments)}
            class={[
              "btn btn-lg rounded-full",
              instrument.id in @song.instruments && "btn-primary",
              instrument.id not in @song.instruments && "btn-outline border-base-300"
            ]}
          >
            <span class="text-xl">{instrument.emoji}</span> {instrument.name}
            <.icon :if={instrument.id in @song.instruments} name="hero-check" class="size-5" />
          </button>
        </div>
      </div>

      <div class="rounded-box bg-base-100 p-5 shadow-sm">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="font-display text-xl font-bold">Choose a rhythm</h2>
            <p class="text-base-content/70">
              Get drum patterns that fit your style and speed, listen, and pick one.
            </p>
          </div>
          <button
            id="suggest-rhythms"
            type="button"
            phx-click="suggest_rhythms"
            class="btn btn-secondary rounded-full"
            disabled={is_nil(@song.genre) or @loading?}
          >
            <span :if={@loading?} class="loading loading-spinner loading-sm"></span>
            <.icon :if={!@loading?} name="hero-sparkles" class="size-5" />
            {if @song.rhythm_ideas == [], do: "Get rhythm ideas", else: "Get new ideas"}
          </button>
        </div>

        <p :if={is_nil(@song.genre)} class="mt-3 text-sm text-base-content/60">
          Choose a style above first.
        </p>
        <p :if={@rhythm_source == :builtin} class="mt-3 text-sm text-base-content/60">
          {if @ai?,
            do: "The AI did not answer, so here are some of our favorite rhythms for this style.",
            else:
              "AI ideas are not set up on this server, so here are some of our favorite rhythms for this style."}
        </p>

        <div id="rhythm-ideas" class="mt-4 grid gap-3 md:grid-cols-3">
          <div
            :for={{rhythm, index} <- Enum.with_index(@song.rhythm_ideas)}
            id={"rhythm-#{index}"}
            class={[
              "flex flex-col gap-3 rounded-box border-2 p-4",
              @song.rhythm == rhythm && "border-primary bg-primary/10",
              @song.rhythm != rhythm && "border-base-200"
            ]}
          >
            <div>
              <div class="font-display text-lg font-bold">{rhythm["name"]}</div>
              <div class="text-sm text-base-content/70">{rhythm["description"]}</div>
            </div>
            <.step_grid steps={rhythm["steps"]} />
            <div class="mt-auto flex gap-2">
              <button
                type="button"
                class="btn btn-sm btn-ghost rounded-full"
                phx-click={
                  JS.dispatch("ms:preview-rhythm",
                    detail: %{steps: rhythm["steps"], feel: rhythm["feel"], tempo: @song.tempo}
                  )
                }
              >
                <.icon name="hero-play-solid" class="size-4" /> Listen
              </button>
              <button
                type="button"
                class={[
                  "btn btn-sm rounded-full",
                  @song.rhythm == rhythm && "btn-primary",
                  @song.rhythm != rhythm && "btn-outline"
                ]}
                phx-click="choose_rhythm"
                phx-value-index={index}
              >
                {if @song.rhythm == rhythm, do: "Chosen", else: "Use this one"}
              </button>
            </div>
          </div>
        </div>
      </div>

      <div class="flex justify-end">
        <.link patch={~p"/songs/#{@song}?step=build"} class="btn btn-primary btn-lg rounded-full">
          Next: build the song <.icon name="hero-arrow-right" class="size-5" />
        </.link>
      </div>
    </section>
    """
  end

  attr :steps, :map, required: true

  defp step_grid(assigns) do
    ~H"""
    <div class="space-y-1" aria-hidden="true">
      <div
        :for={
          {row, color} <- [{"hihat", "bg-accent"}, {"snare", "bg-secondary"}, {"kick", "bg-primary"}]
        }
        class="grid grid-cols-16 gap-0.5"
      >
        <span
          :for={{hit, i} <- Enum.with_index(@steps[row] || [])}
          class={[
            "h-2.5 rounded-sm",
            hit == 1 && color,
            hit != 1 && rem(i, 4) == 0 && "bg-base-300",
            hit != 1 && rem(i, 4) != 0 && "bg-base-200"
          ]}
        />
      </div>
    </div>
    """
  end

  ## Step 3: build

  attr :song, :map, required: true
  attr :ai?, :boolean, required: true
  attr :stems?, :boolean, required: true
  attr :uploads, :map, required: true

  def build_step(assigns) do
    song = assigns.song

    checks = [
      {"A recorded melody", Studio.melody_notes(song) != [], "melody"},
      {"A style", song.genre != nil, "style"},
      {"At least one instrument", song.instruments != [], "style"},
      {"A rhythm (optional)", song.rhythm != nil, "style"}
    ]

    ready? = Enum.take(checks, 3) |> Enum.all?(fn {_, ok, _} -> ok end)
    busy? = song.status in ["arranging", "generating"]

    assigns = assign(assigns, checks: checks, ready?: ready?, busy?: busy?)

    ~H"""
    <section class="space-y-4">
      <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <div class="min-w-0 rounded-box bg-base-100 p-5 shadow-sm">
          <h2 class="font-display text-xl font-bold">Let the AI build your song</h2>
          <p class="text-base-content/70">
            The AI writes chords that fit your melody, plans the parts of the song, and records
            each instrument.
          </p>

          <ul class="my-4 space-y-2">
            <li :for={{label, ok, step} <- @checks} class="flex items-center gap-3">
              <span class={[
                "grid size-7 place-items-center rounded-full",
                ok && "bg-success text-success-content",
                !ok && "bg-base-200"
              ]}>
                <.icon name={if ok, do: "hero-check", else: "hero-minus"} class="size-4" />
              </span>
              <span>{label}</span>
              <.link
                :if={!ok}
                patch={~p"/songs/#{@song}?step=#{step}"}
                class="link link-primary text-sm"
              >
                Add it
              </.link>
            </li>
          </ul>

          <form id="melody-audio-form" phx-change="validate_upload" class="hidden">
            <.live_file_input upload={@uploads.melody_audio} />
          </form>

          <button
            id="build-song"
            type="button"
            phx-hook="BuildSong"
            data-notes={Jason.encode!(Studio.melody_notes(@song))}
            data-tempo={@song.tempo}
            class="btn btn-primary btn-lg w-full rounded-full sm:w-auto"
            disabled={!@ready? or @busy?}
          >
            <span :if={@busy?} class="loading loading-spinner"></span>
            <.icon :if={!@busy?} name="hero-sparkles" class="size-6" />
            {cond do
              @busy? -> "Building your song..."
              @song.arrangement -> "Build it again"
              true -> "Build my song"
            end}
          </button>
          <p :if={@song.arrangement && !@busy?} class="mt-2 text-sm text-base-content/60">
            Building again makes a new plan and new tracks. Your current tracks are replaced.
          </p>
        </div>

        <aside class="space-y-3 rounded-box bg-base-100 p-5 text-sm shadow-sm">
          <h3 class="font-display text-lg font-bold">What the AI uses</h3>
          <p class="text-base-content/75">
            {if @ai?,
              do: "Claude plans the chords, the parts of the song and how each instrument plays.",
              else:
                "AI planning is not set up on this server, so the app uses a simple built-in plan."}
          </p>
          <p class="text-base-content/75">
            {if @stems?,
              do:
                "An AI music model records each instrument, guided by your melody. This can take a few minutes.",
              else:
                "AI audio is not set up on this server, so each instrument plays with a built-in sound. You can still hear, mix and download the whole song."}
          </p>
        </aside>
      </div>

      <div
        :if={@song.status == "failed"}
        id="build-error"
        class="alert alert-error rounded-box"
        role="alert"
      >
        <.icon name="hero-exclamation-triangle" class="size-6" />
        <span>{@song.error || "Something went wrong while building your song. Please try again."}</span>
      </div>

      <div
        :if={@song.status == "arranging"}
        id="build-progress"
        class="rounded-box bg-base-100 p-6 text-center shadow-sm"
      >
        <span class="loading loading-dots loading-lg text-primary"></span>
        <p class="font-semibold">The AI is listening to your melody and planning the song...</p>
      </div>

      <.arrangement
        :if={@song.arrangement && @song.status != "arranging"}
        song={@song}
        stems?={@stems?}
      />
    </section>
    """
  end

  attr :song, :map, required: true
  attr :stems?, :boolean, required: true

  defp arrangement(assigns) do
    ~H"""
    <div id="arrangement" class="space-y-4">
      <div class="rounded-box bg-base-100 p-5 shadow-sm">
        <h3 class="font-display text-lg font-bold">The plan</h3>
        <p :if={@song.arrangement["summary"] != ""} class="text-base-content/75">
          {@song.arrangement["summary"]}
        </p>
        <div class="mt-3 flex gap-2 overflow-x-auto pb-2">
          <div
            :for={section <- @song.arrangement["sections"]}
            class={[
              "min-w-36 shrink-0 rounded-2xl p-3",
              section["energy"] == "high" && "bg-primary/15",
              section["energy"] == "medium" && "bg-secondary/15",
              section["energy"] == "low" && "bg-base-200"
            ]}
          >
            <div class="font-bold">{section["name"]}</div>
            <div class="text-xs text-base-content/60">
              {section["bars"]} bars{if section["melody"], do: " · with melody"}
            </div>
            <div class="mt-1 font-mono text-sm">{Enum.join(section["chords"], "  ")}</div>
          </div>
        </div>
      </div>

      <div class="rounded-box bg-base-100 p-5 shadow-sm">
        <div class="mb-3 flex flex-wrap items-center justify-between gap-3">
          <h3 class="font-display text-lg font-bold">The band</h3>
          <form id="add-track-form" phx-submit="add_track" class="flex gap-2">
            <select
              name="instrument"
              class="select select-sm rounded-full"
              aria-label="Instrument to add"
            >
              <option :for={i <- Catalog.instruments()} value={i.id}>{i.emoji} {i.name}</option>
            </select>
            <button class="btn btn-sm btn-outline rounded-full">
              <.icon name="hero-plus" class="size-4" /> Add
            </button>
          </form>
        </div>
        <ul id="tracks" class="divide-y divide-base-200">
          <li
            :for={track <- @song.tracks}
            id={"track-#{track.id}"}
            class="flex flex-wrap items-center gap-3 py-3"
          >
            <span class="grid size-10 place-items-center rounded-2xl bg-base-200 text-xl">
              {Catalog.instrument_emoji(track.instrument)}
            </span>
            <div class="min-w-0 flex-1">
              <div class="font-semibold">{Catalog.instrument_name(track.instrument)}</div>
              <div class="truncate text-sm text-base-content/60">{track.error || track.role}</div>
            </div>
            <.track_status track={track} />
            <div :if={track.role != "melody"} class="flex gap-1">
              <button
                :if={@stems?}
                type="button"
                class="btn btn-ghost btn-sm rounded-full"
                phx-click="regenerate_track"
                phx-value-id={track.id}
                disabled={track.status in ["pending", "generating"]}
                title="Record this track again"
              >
                <.icon name="hero-arrow-path" class="size-4" />
                <span class="hidden sm:inline">Make again</span>
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm rounded-full text-error"
                phx-click="remove_track"
                phx-value-id={track.id}
                data-confirm="Remove this instrument from the song?"
                title="Remove this track"
              >
                <.icon name="hero-x-mark" class="size-4" />
                <span class="hidden sm:inline">Remove</span>
              </button>
            </div>
          </li>
        </ul>
        <div class="mt-4 flex justify-end">
          <.link patch={~p"/songs/#{@song}?step=mix"} class="btn btn-primary rounded-full">
            Listen and mix <.icon name="hero-arrow-right" class="size-5" />
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :track, :map, required: true

  defp track_status(assigns) do
    ~H"""
    <span class={[
      "badge rounded-full",
      @track.status == "ready" && "badge-success",
      @track.status == "sketch" && "badge-ghost",
      @track.status == "failed" && "badge-error",
      @track.status in ["pending", "generating"] && "badge-info"
    ]}>
      <span
        :if={@track.status in ["pending", "generating"]}
        class="loading loading-spinner loading-xs"
      ></span>
      {track_status_label(@track)}
    </span>
    """
  end

  defp track_status_label(%{role: "melody"}), do: "Your recording"
  defp track_status_label(%{status: "ready"}), do: "AI audio ready"
  defp track_status_label(%{status: "sketch"}), do: "Built-in sound"
  defp track_status_label(%{status: "failed"}), do: "Did not work"
  defp track_status_label(%{status: "generating"}), do: "Recording..."
  defp track_status_label(_), do: "Waiting"

  ## Step 4: mix and export

  attr :song, :map, required: true
  attr :loading?, :boolean, default: false
  attr :mix_source, :atom, default: nil

  def mix_step(assigns) do
    ~H"""
    <section
      :if={is_nil(@song.arrangement)}
      class="rounded-box bg-base-100 p-10 text-center shadow-sm"
    >
      <div class="text-5xl">🎚️</div>
      <h2 class="mt-3 font-display text-xl font-bold">Nothing to mix yet</h2>
      <p class="text-base-content/70">
        Build your song first. Then you can mix it and download it here.
      </p>
      <.link patch={~p"/songs/#{@song}?step=build"} class="btn btn-primary mt-4 rounded-full">
        Go to Build
      </.link>
    </section>

    <section
      :if={@song.arrangement}
      id="song-player"
      phx-hook="SongPlayer"
      data-song={Jason.encode!(song_data(@song))}
      data-title={@song.title}
      class="space-y-4"
    >
      <div class="sticky top-[4.5rem] z-10 rounded-box bg-base-100 p-4 shadow-md">
        <div id="song-player-ui" phx-update="ignore" class="flex flex-wrap items-center gap-3">
          <button
            type="button"
            data-action="play"
            class="btn btn-primary btn-circle btn-lg"
            aria-label="Play"
          >
            <.icon name="hero-play-solid" class="size-6" />
          </button>
          <button type="button" data-action="stop" class="btn btn-circle btn-lg" aria-label="Stop">
            <.icon name="hero-stop-solid" class="size-6" />
          </button>
          <div class="min-w-40 flex-1">
            <div class="flex justify-between text-sm font-semibold">
              <span data-role="section">Press play to listen</span>
              <span data-role="time">0:00</span>
            </div>
            <progress
              data-role="progress"
              class="progress progress-primary w-full"
              value="0"
              max="100"
            ></progress>
          </div>
          <button type="button" data-action="export" class="btn btn-secondary rounded-full">
            <.icon name="hero-arrow-down-tray" class="size-5" />
            <span data-role="export-label">Download WAV</span>
          </button>
        </div>
      </div>

      <div class="rounded-box bg-base-100 p-5 shadow-sm">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="font-display text-xl font-bold">Mix your song</h2>
            <p class="text-base-content/70">
              Move the sliders while the song plays to hear the change.
            </p>
          </div>
          <button
            id="suggest-mix"
            type="button"
            phx-click="suggest_mix"
            class="btn btn-secondary rounded-full"
            disabled={@loading?}
          >
            <span :if={@loading?} class="loading loading-spinner loading-sm"></span>
            <.icon :if={!@loading?} name="hero-sparkles" class="size-5" /> AI mix
          </button>
        </div>

        <div
          :if={@song.mix_suggestion}
          id="mix-suggestion"
          class="mt-4 rounded-box border-2 border-secondary/40 bg-secondary/10 p-4"
        >
          <p class="font-semibold">
            {if @mix_source == :builtin,
              do: "A balanced starting mix",
              else: "The AI suggests a new mix"}
          </p>
          <p class="text-base-content/75">{@song.mix_suggestion["summary"]}</p>
          <div class="mt-3 flex gap-2">
            <button
              type="button"
              class="btn btn-secondary btn-sm rounded-full"
              phx-click="apply_mix_suggestion"
            >
              Use these settings
            </button>
            <button
              type="button"
              class="btn btn-ghost btn-sm rounded-full"
              phx-click="dismiss_mix_suggestion"
            >
              Keep my mix
            </button>
          </div>
        </div>
      </div>

      <div id="mixer" class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <.mixer_strip :for={track <- @song.tracks} track={track} />
      </div>
    </section>
    """
  end

  attr :track, :map, required: true

  defp mixer_strip(assigns) do
    ~H"""
    <div id={"mixer-#{@track.id}"} class="rounded-box bg-base-100 p-5 shadow-sm">
      <div class="mb-3 flex items-center gap-3">
        <span class="grid size-10 place-items-center rounded-2xl bg-base-200 text-xl">
          {Catalog.instrument_emoji(@track.instrument)}
        </span>
        <div class="flex-1 font-display text-lg font-bold">
          {Catalog.instrument_name(@track.instrument)}
        </div>
        <button
          type="button"
          phx-click="toggle_mix"
          phx-value-id={@track.id}
          phx-value-field="mute"
          aria-pressed={to_string(@track.mix["mute"])}
          class={["btn btn-sm btn-circle", @track.mix["mute"] && "btn-error"]}
          title="Mute: turn this track off"
        >
          M
        </button>
        <button
          type="button"
          phx-click="toggle_mix"
          phx-value-id={@track.id}
          phx-value-field="solo"
          aria-pressed={to_string(@track.mix["solo"])}
          class={["btn btn-sm btn-circle", @track.mix["solo"] && "btn-accent"]}
          title="Solo: hear only this track"
        >
          S
        </button>
      </div>
      <form id={"mix-form-#{@track.id}"} phx-change="update_mix" class="space-y-2">
        <input type="hidden" name="track_id" value={@track.id} />
        <.slider track={@track} field="volume" label="Loudness" min={0} max={100} />
        <.slider track={@track} field="pan" label="Left · Right" min={-100} max={100} />
        <.slider track={@track} field="reverb" label="Space (reverb)" min={0} max={100} />
        <.slider track={@track} field="delay" label="Echo" min={0} max={100} />
        <.slider track={@track} field="punch" label="Punch" min={0} max={100} />
        <div class="grid grid-cols-3 gap-3">
          <.slider track={@track} field="low" label="Bass" min={-12} max={12} />
          <.slider track={@track} field="mid" label="Middle" min={-12} max={12} />
          <.slider track={@track} field="high" label="Treble" min={-12} max={12} />
        </div>
      </form>
    </div>
    """
  end

  attr :track, :map, required: true
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :min, :integer, required: true
  attr :max, :integer, required: true

  defp slider(assigns) do
    ~H"""
    <label class="block">
      <span class="flex justify-between text-xs font-semibold text-base-content/70">
        <span>{@label}</span>
      </span>
      <input
        type="range"
        name={"mix[#{@field}]"}
        min={@min}
        max={@max}
        value={@track.mix[@field]}
        class="mix-slider"
        data-track-id={@track.id}
        data-param={@field}
        phx-debounce="250"
      />
    </label>
    """
  end

  @doc "The data the browser player needs to play and export the song."
  def song_data(song) do
    rhythm = song.rhythm || List.first(Catalog.preset_rhythms(song.genre || "pop"))

    %{
      tempo: song.tempo,
      family: Catalog.genre_family(song.genre),
      key: song.key,
      melody: Studio.melody_notes(song),
      melodyBars: Melody.bars(Studio.melody_notes(song)),
      rhythm: rhythm,
      sections: (song.arrangement || %{})["sections"] || [],
      tracks:
        Enum.map(song.tracks, fn track ->
          %{
            id: track.id,
            instrument: track.instrument,
            role: track.role,
            status: track.status,
            audioUrl: if(track.status == "ready", do: Storage.url(track.audio_path)),
            mix: track.mix
          }
        end)
    }
  end
end
