defmodule MelodyStudioWeb.SongLive.Show do
  use MelodyStudioWeb, :live_view

  import MelodyStudioWeb.SongLive.StudioComponents

  alias MelodyStudio.{AI, Stems, Studio}
  alias MelodyStudio.Studio.Catalog

  @steps ~w(melody style build mix)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="min-w-0">
          <.link navigate={~p"/songs"} class="text-sm text-base-content/60 hover:text-primary">
            <.icon name="hero-arrow-left" class="size-4" /> My songs
          </.link>
          <h1 class="truncate font-display text-3xl font-extrabold" id="song-title">{@song.title}</h1>
          <p class="text-sm text-base-content/60">
            {Catalog.genre_name(@song.genre)} · {@song.tempo} BPM · {@song.key}
          </p>
        </div>
      </div>

      <.step_nav song={@song} step={@step} />

      <.melody_step :if={@step == "melody"} song={@song} settings_form={@settings_form} />
      <.style_step
        :if={@step == "style"}
        song={@song}
        ai?={@ai?}
        rhythm_source={@rhythm_source}
        loading?={@rhythm_loading?}
      />
      <.build_step
        :if={@step == "build"}
        song={@song}
        ai?={@ai?}
        stems?={@stems?}
        uploads={@uploads}
      />
      <.mix_step
        :if={@step == "mix"}
        song={@song}
        loading?={@mix_loading?}
        mix_source={@mix_source}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    song = Studio.get_song!(socket.assigns.current_scope, id)
    if connected?(socket), do: Studio.subscribe(song.id)

    {:ok,
     socket
     |> assign(:page_title, song.title)
     |> assign(:ai?, AI.configured?())
     |> assign(:stems?, Stems.configured?())
     |> assign(:rhythm_loading?, false)
     |> assign(:rhythm_source, nil)
     |> assign(:mix_loading?, false)
     |> assign(:mix_source, nil)
     |> assign_song(song)
     |> allow_upload(:melody_audio,
       accept: ~w(.wav),
       max_entries: 1,
       max_file_size: 40_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    step =
      if params["step"] in @steps, do: params["step"], else: default_step(socket.assigns.song)

    {:noreply, assign(socket, :step, step)}
  end

  defp default_step(song) do
    cond do
      song.arrangement -> "mix"
      Studio.melody_notes(song) == [] -> "melody"
      is_nil(song.genre) or song.instruments == [] -> "style"
      true -> "build"
    end
  end

  defp assign_song(socket, song) do
    socket
    |> assign(:song, song)
    |> assign(:settings_form, to_form(Studio.change_song_settings(song)))
  end

  defp reload(socket) do
    assign_song(socket, Studio.get_song!(socket.assigns.current_scope, socket.assigns.song.id))
  end

  defp scope(socket), do: socket.assigns.current_scope

  ## Melody

  @impl true
  def handle_event("update_settings", %{"song" => params}, socket) do
    case Studio.update_song_settings(scope(socket), socket.assigns.song, params) do
      {:ok, _song} -> {:noreply, reload(socket)}
      {:error, changeset} -> {:noreply, assign(socket, :settings_form, to_form(changeset))}
    end
  end

  def handle_event("save_melody", %{"notes" => notes}, socket) when is_list(notes) do
    case Studio.save_melody(scope(socket), socket.assigns.song, notes) do
      {:ok, _melody} ->
        {:noreply, reload(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "We could not save your melody. Please try again.")}
    end
  end

  ## Style

  def handle_event("choose_genre", %{"genre" => genre}, socket) do
    case Studio.update_song_style(scope(socket), socket.assigns.song, %{genre: genre}) do
      {:ok, _} -> {:noreply, socket |> assign(:rhythm_source, nil) |> reload()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Please choose a style from the list.")}
    end
  end

  def handle_event("toggle_instrument", %{"instrument" => instrument}, socket) do
    case Studio.toggle_instrument(scope(socket), socket.assigns.song, instrument) do
      {:ok, _} ->
        {:noreply, reload(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Please choose an instrument from the list.")}
    end
  end

  def handle_event("suggest_rhythms", _params, socket) do
    song = socket.assigns.song

    if song.genre do
      {:noreply,
       socket
       |> assign(:rhythm_loading?, true)
       |> start_async(:rhythm_ideas, fn -> AI.rhythm_ideas(song) end)}
    else
      {:noreply, put_flash(socket, :error, "Choose a style first, then ask for rhythm ideas.")}
    end
  end

  def handle_event("choose_rhythm", %{"index" => index}, socket) do
    with {index, ""} <- Integer.parse(index),
         {:ok, _} <- Studio.choose_rhythm(scope(socket), socket.assigns.song, index) do
      {:noreply, reload(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "That rhythm is no longer available.")}
    end
  end

  ## Build

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("build_song", _params, socket) do
    {:noreply, build(socket)}
  end

  def handle_event("add_track", %{"instrument" => instrument}, socket) do
    case Studio.add_track(scope(socket), socket.assigns.song, instrument) do
      {:ok, _track} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{Catalog.instrument_name(instrument)} joined the band.")
         |> reload()}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "We could not add that instrument. Please try again.")}
    end
  end

  def handle_event("remove_track", %{"id" => id}, socket) do
    case Studio.remove_track(scope(socket), socket.assigns.song, id) do
      {:ok, track} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{Catalog.instrument_name(track.instrument)} left the band.")
         |> reload()}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "We could not remove that track. Please try again.")}
    end
  end

  def handle_event("regenerate_track", %{"id" => id}, socket) do
    case Studio.regenerate_track(scope(socket), socket.assigns.song, id) do
      {:ok, _track} ->
        {:noreply,
         socket |> put_flash(:info, "The AI is recording this track again.") |> reload()}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "We could not start a new take. Please try again.")}
    end
  end

  ## Mix

  def handle_event("update_mix", %{"track_id" => id, "mix" => mix}, socket) do
    {:ok, _} = Studio.update_track_mix(scope(socket), socket.assigns.song, id, mix)
    {:noreply, reload(socket)}
  end

  def handle_event("toggle_mix", %{"id" => id, "field" => field}, socket)
      when field in ["mute", "solo"] do
    track = Studio.get_track!(socket.assigns.song, id)

    {:ok, _} =
      Studio.update_track_mix(scope(socket), socket.assigns.song, id, %{
        field => !track.mix[field]
      })

    {:noreply, reload(socket)}
  end

  def handle_event("suggest_mix", _params, socket) do
    song = socket.assigns.song

    {:noreply,
     socket
     |> assign(:mix_loading?, true)
     |> start_async(:mix_suggestion, fn -> AI.mix_suggestion(song, song.tracks) end)}
  end

  def handle_event("apply_mix_suggestion", _params, socket) do
    {:ok, _} = Studio.apply_mix_suggestion(scope(socket), socket.assigns.song)

    {:noreply,
     socket |> put_flash(:info, "The new mix is on. Adjust any slider you like.") |> reload()}
  end

  def handle_event("dismiss_mix_suggestion", _params, socket) do
    {:ok, _} = Studio.put_mix_suggestion(scope(socket), socket.assigns.song, nil)
    {:noreply, reload(socket)}
  end

  def handle_event("export_failed", %{"message" => message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  ## Async results

  @impl true
  def handle_async(:rhythm_ideas, {:ok, {:ok, ideas, source}}, socket) do
    {:ok, _} = Studio.put_rhythm_ideas(scope(socket), socket.assigns.song, ideas)

    {:noreply, socket |> assign(rhythm_loading?: false, rhythm_source: source) |> reload()}
  end

  def handle_async(:rhythm_ideas, _result, socket) do
    {:noreply,
     socket
     |> assign(:rhythm_loading?, false)
     |> put_flash(:error, "We could not get rhythm ideas. Please try again.")}
  end

  def handle_async(:mix_suggestion, {:ok, {:ok, suggestion, source}}, socket) do
    {:ok, _} = Studio.put_mix_suggestion(scope(socket), socket.assigns.song, suggestion)
    {:noreply, socket |> assign(mix_loading?: false, mix_source: source) |> reload()}
  end

  def handle_async(:mix_suggestion, _result, socket) do
    {:noreply,
     socket
     |> assign(:mix_loading?, false)
     |> put_flash(:error, "We could not get mix ideas. Please try again.")}
  end

  @impl true
  def handle_info({:song_updated, _id}, socket), do: {:noreply, reload(socket)}

  ## Upload of the rendered melody

  defp handle_progress(:melody_audio, entry, socket) do
    if entry.done? do
      binary =
        consume_uploaded_entry(socket, entry, fn %{path: path} -> {:ok, File.read!(path)} end)

      case Studio.save_melody_audio(scope(socket), socket.assigns.song, binary) do
        {:ok, _} -> {:noreply, build(socket)}
        {:error, _} -> {:noreply, build(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  defp build(socket) do
    case Studio.build_song(scope(socket), reload(socket).assigns.song) do
      {:ok, _song} ->
        reload(socket)

      {:error, message} when is_binary(message) ->
        put_flash(socket, :error, message)

      {:error, _} ->
        put_flash(socket, :error, "We could not start building your song. Please try again.")
    end
  end
end
