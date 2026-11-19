defmodule MelodyStudio.Workers.GenerateStemTest do
  # Not async: the tests change the app config to turn the music service on.
  use MelodyStudio.DataCase, async: false
  use Oban.Testing, repo: MelodyStudio.Repo

  import MelodyStudio.AccountsFixtures
  import MelodyStudio.StudioFixtures

  alias MelodyStudio.{Storage, Studio}
  alias MelodyStudio.Stems.Replicate
  alias MelodyStudio.Workers.{ArrangeSong, GenerateStem}

  setup do
    config = Application.get_env(:melody_studio, Replicate)
    Application.put_env(:melody_studio, Replicate, Keyword.put(config, :api_token, "r8-test"))
    on_exit(fn -> Application.put_env(:melody_studio, Replicate, config) end)

    scope = user_scope_fixture()
    song = ready_song_fixture(scope)
    {:ok, _} = Studio.save_melody_audio(scope, song, "RIFF-melody")
    {:ok, _} = Studio.build_song(scope, song)
    :ok = perform_job(ArrangeSong, %{song_id: song.id})

    %{scope: scope, song: Studio.get_song!(scope, song.id)}
  end

  test "the build starts one stem job for each instrument", %{song: song} do
    assert song.status == "generating"
    tracks = Enum.reject(song.tracks, &(&1.role == "melody"))
    assert Enum.all?(tracks, &(&1.status == "pending"))

    for track <- tracks do
      assert_enqueued(worker: GenerateStem, args: %{track_id: track.id})
    end
  end

  test "makes the audio and stores it", %{scope: scope, song: song} do
    track = Enum.find(song.tracks, &(&1.instrument == "drums"))
    test_pid = self()

    Req.Test.stub(Replicate, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/files"} ->
          Req.Test.json(conn, %{"urls" => %{"get" => "https://files.example/melody.wav"}})

        {"POST", "/v1/predictions"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:prediction, Jason.decode!(body)})
          Plug.Conn.put_status(conn, 201) |> Req.Test.json(%{"id" => "pred-1"})

        {"GET", "/v1/predictions/pred-1"} ->
          Req.Test.json(conn, %{
            "status" => "succeeded",
            "output" => "https://out.example/drums.wav"
          })

        {"GET", "/drums.wav"} ->
          Plug.Conn.send_resp(conn, 200, "RIFF-drums")
      end
    end)

    assert {:snooze, _} = perform_job(GenerateStem, %{track_id: track.id})
    assert_received {:prediction, %{"input" => input}}
    assert input["prompt"] == track.prompt
    assert input["input_audio"] == "https://files.example/melody.wav"
    assert input["model_version"] == "stereo-melody-large"
    assert input["duration"] == 30

    assert :ok = perform_job(GenerateStem, %{track_id: track.id})

    track = Studio.get_track!(song, track.id)
    assert track.status == "ready"
    assert {:ok, "RIFF-drums"} = Storage.get(track.audio_path)

    # The song is ready when no track is still being made.
    for other <- song.tracks, other.id != track.id, other.role != "melody" do
      Studio.update_track_from_job(other, %{status: "ready"})
    end

    assert Studio.get_song!(scope, song.id).status == "ready"
  end

  test "marks the track as failed when the model fails", %{song: song} do
    track = Enum.find(song.tracks, &(&1.instrument == "bass"))

    {:ok, track} =
      Studio.update_track_from_job(track, %{prediction_id: "pred-2", status: "generating"})

    Req.Test.stub(Replicate, fn conn ->
      Req.Test.json(conn, %{"status" => "failed", "error" => "Out of memory"})
    end)

    assert :ok = perform_job(GenerateStem, %{track_id: track.id})
    track = Studio.get_track!(song, track.id)
    assert track.status == "failed"
    assert track.error == "Out of memory"
  end

  test "a track can be made again", %{scope: scope, song: song} do
    track = Enum.find(song.tracks, &(&1.instrument == "keys"))
    {:ok, track} = Studio.update_track_from_job(track, %{status: "failed", prediction_id: "old"})

    assert {:ok, track} = Studio.regenerate_track(scope, song, track.id)
    assert track.status == "pending"
    assert track.prediction_id == nil
  end
end
