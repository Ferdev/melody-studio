import * as Tone from "tone"
import type { HookContext, Mix, SongData } from "../audio/types"
import { buildSongGraph, loadBuffers, renderSong, sectionStarts, songDuration, SongGraph } from "../audio/song"
import { downloadBlob, encodeWav } from "../audio/wav"

interface State {
  data: SongData
  structure: string
  graph: SongGraph | null
  buffers: Map<number, Tone.ToneAudioBuffer> | null
  playing: boolean
  exporting: boolean
  frame: number
  onInput: (event: Event) => void
  onClick: (event: Event) => void
}

type Self = HookContext & { s: State }

function parse(el: HTMLElement): SongData {
  return JSON.parse(el.dataset.song || "{}")
}

/** Everything except the mix. When it changes, the player rebuilds the song. */
function structureKey(data: SongData) {
  return JSON.stringify({
    tempo: data.tempo,
    melody: data.melody,
    rhythm: data.rhythm,
    sections: data.sections,
    tracks: data.tracks.map((t) => [t.id, t.instrument, t.audioUrl]),
  })
}

function $(self: Self, selector: string) {
  return self.el.querySelector(selector) as HTMLElement | null
}

function formatTime(seconds: number) {
  const s = Math.max(0, Math.floor(seconds))
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
}

function setLabel(self: Self, text: string) {
  const label = $(self, "[data-role=section]")
  if (label) label.textContent = text
}

function setPlayIcon(self: Self, playing: boolean) {
  const button = $(self, "[data-action=play]")
  if (!button) return
  button.setAttribute("aria-label", playing ? "Pause" : "Play")
  button.classList.toggle("btn-active", playing)
}

async function ensureGraph(self: Self) {
  if (self.s.graph) return self.s.graph
  setLabel(self, "Loading sounds...")
  if (!self.s.buffers) self.s.buffers = await loadBuffers(self.s.data)
  const transport = Tone.getTransport()
  transport.stop()
  transport.cancel(0)
  transport.position = 0
  self.s.graph = await buildSongGraph(self.s.data, self.s.buffers, transport)
  transport.schedule(() => Tone.getDraw().schedule(() => stop(self), Tone.now()), self.s.graph.duration)
  return self.s.graph
}

async function play(self: Self) {
  await Tone.start()
  const transport = Tone.getTransport()

  if (self.s.playing) {
    transport.pause()
    self.s.playing = false
    setPlayIcon(self, false)
    setLabel(self, "Paused")
    return
  }

  await ensureGraph(self)
  transport.start("+0.05")
  self.s.playing = true
  setPlayIcon(self, true)
  tick(self)
}

function stop(self: Self) {
  const transport = Tone.getTransport()
  transport.stop()
  transport.position = 0
  self.s.playing = false
  setPlayIcon(self, false)
  cancelAnimationFrame(self.s.frame)
  updateProgress(self, 0)
  setLabel(self, "Press play to listen")
}

function tick(self: Self) {
  if (!self.s.playing) return
  updateProgress(self, Tone.getTransport().seconds)
  self.s.frame = requestAnimationFrame(() => tick(self))
}

function updateProgress(self: Self, seconds: number) {
  const duration = songDuration(self.s.data)
  const progress = $(self, "[data-role=progress]") as HTMLProgressElement | null
  if (progress) progress.value = Math.min(100, (seconds / duration) * 100)
  const time = $(self, "[data-role=time]")
  if (time) time.textContent = `${formatTime(seconds)} / ${formatTime(duration)}`

  if (self.s.playing) {
    const starts = sectionStarts(self.s.data)
    let index = 0
    starts.forEach((start, i) => {
      if (seconds >= start) index = i
    })
    const section = self.s.data.sections[index]
    if (section) setLabel(self, `Now playing: ${section.name}`)
  }
}

function resetGraph(self: Self) {
  if (self.s.playing) stop(self)
  self.s.graph?.dispose()
  self.s.graph = null
  self.s.buffers = null
}

async function exportWav(self: Self) {
  if (self.s.exporting) return
  self.s.exporting = true
  const button = $(self, "[data-action=export]") as HTMLButtonElement | null
  const label = $(self, "[data-role=export-label]")
  if (button) button.disabled = true
  if (label) label.textContent = "Preparing your file..."

  try {
    if (!self.s.buffers) self.s.buffers = await loadBuffers(self.s.data)
    const rendered = await renderSong(self.s.data, self.s.buffers)
    const title = (self.el.dataset.title || "my-song").replace(/[^\p{L}\p{N} _-]+/gu, "").trim() || "my-song"
    downloadBlob(encodeWav(rendered), `${title}.wav`)
  } catch (_error) {
    self.pushEvent("export_failed", { message: "We could not make the WAV file. Please try again." })
  } finally {
    self.s.exporting = false
    if (button) button.disabled = false
    if (label) label.textContent = "Download WAV"
  }
}

export const SongPlayer = {
  mounted(this: Self) {
    const self = this
    const data = parse(self.el)

    self.s = {
      data,
      structure: structureKey(data),
      graph: null,
      buffers: null,
      playing: false,
      exporting: false,
      frame: 0,
      onInput: (event: Event) => {
        const input = event.target as HTMLInputElement
        if (!input.dataset.param || !input.dataset.trackId) return
        const trackId = Number(input.dataset.trackId)
        const param = input.dataset.param as keyof Mix
        const value = Number(input.value)
        const track = self.s.data.tracks.find((t) => t.id === trackId)
        if (track) (track.mix as any)[param] = value
        self.s.graph?.setParam(trackId, param, value)
      },
      onClick: (event: Event) => {
        const target = (event.target as HTMLElement).closest("[data-action]") as HTMLElement | null
        if (!target) return
        if (target.dataset.action === "play") play(self)
        if (target.dataset.action === "stop") stop(self)
        if (target.dataset.action === "export") exportWav(self)
      },
    }

    self.el.addEventListener("input", self.s.onInput)
    $(self, "#song-player-ui")?.addEventListener("click", self.s.onClick)
    updateProgress(self, 0)
  },

  updated(this: Self) {
    const data = parse(this.el)
    const structure = structureKey(data)
    this.s.data = data

    if (structure !== this.s.structure) {
      this.s.structure = structure
      resetGraph(this)
      updateProgress(this, 0)
    } else {
      this.s.graph?.applyMix(data.tracks)
    }
  },

  destroyed(this: Self) {
    cancelAnimationFrame(this.s.frame)
    const transport = Tone.getTransport()
    transport.stop()
    this.s.graph?.dispose()
  },
}
