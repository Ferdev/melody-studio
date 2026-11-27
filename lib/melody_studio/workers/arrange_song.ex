defmodule MelodyStudio.Workers.ArrangeSong do
  @moduledoc """
  Asks the AI for the arrangement plan of a song, then creates its tracks and
  starts one stem job for each instrument.
  """
  use Oban.Worker, queue: :generation, max_attempts: 3

  alias MelodyStudio.{AI, Studio}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"song_id" => song_id}} = job) do
    case Studio.get_song_for_job(song_id) do
      nil ->
        :ok

      song ->
        notes = Studio.melody_notes(song)

        if notes == [] do
          Studio.mark_build_failed(song.id, "The melody is empty. Record a melody and try again.")
          :ok
        else
          {:ok, plan, _source} = AI.arrangement(song, notes)

          case Studio.apply_arrangement(song, plan) do
            {:ok, _song} ->
              :ok

            {:error, reason} ->
              if job.attempt >= job.max_attempts do
                Studio.mark_build_failed(
                  song.id,
                  "We could not build your song. Please try again."
                )
              end

              {:error, reason}
          end
        end
    end
  end
end
