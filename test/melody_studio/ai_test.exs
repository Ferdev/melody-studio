defmodule MelodyStudio.AITest do
  # Not async: the tests change the app config to turn the AI on.
  use MelodyStudio.DataCase, async: false

  import MelodyStudio.AccountsFixtures
  import MelodyStudio.StudioFixtures

  alias MelodyStudio.{AI, Studio}

  defp with_claude(_context) do
    config = Application.get_env(:melody_studio, AI.Claude)
    Application.put_env(:melody_studio, AI.Claude, Keyword.put(config, :api_key, "test-key"))
    on_exit(fn -> Application.put_env(:melody_studio, AI.Claude, config) end)
    :ok
  end

  defp claude_reply(json) do
    Req.Test.stub(AI.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:claude_request, conn.req_headers, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => Jason.encode!(json)}]
      })
    end)
  end

  describe "without an API key" do
    test "rhythm ideas come from the built-in list" do
      assert {:ok, [_, _, _] = rhythms, :builtin} =
               AI.rhythm_ideas(%{genre: "lofi", tempo: 80, key: "C major"})

      assert hd(rhythms)["feel"] == "swing"
    end

    test "the arrangement uses a common progression in the song key" do
      scope = user_scope_fixture()
      song = ready_song_fixture(scope)
      {:ok, _} = Studio.update_song_settings(scope, song, %{key: "A minor"})
      song = Studio.get_song!(scope, song.id)

      assert {:ok, plan, :builtin} = AI.arrangement(song, melody_notes())
      assert hd(plan["sections"])["chords"] == ["Am", "F", "C", "G"]
      assert Enum.map(plan["tracks"], & &1["instrument"]) == ["drums", "bass", "keys"]
    end
  end

  describe "with Claude" do
    setup :with_claude

    test "rhythm ideas are cleaned to 16 steps" do
      claude_reply(%{
        "rhythms" => [
          %{
            "name" => "Bounce",
            "description" => "Happy and light.",
            "feel" => "straight",
            "kick" => [1, 0, 0, 0, 1],
            "snare" => List.duplicate(1, 20),
            "hihat" => [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]
          }
        ]
      })

      assert {:ok, [rhythm], :ai} = AI.rhythm_ideas(%{genre: "pop", tempo: 100, key: "C major"})
      assert length(rhythm["steps"]["kick"]) == 16
      assert length(rhythm["steps"]["snare"]) == 16
      assert Enum.take(rhythm["steps"]["kick"], 6) == [1, 0, 0, 0, 1, 0]

      assert_received {:claude_request, headers, body}
      assert {"x-api-key", "test-key"} in headers
      assert {"anthropic-version", "2026-10-21"} in headers
      assert body["model"] == "claude-sonnet-5-5"
      assert body["output_config"]["format"]["type"] == "json_schema"
      assert body["fallbacks"] == "default"
    end

    test "the arrangement is checked against the song choices" do
      scope = user_scope_fixture()
      song = ready_song_fixture(scope)

      claude_reply(%{
        "summary" => "A bright pop song.",
        "sections" => [
          %{
            "name" => "Verse",
            "chords" => ["C", "G", "not a chord"],
            "energy" => "medium",
            "melody" => true
          },
          %{
            "name" => "Chorus",
            "chords" => ["F", "G", "Am", "Em", "C"],
            "energy" => "loud",
            "melody" => true
          }
        ],
        "tracks" => [
          %{"instrument" => "drums", "role" => "groove", "prompt" => "pop drums, 100 bpm"},
          %{"instrument" => "tuba", "role" => "fun", "prompt" => "tuba"}
        ]
      })

      assert {:ok, plan, :ai} = AI.arrangement(song, melody_notes())
      [verse, chorus] = plan["sections"]
      assert verse["chords"] == ["C", "G", "C", "C"]
      assert chorus["chords"] == ["F", "G", "Am", "Em"]
      assert chorus["energy"] == "medium"
      assert Enum.map(plan["tracks"], & &1["instrument"]) == ["drums", "bass", "keys"]
      assert hd(plan["tracks"])["prompt"] == "pop drums, 100 bpm"
    end

    test "falls back to built-in ideas when Claude declines" do
      Req.Test.stub(AI.Claude, fn conn ->
        Req.Test.json(conn, %{"stop_reason" => "refusal", "content" => []})
      end)

      assert {:ok, _rhythms, :builtin} =
               AI.rhythm_ideas(%{genre: "rock", tempo: 120, key: "E minor"})
    end

    test "mix suggestions keep only known tracks and valid values" do
      scope = user_scope_fixture()
      song = ready_song_fixture(scope)
      {:ok, _} = Studio.apply_arrangement(song, AI.basic_arrangement(song, melody_notes()))
      song = Studio.get_song!(scope, song.id)
      [melody | _] = song.tracks

      claude_reply(%{
        "summary" => "Clearer melody.",
        "tracks" => [
          %{
            "id" => melody.id,
            "volume" => 140,
            "pan" => 0,
            "reverb" => 30,
            "delay" => 10,
            "low" => 0,
            "mid" => 0,
            "high" => 3,
            "punch" => 20
          },
          %{
            "id" => -1,
            "volume" => 10,
            "pan" => 0,
            "reverb" => 0,
            "delay" => 0,
            "low" => 0,
            "mid" => 0,
            "high" => 0,
            "punch" => 0
          }
        ]
      })

      assert {:ok, %{"tracks" => mixes, "summary" => "Clearer melody."}, :ai} =
               AI.mix_suggestion(song, song.tracks)

      assert Map.keys(mixes) == [to_string(melody.id)]
      assert mixes[to_string(melody.id)]["volume"] == 100
    end
  end
end
