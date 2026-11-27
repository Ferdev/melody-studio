defmodule MelodyStudio.Repo.Migrations.CreateSongs do
  use Ecto.Migration

  def change do
    create table(:songs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :genre, :string
      add :tempo, :integer, null: false, default: 100
      add :key, :string, null: false, default: "C major"
      add :instruments, {:array, :string}, null: false, default: []
      add :rhythm, :map
      add :rhythm_ideas, :jsonb, null: false, default: "[]"
      add :arrangement, :map
      add :status, :string, null: false, default: "draft"
      add :error, :text
      add :mix_suggestion, :map

      timestamps(type: :utc_datetime)
    end

    create index(:songs, [:user_id, :updated_at])

    create table(:melodies) do
      add :song_id, references(:songs, on_delete: :delete_all), null: false
      add :notes, :jsonb, null: false, default: "[]"
      add :audio_path, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:melodies, [:song_id])

    create table(:tracks) do
      add :song_id, references(:songs, on_delete: :delete_all), null: false
      add :instrument, :string, null: false
      add :role, :string, null: false
      add :prompt, :text
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :audio_path, :string
      add :prediction_id, :string
      add :mix, :map, null: false, default: %{}
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:tracks, [:song_id, :position])
  end
end
