defmodule MelodyStudio.StudioTest do
  use MelodyStudio.DataCase, async: true
  use Oban.Testing, repo: MelodyStudio.Repo

  import MelodyStudio.AccountsFixtures
  import MelodyStudio.StudioFixtures

  alias MelodyStudio.Studio
  alias MelodyStudio.Studio.{Melody, Song, Track}
  alias MelodyStudio.Workers.ArrangeSong

  setup do
    %{scope: user_scope_fixture(), other: user_scope_fixture()}
  end

  describe "songs" do
    test "create, list, rename and delete", %{scope: scope} do
      assert {:ok, %Song{} = song} = Studio.create_song(scope, %{title: "  Sunny day  "})
      assert song.title == "Sunny day"
      assert [%Song{id: id}] = Studio.list_songs(scope)
      assert id == song.id

      assert {:ok, song} = Studio.rename_song(scope, song, %{title: "Rainy day"})
      assert song.title == "Rainy day"

      assert {:ok, _} = Studio.delete_song(scope, song)
      assert Studio.list_songs(scope) == []
    end

    test "requires a title", %{scope: scope} do
      assert {:error, changeset} = Studio.create_song(scope, %{title: ""})
      assert %{title: ["Please give your song a name"]} = errors_on(changeset)
    end

    test "people cannot see or change the songs of others", %{scope: scope, other: other} do
      song = song_fixture(scope)
      assert Studio.list_songs(other) == []
      assert_raise Ecto.NoResultsError, fn -> Studio.get_song!(other, song.id) end

      assert_raise Ecto.NoResultsError, fn ->
        Studio.rename_song(other, song, %{title: "Mine"})
      end

      assert_raise Ecto.NoResultsError, fn -> Studio.delete_song(other, song) end
    end

    test "validates tempo and key", %{scope: scope} do
      song = song_fixture(scope)
      assert {:ok, song} = Studio.update_song_settings(scope, song, %{tempo: 120, key: "A minor"})
      assert {song.tempo, song.key} == {120, "A minor"}

      assert {:error, changeset} =
               Studio.update_song_settings(scope, song, %{tempo: 400, key: "H"})

      assert errors_on(changeset)[:tempo]
      assert errors_on(changeset)[:key]
    end
  end

  describe "melody" do
    test "saves clean notes and drops invalid ones", %{scope: scope} do
      song = song_fixture(scope)

      notes = [
        %{"pitch" => 64, "start" => 1, "duration" => 0.5, "velocity" => 0.9},
        %{"pitch" => 60, "start" => 0.0, "duration" => 1, "velocity" => 2},
        %{"pitch" => 500, "start" => 0, "duration" => 1},
        %{"pitch" => 62, "start" => -1, "duration" => 1},
        %{"pitch" => 62, "start" => 1, "duration" => 0},
        "not a note"
      ]

      assert {:ok, %Melody{notes: saved}} = Studio.save_melody(scope, song, notes)

      assert saved == [
               %{"pitch" => 60, "start" => 0.0, "duration" => 1.0, "velocity" => 1.0},
               %{"pitch" => 64, "start" => 1.0, "duration" => 0.5, "velocity" => 0.9}
             ]

      # Saving again replaces the melody.
      assert {:ok, %Melody{notes: []}} = Studio.save_melody(scope, song, [])
      assert Studio.melody_notes(Studio.get_song!(scope, song.id)) == []
    end

    test "counts bars in steps of 1, 2, 4, 8 and 16" do
      assert Melody.bars([]) == 0
      assert Melody.bars([%{"start" => 0, "duration" => 3}]) == 1
      assert Melody.bars([%{"start" => 4, "duration" => 4}]) == 2
      assert Melody.bars([%{"start" => 8, "duration" => 1}]) == 4
      assert Melody.bars([%{"start" => 30, "duration" => 4}]) == 16
    end
  end

  describe "style" do
    test "changing the genre clears old rhythm ideas", %{scope: scope} do
      song = song_fixture(scope)
      {:ok, song} = Studio.update_song_style(scope, song, %{genre: "rock"})

      {:ok, song} =
        Studio.put_rhythm_ideas(scope, song, MelodyStudio.Studio.Catalog.preset_rhythms("rock"))

      {:ok, song} = Studio.choose_rhythm(scope, song, 1)
      assert song.rhythm["name"] == "Driving rock"

      {:ok, song} = Studio.update_song_style(scope, song, %{genre: "jazz"})
      assert song.rhythm_ideas == []
      assert song.rhythm == nil
    end

    test "accepts a typed style and only known instruments", %{scope: scope} do
      song = song_fixture(scope)

      assert {:ok, %{genre: "Sea shanty"}} =
               Studio.update_song_style(scope, song, %{genre: "  Sea   shanty "})

      # A typed name of a style in the list becomes that style.
      assert {:ok, %{genre: "future_funk"}} =
               Studio.update_song_style(scope, song, %{genre: "future FUNK"})

      assert {:error, changeset} = Studio.update_song_style(scope, song, %{genre: "x"})
      assert %{genre: ["Please type at least 2 characters"]} = errors_on(changeset)

      assert {:error, _} =
               Studio.update_song_style(scope, song, %{genre: String.duplicate("a", 41)})

      assert {:error, _} = Studio.update_song_style(scope, song, %{instruments: ["kazoo"]})
    end

    test "toggles instruments", %{scope: scope} do
      song = song_fixture(scope)
      {:ok, song} = Studio.toggle_instrument(scope, song, "drums")
      {:ok, song} = Studio.toggle_instrument(scope, song, "bass")
      assert song.instruments == ["drums", "bass"]
      {:ok, song} = Studio.toggle_instrument(scope, song, "drums")
      assert song.instruments == ["bass"]
    end
  end

  describe "build_song/2" do
    test "explains what is missing", %{scope: scope} do
      song = song_fixture(scope)
      assert {:error, "Record a melody first" <> _} = Studio.build_song(scope, song)

      {:ok, _} = Studio.save_melody(scope, song, melody_notes())
      song = Studio.get_song!(scope, song.id)
      assert {:error, "Choose a style" <> _} = Studio.build_song(scope, song)

      {:ok, song} = Studio.update_song_style(scope, song, %{genre: "pop"})
      song = Studio.get_song!(scope, song.id)
      assert {:error, "Choose at least one instrument" <> _} = Studio.build_song(scope, song)
    end

    test "starts the background job", %{scope: scope} do
      song = ready_song_fixture(scope)
      assert {:ok, %Song{status: "arranging"}} = Studio.build_song(scope, song)
      assert_enqueued(worker: ArrangeSong, args: %{song_id: song.id})

      song = Studio.get_song!(scope, song.id)
      assert {:error, "Your song is already being built" <> _} = Studio.build_song(scope, song)
    end

    test "without AI keys, the job makes a built-in plan and tracks with built-in sounds",
         %{scope: scope} do
      song = ready_song_fixture(scope)
      {:ok, _} = Studio.build_song(scope, song)
      Studio.subscribe(song.id)

      assert :ok = perform_job(ArrangeSong, %{song_id: song.id})
      assert_receive {:song_updated, _}

      song = Studio.get_song!(scope, song.id)
      assert song.status == "ready"
      assert [first | _] = song.arrangement["sections"]
      assert first["bars"] == 4
      assert length(first["chords"]) == 4

      assert Enum.map(song.tracks, &{&1.instrument, &1.status}) == [
               {"melody", "ready"},
               {"drums", "sketch"},
               {"bass", "sketch"},
               {"keys", "sketch"}
             ]

      assert Studio.song_seconds(song) == 6 * 4 * 4 * 60 / 100
    end
  end

  describe "tracks" do
    setup %{scope: scope} do
      song = ready_song_fixture(scope)
      {:ok, _} = Studio.build_song(scope, song)
      :ok = perform_job(ArrangeSong, %{song_id: song.id})
      %{song: Studio.get_song!(scope, song.id)}
    end

    test "adds and removes instruments", %{scope: scope, song: song} do
      assert {:ok, %Track{instrument: "strings", status: "sketch"} = track} =
               Studio.add_track(scope, song, "strings")

      assert track.prompt =~ "strings"
      song = Studio.get_song!(scope, song.id)
      assert length(song.tracks) == 5

      assert {:ok, _} = Studio.remove_track(scope, song, track.id)
      assert length(Studio.get_song!(scope, song.id).tracks) == 4
    end

    test "keeps the melody track", %{scope: scope, song: song} do
      melody = Enum.find(song.tracks, &(&1.role == "melody"))
      assert {:error, _message} = Studio.remove_track(scope, song, melody.id)
      assert {:error, _message} = Studio.regenerate_track(scope, song, melody.id)
    end

    test "cannot make a track again without the AI music service", %{scope: scope, song: song} do
      track = Enum.find(song.tracks, &(&1.instrument == "drums"))

      assert {:error, "AI audio is not set up" <> _} =
               Studio.regenerate_track(scope, song, track.id)
    end

    test "updates mix values within their ranges", %{scope: scope, song: song} do
      track = Enum.find(song.tracks, &(&1.instrument == "bass"))

      assert {:ok, track} =
               Studio.update_track_mix(scope, song, track.id, %{
                 "volume" => "150",
                 "pan" => "-30",
                 "low" => "-50",
                 "mute" => "true"
               })

      assert track.mix["volume"] == 100
      assert track.mix["pan"] == -30
      assert track.mix["low"] == -12
      assert track.mix["mute"] == true
      assert track.mix["reverb"] == 15
    end

    test "applies a mix suggestion", %{scope: scope, song: song} do
      [melody | _] = song.tracks

      {:ok, song} =
        Studio.put_mix_suggestion(scope, song, %{
          "summary" => "Louder melody.",
          "tracks" => %{to_string(melody.id) => Track.normalize_mix(%{"volume" => 95})}
        })

      {:ok, _} = Studio.apply_mix_suggestion(scope, Studio.get_song!(scope, song.id))
      song = Studio.get_song!(scope, song.id)
      assert song.mix_suggestion == nil
      assert hd(song.tracks).mix["volume"] == 95
    end
  end
end
