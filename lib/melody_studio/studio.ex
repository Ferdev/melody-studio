defmodule MelodyStudio.Studio do
  @moduledoc """
  Songs and everything in them: the melody, the style choices, the
  arrangement plan, the tracks and their mix.
  """

  import Ecto.Query, warn: false

  alias MelodyStudio.Repo
  alias MelodyStudio.Accounts.Scope
  alias MelodyStudio.Storage
  alias MelodyStudio.Studio.{Melody, Song, Track}
  alias MelodyStudio.Workers.{ArrangeSong, GenerateStem}

  ## PubSub

  @doc "Subscribes the caller to changes of a song."
  def subscribe(song_id), do: Phoenix.PubSub.subscribe(MelodyStudio.PubSub, topic(song_id))

  @doc "Tells subscribers that a song changed."
  def broadcast(song_id) do
    Phoenix.PubSub.broadcast(MelodyStudio.PubSub, topic(song_id), {:song_updated, song_id})
  end

  defp topic(song_id), do: "song:#{song_id}"

  ## Songs

  def list_songs(%Scope{user: user}) do
    Song
    |> where(user_id: ^user.id)
    |> order_by(desc: :updated_at, desc: :id)
    |> Repo.all()
  end

  def get_song!(%Scope{user: user}, id) do
    Song
    |> where(user_id: ^user.id, id: ^id)
    |> Repo.one!()
    |> Repo.preload([:melody, :tracks])
  end

  @doc false
  def get_song_for_job(id) do
    case Repo.get(Song, id) do
      nil -> nil
      song -> Repo.preload(song, [:melody, :tracks])
    end
  end

  def change_song_title(song, attrs \\ %{}), do: Song.title_changeset(song, attrs)

  def create_song(%Scope{user: user}, attrs) do
    %Song{user_id: user.id}
    |> Song.title_changeset(attrs)
    |> Repo.insert()
  end

  def rename_song(%Scope{} = scope, %Song{} = song, attrs) do
    authorize!(scope, song)
    song |> Song.title_changeset(attrs) |> Repo.update()
  end

  def delete_song(%Scope{} = scope, %Song{} = song) do
    authorize!(scope, song)
    song = Repo.preload(song, [:melody, :tracks], force: true)

    with {:ok, song} <- Repo.delete(song) do
      Enum.each(song.tracks, &Storage.delete(&1.audio_path))
      if song.melody, do: Storage.delete(song.melody.audio_path)
      {:ok, song}
    end
  end

  def change_song_settings(song, attrs \\ %{}), do: Song.settings_changeset(song, attrs)

  def update_song_settings(%Scope{} = scope, %Song{} = song, attrs) do
    authorize!(scope, song)
    song |> Song.settings_changeset(attrs) |> Repo.update() |> notify()
  end

  ## Melody

  def save_melody(%Scope{} = scope, %Song{} = song, notes) do
    authorize!(scope, song)
    melody = Repo.get_by(Melody, song_id: song.id) || %Melody{song_id: song.id}

    melody
    |> Melody.changeset(%{notes: Melody.normalize_notes(notes)})
    |> Repo.insert_or_update()
    |> tap(fn _ -> touch(song) end)
  end

  @doc "Stores the melody as audio (rendered in the browser) to guide the AI music model."
  def save_melody_audio(%Scope{} = scope, %Song{} = song, binary) do
    authorize!(scope, song)
    melody = Repo.get_by!(Melody, song_id: song.id)
    path = Storage.song_path(song.id, "melody")

    with :ok <- Storage.put(path, binary, "audio/wav"),
         {:ok, updated} <- melody |> Melody.changeset(%{audio_path: path}) |> Repo.update() do
      Storage.delete(melody.audio_path)
      {:ok, updated}
    end
  end

  def melody_notes(%Song{melody: %Melody{notes: notes}}), do: notes
  def melody_notes(_), do: []

  ## Style

  def change_song_style(song, attrs \\ %{}), do: Song.style_changeset(song, attrs)

  def update_song_style(%Scope{} = scope, %Song{} = song, attrs) do
    authorize!(scope, song)
    changeset = Song.style_changeset(song, attrs)

    changeset =
      if Ecto.Changeset.changed?(changeset, :genre),
        do: Ecto.Changeset.change(changeset, rhythm_ideas: [], rhythm: nil),
        else: changeset

    changeset |> Repo.update() |> notify()
  end

  def toggle_instrument(%Scope{} = scope, %Song{} = song, instrument) do
    instruments =
      if instrument in song.instruments,
        do: List.delete(song.instruments, instrument),
        else: song.instruments ++ [instrument]

    update_song_style(scope, song, %{instruments: instruments})
  end

  def put_rhythm_ideas(%Scope{} = scope, %Song{} = song, ideas) do
    authorize!(scope, song)
    song |> Song.system_changeset(%{rhythm_ideas: ideas}) |> Repo.update() |> notify()
  end

  def choose_rhythm(%Scope{} = scope, %Song{} = song, index) when is_integer(index) do
    authorize!(scope, song)

    case Enum.at(song.rhythm_ideas, index) do
      nil -> {:error, :not_found}
      rhythm -> song |> Song.system_changeset(%{rhythm: rhythm}) |> Repo.update() |> notify()
    end
  end

  ## Building the song

  @doc """
  Checks that the song has what the AI needs and starts the build in the
  background. Returns `{:error, message}` when something is missing.
  """
  def build_song(%Scope{} = scope, %Song{} = song) do
    authorize!(scope, song)

    cond do
      melody_notes(song) == [] ->
        {:error, "Record a melody first. It is the heart of your song."}

      is_nil(song.genre) ->
        {:error, "Choose a style for your song first."}

      song.instruments == [] ->
        {:error, "Choose at least one instrument for the band."}

      song.status in ["arranging", "generating"] ->
        {:error, "Your song is already being built. Please wait until it is ready."}

      true ->
        Repo.transact(fn ->
          with {:ok, song} <-
                 song
                 |> Song.system_changeset(%{status: "arranging", error: nil, mix_suggestion: nil})
                 |> Repo.update(),
               {:ok, _job} <- %{song_id: song.id} |> ArrangeSong.new() |> Oban.insert() do
            {:ok, song}
          end
        end)
        |> notify()
    end
  end

  @doc """
  Saves the arrangement plan and replaces the tracks of the song. Used by the
  background job.
  """
  def apply_arrangement(%Song{} = song, plan) do
    song = Repo.preload(song, :tracks, force: true)
    old_tracks = song.tracks
    stems? = MelodyStudio.Stems.configured?()

    result =
      Repo.transact(fn ->
        Enum.each(old_tracks, &Repo.delete!/1)

        melody_track =
          insert_track!(song, %{
            instrument: "melody",
            role: "melody",
            prompt: nil,
            status: "ready",
            position: 0
          })

        tracks =
          plan["tracks"]
          |> Enum.with_index(1)
          |> Enum.map(fn {track, position} ->
            insert_track!(song, %{
              instrument: track["instrument"],
              role: track["role"],
              prompt: track["prompt"],
              status: if(stems?, do: "pending", else: "sketch"),
              position: position
            })
          end)

        if stems?, do: Enum.each(tracks, &enqueue_stem!/1)

        song
        |> Song.system_changeset(%{
          arrangement: plan,
          status: if(stems? and tracks != [], do: "generating", else: "ready")
        })
        |> Repo.update()
        |> case do
          {:ok, song} -> {:ok, {song, [melody_track | tracks]}}
          error -> error
        end
      end)

    case result do
      {:ok, {song, _tracks}} ->
        Enum.each(old_tracks, &Storage.delete(&1.audio_path))
        broadcast(song.id)
        {:ok, song}

      error ->
        error
    end
  end

  def mark_build_failed(song_id, message) do
    with %Song{} = song <- Repo.get(Song, song_id) do
      song
      |> Song.system_changeset(%{status: "failed", error: message})
      |> Repo.update()
      |> notify()
    end
  end

  defp insert_track!(song, attrs) do
    %Track{song_id: song.id}
    |> Track.changeset(Map.put(attrs, :mix, Track.mix_defaults()))
    |> Repo.insert!()
  end

  defp enqueue_stem!(track) do
    %{track_id: track.id} |> GenerateStem.new() |> Oban.insert!()
  end

  ## Tracks

  def get_track!(%Song{} = song, track_id) do
    Repo.get_by!(Track, id: track_id, song_id: song.id)
  end

  @doc false
  def get_track_for_job(id) do
    case Repo.get(Track, id) do
      nil -> nil
      track -> Repo.preload(track, song: :melody)
    end
  end

  def add_track(%Scope{} = scope, %Song{} = song, instrument) do
    authorize!(scope, song)

    cond do
      is_nil(song.arrangement) ->
        {:error, "Build your song first, then you can add more instruments."}

      instrument not in MelodyStudio.Studio.Catalog.instrument_ids() ->
        {:error, "Please choose an instrument from the list."}

      true ->
        stems? = MelodyStudio.Stems.configured?()
        position = (song.tracks |> Enum.map(& &1.position) |> Enum.max(fn -> 0 end)) + 1

        prompt =
          MelodyStudio.AI.default_prompt(song, instrument, song.arrangement["sections"] || [])

        Repo.transact(fn ->
          track =
            insert_track!(song, %{
              instrument: instrument,
              role: MelodyStudio.Studio.Catalog.default_role(instrument),
              prompt: prompt,
              status: if(stems?, do: "pending", else: "sketch"),
              position: position
            })

          if stems?, do: enqueue_stem!(track)
          {:ok, track}
        end)
        |> tap(fn _ -> refresh_song_status(song.id) end)
    end
  end

  def remove_track(%Scope{} = scope, %Song{} = song, track_id) do
    authorize!(scope, song)
    track = get_track!(song, track_id)

    if Track.melody?(track) do
      {:error, "Your melody is the heart of the song, so it cannot be removed."}
    else
      with {:ok, track} <- Repo.delete(track) do
        Storage.delete(track.audio_path)
        refresh_song_status(song.id)
        {:ok, track}
      end
    end
  end

  def regenerate_track(%Scope{} = scope, %Song{} = song, track_id) do
    authorize!(scope, song)
    track = get_track!(song, track_id)

    cond do
      Track.melody?(track) ->
        {:error, "Your melody is played from your recording, so there is nothing to make again."}

      Track.busy?(track) ->
        {:error, "This track is still being made."}

      not MelodyStudio.Stems.configured?() ->
        {:error, "AI audio is not set up on this server, so tracks use built-in sounds."}

      true ->
        Repo.transact(fn ->
          with {:ok, track} <-
                 track
                 |> Track.changeset(%{status: "pending", error: nil, prediction_id: nil})
                 |> Repo.update() do
            enqueue_stem!(track)
            {:ok, track}
          end
        end)
        |> tap(fn _ -> refresh_song_status(song.id) end)
    end
  end

  @doc "Updates a track from a background job and tells the song page."
  def update_track_from_job(%Track{} = track, attrs) do
    with {:ok, track} <- track |> Track.changeset(attrs) |> Repo.update() do
      refresh_song_status(track.song_id)
      {:ok, track}
    end
  end

  def update_track_mix(%Scope{} = scope, %Song{} = song, track_id, mix) do
    authorize!(scope, song)
    track = get_track!(song, track_id)

    track
    |> Track.changeset(%{mix: Map.merge(track.mix, mix)})
    |> Repo.update()
    |> tap(fn _ -> touch(song) end)
  end

  ## Mix suggestions

  def put_mix_suggestion(%Scope{} = scope, %Song{} = song, suggestion) do
    authorize!(scope, song)
    song |> Song.system_changeset(%{mix_suggestion: suggestion}) |> Repo.update() |> notify()
  end

  def apply_mix_suggestion(%Scope{} = scope, %Song{mix_suggestion: %{"tracks" => mixes}} = song) do
    authorize!(scope, song)

    Repo.transact(fn ->
      Enum.each(song.tracks, fn track ->
        case Map.get(mixes, to_string(track.id)) do
          nil -> :ok
          mix -> track |> Track.changeset(%{mix: mix}) |> Repo.update!()
        end
      end)

      song |> Song.system_changeset(%{mix_suggestion: nil}) |> Repo.update()
    end)
    |> notify()
  end

  def apply_mix_suggestion(_scope, song), do: {:ok, song}

  ## Helpers

  @doc "Length of the whole song in seconds."
  def song_seconds(%Song{arrangement: %{"sections" => sections}, tempo: tempo}) do
    bars = sections |> Enum.map(& &1["bars"]) |> Enum.sum()
    bars * 4 * 60 / tempo
  end

  def song_seconds(%Song{}), do: 0

  @doc "Recomputes the song status from the state of its tracks."
  def refresh_song_status(song_id) do
    song = Repo.get(Song, song_id) |> Repo.preload(:tracks)

    if song && song.status not in ["arranging", "draft"] do
      status = if Enum.any?(song.tracks, &Track.busy?/1), do: "generating", else: "ready"
      song |> Song.system_changeset(%{status: status}) |> Repo.update!()
    end

    broadcast(song_id)
  end

  defp touch(song) do
    from(s in Song, where: s.id == ^song.id)
    |> Repo.update_all(set: [updated_at: DateTime.utc_now(:second)])
  end

  defp notify({:ok, %Song{} = song} = result) do
    broadcast(song.id)
    result
  end

  defp notify(result), do: result

  defp authorize!(%Scope{user: %{id: user_id}}, %Song{user_id: user_id}), do: :ok

  defp authorize!(_scope, _song) do
    raise Ecto.NoResultsError, queryable: Song
  end
end
