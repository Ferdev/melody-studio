defmodule MelodyStudioWeb.SongLiveTest do
  use MelodyStudioWeb.ConnCase, async: true
  use Oban.Testing, repo: MelodyStudio.Repo

  import Phoenix.LiveViewTest
  import MelodyStudio.AccountsFixtures
  import MelodyStudio.StudioFixtures

  alias MelodyStudio.Studio
  alias MelodyStudio.Workers.ArrangeSong

  setup :register_and_log_in_user

  describe "My songs" do
    test "requires login" do
      conn = build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/songs")
    end

    test "creates a song and opens it", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/songs")
      assert html =~ "No songs yet"

      assert lv |> form("#new-song-form", song: %{title: ""}) |> render_submit() =~
               "Please give your song a name"

      {:ok, _show, html} =
        lv
        |> form("#new-song-form", song: %{title: "Moonlight"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Moonlight"
      assert html =~ "Play your melody"
    end

    test "renames and deletes songs", %{conn: conn, scope: scope} do
      song = song_fixture(scope, %{title: "Old name"})
      {:ok, lv, html} = live(conn, ~p"/songs")
      assert html =~ "Old name"

      lv |> element("#songs-#{song.id} button", "Rename") |> render_click()

      html =
        lv
        |> form("#rename-form-#{song.id}", song: %{title: "New name"})
        |> render_submit()

      assert html =~ "New name"
      assert Studio.get_song!(scope, song.id).title == "New name"

      lv |> element("#songs-#{song.id} button", "Delete") |> render_click()
      refute has_element?(lv, "#songs-#{song.id}")
      assert Studio.list_songs(scope) == []
    end

    test "does not show the songs of other people", %{conn: conn} do
      other = user_scope_fixture()
      song_fixture(other, %{title: "Secret song"})
      {:ok, _lv, html} = live(conn, ~p"/songs")
      refute html =~ "Secret song"
    end
  end

  describe "Studio" do
    test "other people cannot open a song", %{conn: conn} do
      song = song_fixture(user_scope_fixture())
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/songs/#{song}") end
    end

    test "saves the melody and the speed", %{conn: conn, scope: scope} do
      song = song_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/songs/#{song}")

      lv
      |> element("#melody-recorder")
      |> render_hook("save_melody", %{notes: melody_notes()})

      assert Studio.melody_notes(Studio.get_song!(scope, song.id)) == melody_notes()

      lv |> form("#song-settings-form", song: %{tempo: "132", key: "D minor"}) |> render_change()
      song = Studio.get_song!(scope, song.id)
      assert {song.tempo, song.key} == {132, "D minor"}
    end

    test "chooses a style, instruments and a rhythm", %{conn: conn, scope: scope} do
      song = song_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/songs/#{song}?step=style")

      lv |> element("#genre-lofi") |> render_click()
      lv |> element("#instrument-drums") |> render_click()
      lv |> element("#instrument-keys") |> render_click()

      lv |> element("#suggest-rhythms") |> render_click()
      html = render_async(lv)
      assert html =~ "AI ideas are not set up on this server"
      assert html =~ "Lazy boom bap"

      lv |> element("#rhythm-0 button", "Use this one") |> render_click()

      song = Studio.get_song!(scope, song.id)
      assert song.genre == "lofi"
      assert song.instruments == ["drums", "keys"]
      assert song.rhythm["name"] == "Lazy boom bap"
    end

    test "builds the song and shows the band", %{conn: conn, scope: scope} do
      song = ready_song_fixture(scope)
      {:ok, lv, html} = live(conn, ~p"/songs/#{song}?step=build")
      assert html =~ "Build my song"

      lv |> element("#build-song") |> render_hook("build_song", %{})
      assert render(lv) =~ "planning the song"
      assert_enqueued(worker: ArrangeSong, args: %{song_id: song.id})

      :ok = perform_job(ArrangeSong, %{song_id: song.id})
      html = render(lv)
      assert html =~ "The plan"
      assert html =~ "Built-in sound"
      assert has_element?(lv, "#tracks li", "Drums")

      lv |> form("#add-track-form", instrument: "pads") |> render_submit()
      assert has_element?(lv, "#tracks li", "Pads")
    end

    test "shows what is missing before a build", %{conn: conn, scope: scope} do
      song = song_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/songs/#{song}?step=build")
      assert has_element?(lv, "#build-song[disabled]")
      assert has_element?(lv, "a[href='/songs/#{song.id}?step=melody']", "Add it")
      assert has_element?(lv, "a[href='/songs/#{song.id}?step=style']", "Add it")
    end

    test "mixes the song", %{conn: conn, scope: scope} do
      song = ready_song_fixture(scope)
      {:ok, _} = Studio.build_song(scope, song)
      :ok = perform_job(ArrangeSong, %{song_id: song.id})
      song = Studio.get_song!(scope, song.id)
      bass = Enum.find(song.tracks, &(&1.instrument == "bass"))

      {:ok, lv, html} = live(conn, ~p"/songs/#{song}")
      assert html =~ "Mix your song"
      assert has_element?(lv, "#song-player[data-song]")

      lv
      |> form("#mix-form-#{bass.id}", mix: %{volume: "55", pan: "-40"})
      |> render_change(%{"track_id" => bass.id})

      lv |> element("#mixer-#{bass.id} button[phx-value-field=mute]") |> render_click()

      bass = Studio.get_track!(song, bass.id)
      assert bass.mix["volume"] == 55
      assert bass.mix["pan"] == -40
      assert bass.mix["mute"] == true

      lv |> element("#suggest-mix") |> render_click()
      assert render_async(lv) =~ "A balanced starting mix"

      lv |> element("#mix-suggestion button", "Use these settings") |> render_click()
      refute has_element?(lv, "#mix-suggestion")
      assert Studio.get_track!(song, bass.id).mix["volume"] == 78
    end
  end
end
