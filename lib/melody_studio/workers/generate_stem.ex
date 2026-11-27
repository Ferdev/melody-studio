defmodule MelodyStudio.Workers.GenerateStem do
  @moduledoc """
  Makes the audio of one track with the AI music model. The job starts the
  remote generation, then checks it again every few seconds until the audio is
  ready, and stores the file.
  """
  use Oban.Worker,
    queue: :generation,
    max_attempts: 5,
    unique: [keys: [:track_id], states: [:available, :scheduled, :executing, :retryable]]

  alias MelodyStudio.{Stems, Storage, Studio}
  alias MelodyStudio.Studio.Track

  @poll_seconds 5
  @timeout_seconds 20 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"track_id" => track_id}} = job) do
    case Studio.get_track_for_job(track_id) do
      %Track{status: status} = track when status in ["pending", "generating"] ->
        run(track, job)

      _ ->
        :ok
    end
  end

  defp run(track, job) do
    cond do
      not Stems.configured?() ->
        Studio.update_track_from_job(track, %{status: "sketch"})
        :ok

      timed_out?(job) ->
        fail(track, "Making this track took too long. Please try again.")

      is_nil(track.prediction_id) ->
        start(track, job)

      true ->
        poll(track, job)
    end
  end

  defp start(track, job) do
    song = track.song

    request = %{
      prompt: track.prompt,
      duration: duration(song),
      melody_audio: melody_audio(song)
    }

    case Stems.start(request) do
      {:ok, id} ->
        Studio.update_track_from_job(track, %{prediction_id: id, status: "generating"})
        {:snooze, @poll_seconds}

      {:error, reason} ->
        retry_or_fail(track, job, reason)
    end
  end

  defp poll(track, job) do
    case Stems.status(track.prediction_id) do
      :processing ->
        {:snooze, @poll_seconds}

      {:succeeded, url} ->
        path = Storage.song_path(track.song_id, "track-#{track.id}")

        with {:ok, audio} <- Stems.download(url),
             :ok <- Storage.put(path, audio, "audio/wav") do
          Studio.update_track_from_job(track, %{status: "ready", audio_path: path, error: nil})
          Storage.delete(track.audio_path)
          :ok
        else
          {:error, reason} -> retry_or_fail(track, job, reason)
        end

      {:failed, message} ->
        fail(track, message)

      {:error, reason} ->
        retry_or_fail(track, job, reason)
    end
  end

  defp retry_or_fail(track, job, reason) do
    if job.attempt >= job.max_attempts do
      fail(track, "The AI music service did not answer. Please try again later.")
    else
      {:error, reason}
    end
  end

  defp fail(track, message) do
    Studio.update_track_from_job(track, %{status: "failed", error: message})
    :ok
  end

  defp duration(song) do
    song
    |> Studio.song_seconds()
    |> ceil()
    |> max(5)
    |> min(Stems.max_duration())
  end

  defp melody_audio(%{melody: %{audio_path: path}}) when is_binary(path) do
    case Storage.get(path) do
      {:ok, binary} -> binary
      _ -> nil
    end
  end

  defp melody_audio(_), do: nil

  defp timed_out?(%Oban.Job{inserted_at: inserted_at}) do
    DateTime.diff(DateTime.utc_now(), inserted_at) > @timeout_seconds
  end
end
