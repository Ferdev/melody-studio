defmodule MelodyStudio.Studio.CatalogTest do
  use ExUnit.Case, async: true

  alias MelodyStudio.Studio.Catalog

  test "has a wide list of styles, each with built-in rhythms" do
    assert length(Catalog.genres()) >= 30
    assert Catalog.genre("future_funk").name == "Future funk"
    assert Catalog.genre("chiptune").name == "Chiptune"

    for genre <- Catalog.genres() do
      assert [_, _, _] = rhythms = Catalog.preset_rhythms(genre.id)

      for rhythm <- rhythms, row <- ["kick", "snare", "hihat"] do
        assert length(rhythm["steps"][row]) == 16, "#{genre.id} #{rhythm["name"]} #{row}"
      end
    end
  end

  test "ids are unique" do
    ids = Catalog.genre_ids()
    assert ids == Enum.uniq(ids)
  end

  test "searches by name, group and description" do
    assert [%{id: "chiptune"}] = Catalog.search_genres("chip")
    assert Enum.any?(Catalog.search_genres("8-bit"), &(&1.id == "chiptune"))
    assert Catalog.search_genres("") == Catalog.genres()
    assert Catalog.search_genres("zzzz") == []
  end

  test "typed styles keep their text, known names become ids" do
    assert Catalog.normalize_genre("Drum and Bass") == "drum_and_bass"
    assert Catalog.normalize_genre("vaporwave") == "vaporwave"
    assert Catalog.genre_name("vaporwave") == "vaporwave"
    assert Catalog.custom_genre?("vaporwave")
    refute Catalog.custom_genre?("pop")
    assert Catalog.genre_family("vaporwave") == "pop"
    assert Catalog.genre_family("future_funk") == "funk"
  end
end
