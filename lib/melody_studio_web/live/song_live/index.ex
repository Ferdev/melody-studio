defmodule MelodyStudioWeb.SongLive.Index do
  use MelodyStudioWeb, :live_view

  alias MelodyStudio.Studio
  alias MelodyStudio.Studio.{Catalog, Song}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="font-display text-3xl font-extrabold">My songs</h1>
          <p class="text-base-content/70">Start a new idea or keep working on one.</p>
        </div>
      </div>

      <.form
        for={@form}
        id="new-song-form"
        phx-change="validate"
        phx-submit="create"
        class="flex flex-col gap-3 rounded-box bg-base-100 p-4 shadow-sm sm:flex-row sm:items-start"
      >
        <div class="flex-1">
          <.input
            field={@form[:title]}
            placeholder="Name your new song, for example Summer Morning"
            aria-label="Song name"
            autocomplete="off"
          />
        </div>
        <.button class="btn btn-primary rounded-full sm:mt-1" phx-disable-with="Creating...">
          <.icon name="hero-plus" class="size-5" /> New song
        </.button>
      </.form>

      <div :if={@empty?} id="songs-empty" class="rounded-box bg-base-100 p-10 text-center shadow-sm">
        <div class="text-5xl">🎶</div>
        <h2 class="mt-3 font-display text-xl font-bold">No songs yet</h2>
        <p class="text-base-content/70">Give your first song a name above to begin.</p>
      </div>

      <div id="songs" phx-update="stream" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div
          :for={{dom_id, song} <- @streams.songs}
          id={dom_id}
          class="group flex flex-col rounded-box bg-base-100 p-5 shadow-sm transition hover:shadow-md"
        >
          <%= if @renaming_id == song.id do %>
            <.form
              for={@rename_form}
              id={"rename-form-#{song.id}"}
              phx-submit="rename"
              phx-value-id={song.id}
            >
              <.input
                field={@rename_form[:title]}
                id={"rename-title-#{song.id}"}
                aria-label="New name"
                phx-mounted={JS.focus()}
              />
              <div class="flex gap-2">
                <.button class="btn btn-primary btn-sm rounded-full">Save name</.button>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm rounded-full"
                  phx-click="cancel_rename"
                >
                  Cancel
                </button>
              </div>
            </.form>
          <% else %>
            <.link navigate={~p"/songs/#{song}"} class="flex-1">
              <div class="mb-3 flex items-center gap-3">
                <span class="grid size-12 place-items-center rounded-2xl bg-primary/15 text-2xl">
                  {genre_emoji(song.genre)}
                </span>
                <div class="min-w-0">
                  <h2 class="truncate font-display text-lg font-bold">{song.title}</h2>
                  <p class="text-sm text-base-content/60">
                    {Catalog.genre_name(song.genre)} · {song.tempo} BPM · {song.key}
                  </p>
                </div>
              </div>
              <span class={["badge rounded-full", status_class(song.status)]}>
                {status_label(song.status)}
              </span>
            </.link>
            <div class="mt-4 flex gap-2 border-t border-base-200 pt-3">
              <.link navigate={~p"/songs/#{song}"} class="btn btn-primary btn-sm rounded-full">
                Open
              </.link>
              <button
                class="btn btn-ghost btn-sm rounded-full"
                phx-click="start_rename"
                phx-value-id={song.id}
              >
                <.icon name="hero-pencil" class="size-4" /> Rename
              </button>
              <button
                class="btn btn-ghost btn-sm rounded-full text-error"
                phx-click="delete"
                phx-value-id={song.id}
                data-confirm={"Delete \"#{song.title}\"? You cannot undo this."}
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    songs = Studio.list_songs(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "My songs")
     |> assign(:empty?, songs == [])
     |> assign(:renaming_id, nil)
     |> assign(:rename_form, nil)
     |> assign_new_form()
     |> stream(:songs, songs)}
  end

  @impl true
  def handle_event("validate", %{"song" => params}, socket) do
    changeset = Studio.change_song_title(%Song{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("create", %{"song" => params}, socket) do
    case Studio.create_song(socket.assigns.current_scope, params) do
      {:ok, song} ->
        {:noreply, push_navigate(socket, to: ~p"/songs/#{song}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("start_rename", %{"id" => id}, socket) do
    song = Studio.get_song!(socket.assigns.current_scope, id)
    previous = socket.assigns.renaming_id

    socket =
      socket
      |> assign(:renaming_id, song.id)
      |> assign(:rename_form, to_form(Studio.change_song_title(song)))
      |> restream(previous)

    {:noreply, stream_insert(socket, :songs, song)}
  end

  def handle_event("cancel_rename", _params, socket) do
    previous = socket.assigns.renaming_id
    {:noreply, socket |> assign(:renaming_id, nil) |> restream(previous)}
  end

  def handle_event("rename", %{"id" => id, "song" => params}, socket) do
    scope = socket.assigns.current_scope
    song = Studio.get_song!(scope, id)

    case Studio.rename_song(scope, song, params) do
      {:ok, song} ->
        {:noreply,
         socket
         |> assign(:renaming_id, nil)
         |> stream_insert(:songs, song)
         |> put_flash(:info, "Song renamed.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:rename_form, to_form(changeset))
         |> stream_insert(:songs, song)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    song = Studio.get_song!(scope, id)
    {:ok, _} = Studio.delete_song(scope, song)

    {:noreply,
     socket
     |> stream_delete(:songs, song)
     |> assign(:empty?, Studio.list_songs(scope) == [])
     |> put_flash(:info, "Song deleted.")}
  end

  defp restream(socket, nil), do: socket

  defp restream(socket, id) do
    stream_insert(socket, :songs, Studio.get_song!(socket.assigns.current_scope, id))
  end

  defp assign_new_form(socket) do
    assign(socket, :form, to_form(Studio.change_song_title(%Song{})))
  end

  defp genre_emoji(genre), do: Catalog.genre_emoji(genre)

  def status_label("draft"), do: "Idea"
  def status_label("arranging"), do: "AI is planning"
  def status_label("generating"), do: "AI is recording"
  def status_label("ready"), do: "Ready to mix"
  def status_label("failed"), do: "Needs attention"
  def status_label(_), do: "Idea"

  def status_class("ready"), do: "badge-success"
  def status_class("failed"), do: "badge-error"
  def status_class(status) when status in ["arranging", "generating"], do: "badge-info"
  def status_class(_), do: "badge-ghost"
end
