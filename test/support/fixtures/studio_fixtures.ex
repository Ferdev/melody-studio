defmodule MelodyStudio.StudioFixtures do
  @moduledoc """
  Test helpers for songs, melodies and tracks.
  """

  alias MelodyStudio.Studio

  def melody_notes do
    [
      %{"pitch" => 60, "start" => 0.0, "duration" => 1.0, "velocity" => 0.8},
      %{"pitch" => 64, "start" => 1.0, "duration" => 1.0, "velocity" => 0.8},
      %{"pitch" => 67, "start" => 2.0, "duration" => 2.0, "velocity" => 0.8},
      %{"pitch" => 65, "start" => 4.0, "duration" => 2.0, "velocity" => 0.7},
      %{"pitch" => 64, "start" => 6.0, "duration" => 2.0, "velocity" => 0.7}
    ]
  end

  def song_fixture(scope, attrs \\ %{}) do
    {:ok, song} = Studio.create_song(scope, Enum.into(attrs, %{title: "My test song"}))
    Studio.get_song!(scope, song.id)
  end

  @doc "A song with a melody, a style and instruments: ready to build."
  def ready_song_fixture(scope, attrs \\ %{}) do
    song = song_fixture(scope, attrs)
    {:ok, _} = Studio.save_melody(scope, song, melody_notes())

    {:ok, _} =
      Studio.update_song_style(scope, song, %{
        genre: "pop",
        instruments: ["drums", "bass", "keys"]
      })

    Studio.get_song!(scope, song.id)
  end
end
