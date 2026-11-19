defmodule MelodyStudio.Studio.Song do
  use Ecto.Schema
  import Ecto.Changeset

  alias MelodyStudio.Studio.{Catalog, Melody, Track}

  @statuses ~w(draft arranging generating ready failed)

  schema "songs" do
    field :title, :string
    field :genre, :string
    field :tempo, :integer, default: 100
    field :key, :string, default: "C major"
    field :instruments, {:array, :string}, default: []
    field :rhythm, :map
    field :rhythm_ideas, {:array, :map}, default: []
    field :arrangement, :map
    field :status, :string, default: "draft"
    field :error, :string
    field :mix_suggestion, :map

    belongs_to :user, MelodyStudio.Accounts.User
    has_one :melody, Melody
    has_many :tracks, Track, preload_order: [asc: :position, asc: :id]

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc "Changeset for the title, used when a song is created or renamed."
  def title_changeset(song, attrs) do
    song
    |> cast(attrs, [:title])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title], message: "Please give your song a name")
    |> validate_length(:title, max: 80)
  end

  @doc "Changeset for tempo and key."
  def settings_changeset(song, attrs) do
    song
    |> cast(attrs, [:tempo, :key])
    |> validate_required([:tempo, :key])
    |> validate_number(:tempo, greater_than_or_equal_to: 50, less_than_or_equal_to: 200)
    |> validate_inclusion(:key, Catalog.keys())
  end

  @doc "Changeset for the style choices: genre and instruments."
  def style_changeset(song, attrs) do
    song
    |> cast(attrs, [:genre, :instruments])
    |> validate_inclusion(:genre, Catalog.genre_ids())
    |> validate_subset(:instruments, Catalog.instrument_ids())
  end

  @doc "Changeset for internal fields that the app writes (never the user directly)."
  def system_changeset(song, attrs) do
    song
    |> cast(attrs, [:rhythm, :rhythm_ideas, :arrangement, :status, :error, :mix_suggestion])
    |> validate_inclusion(:status, @statuses)
  end
end
