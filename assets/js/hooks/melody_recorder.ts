import * as Tone from "tone"
import type { HookContext, Note } from "../audio/types"
import { createClick, createPiano } from "../audio/instruments"
import { midiToFrequency } from "../audio/theory"
import { NoteEditor } from "./note_editor"

const COMPUTER_KEYS: Record<string, number> = {
  a: 0, w: 1, s: 2, e: 3, d: 4, f: 5, t: 6, g: 7, y: 8, h: 9, u: 10, j: 11,
  k: 12, o: 13, l: 14, p: 15, ";": 16,
}

/** A note played up to this many beats before the first beat counts as on the first beat. */
const EARLY_TOLERANCE = 0.25

/**
 * idle: nothing happens. armed: waiting for the first note to start recording.
 * count-in: the metronome counts before recording. recording, playing: as named.
 */
type Mode = "idle" | "armed" | "count-in" | "recording" | "playing"

interface ActiveNote {
  start: number
  velocity: number
}

interface State {
  notes: Note[]
  history: Note[][]
  take: Note[]
  active: Map<number, ActiveNote>
  mode: Mode
  tempo: number
  maxBeats: number
  octave: number
  /** The audio time of beat 0 of the take or of the playback. */
  startAt: number
  /** The beat where the playback ends. */
  playEnd: number
  /** The live piano. It is never stopped, so it answers at once. */
  piano: Tone.PolySynth | null
  /** The piano for playback. Disposing it cancels the notes scheduled ahead. */
  player: Tone.PolySynth | null
  click: Tone.Synth | null
  pressed: Map<string | number, number>
  lit: Set<number>
  frame: number
  lastPreview: number
  midiAccess: MIDIAccess | null
  cleanup: (() => void)[]
  editor: NoteEditor | null
  saveTimer: number
}

type Self = HookContext & { s: State }

function $(self: Self, selector: string) {
  return self.el.querySelector(selector) as HTMLElement | null
}

function setStatus(self: Self, text: string) {
  const status = $(self, "[data-role=status]")
  if (status && status.textContent !== text) status.textContent = text
}

function beat(self: Self) {
  return 60 / self.s.tempo
}

function option(self: Self, name: string): boolean {
  const input = self.el.querySelector(`[data-option=${name}]`) as HTMLInputElement | null
  return input ? input.checked : false
}

function bars(notes: Note[]) {
  const end = notes.reduce((max, n) => Math.max(max, n.start + n.duration), 0)
  return Math.ceil(end / 4 - 0.001)
}

function describe(notes: Note[]) {
  if (notes.length === 0) return "No melody yet. Press Record to begin."
  const count = bars(notes)
  return `Your melody has ${notes.length} ${notes.length === 1 ? "note" : "notes"} over ${count} ${count === 1 ? "bar" : "bars"}.`
}

function refreshButtons(self: Self) {
  const { mode, notes, history } = self.s
  const busy = mode !== "idle"
  const set = (action: string, disabled: boolean) => {
    const button = self.el.querySelector(`[data-action=${action}]`) as HTMLButtonElement | null
    if (button) button.disabled = disabled
  }
  set("record", busy)
  set("stop", !busy)
  set("play", busy || notes.length === 0)
  set("undo", busy || history.length === 0)
  set("clear", busy || notes.length === 0)
  self.s.editor?.render()
}

function highlight(self: Self, pitch: number, down: boolean) {
  const key = self.el.querySelector(`[data-pitch="${pitch}"]`)
  key?.classList.toggle("is-down", down)
}

// -----------------------------------------------------------------------------
// Audio timing

/** The audio clock now, without Tone's look-ahead, so live notes sound at once. */
function audioNow() {
  return Tone.immediate()
}

/**
 * How late the speakers play a sound after the code starts it. People play
 * along with what they hear, so the recorder moves their notes back by this.
 */
function outputLatency() {
  const raw = Tone.getContext().rawContext as AudioContext
  const latency = raw.outputLatency || raw.baseLatency || 0
  return Math.min(Math.max(latency, 0), 0.15)
}

function beatAt(self: Self, time: number) {
  return (time - self.s.startAt) / beat(self)
}

/** Makes the sounds ready. Building them is synchronous, so a key press never waits. */
function prepareSounds(self: Self) {
  if (Tone.getContext().state !== "running") Tone.start()
  if (!self.s.piano) self.s.piano = createPiano().toDestination()
  if (!self.s.click) self.s.click = createClick().toDestination()
}

// -----------------------------------------------------------------------------
// Playing the piano

function noteOn(self: Self, pitch: number, velocity = 0.8) {
  // Read the clock first, so nothing else delays the time of the note.
  const time = audioNow()
  prepareSounds(self)
  self.s.piano!.triggerAttack(midiToFrequency(pitch), time, velocity)
  highlight(self, pitch, true)

  const heard = time - outputLatency()
  if (self.s.mode === "armed") startTakeNow(self, heard)

  if (self.s.mode === "recording" || self.s.mode === "count-in") {
    self.s.active.set(pitch, { start: beatAt(self, heard), velocity })
  }
}

function noteOff(self: Self, pitch: number) {
  const time = audioNow()
  self.s.piano?.triggerRelease(midiToFrequency(pitch), time)
  highlight(self, pitch, false)

  const active = self.s.active.get(pitch)
  if (active) {
    self.s.active.delete(pitch)
    finishNote(self, pitch, active, beatAt(self, time - outputLatency()))
  }
}

function finishNote(self: Self, pitch: number, active: ActiveNote, end: number) {
  if (active.start >= self.s.maxBeats) return
  const duration = Math.max(Math.min(end, self.s.maxBeats) - active.start, 0.1)
  self.s.take.push({ pitch, start: active.start, duration, velocity: active.velocity })
}

// -----------------------------------------------------------------------------
// Recording

async function record(self: Self) {
  await Tone.start()
  prepareSounds(self)

  self.s.take = []
  self.s.active.clear()
  self.s.editor?.clearSelection()

  if (option(self, "waitForNote")) {
    self.s.mode = "armed"
    setStatus(self, "Ready. Recording starts with the first note you play.")
    refreshButtons(self)
    self.s.editor?.showPreview([])
    return
  }

  const countIn = option(self, "countIn") ? 4 : 0
  // Tone.now() is a little ahead of the clock, which leaves time to schedule the clicks.
  self.s.startAt = Tone.now() + 0.05 + countIn * beat(self)
  self.s.mode = countIn > 0 ? "count-in" : "recording"
  scheduleClicks(self, -countIn)
  refreshButtons(self)
  self.s.editor?.showPreview([])
  loop(self)
}

/** Starts the take on the first note when the recorder waits for it. */
function startTakeNow(self: Self, heard: number) {
  self.s.startAt = heard
  self.s.mode = "recording"
  // The first note is beat 1, so the clicks start on beat 2.
  scheduleClicks(self, 1)
  refreshButtons(self)
  loop(self)
}

/** Schedules the metronome from a beat (negative beats are the count-in). */
function scheduleClicks(self: Self, fromBeat: number) {
  const metronome = option(self, "metronome")
  const b = beat(self)
  const click = self.s.click!

  for (let index = fromBeat; index < self.s.maxBeats; index++) {
    if (index >= 0 && !metronome) break
    const strong = ((index % 4) + 4) % 4 === 0
    // The clicks are heard late by the output latency, like the notes.
    const time = self.s.startAt + index * b
    click.triggerAttackRelease(strong ? "C6" : "G5", 0.03, time, strong ? 0.9 : 0.5)
  }
}

function stop(self: Self) {
  const { mode } = self.s
  cancelAnimationFrame(self.s.frame)
  self.s.click?.dispose()
  self.s.click = null

  if (mode === "recording" || mode === "count-in") {
    const end = beatAt(self, audioNow() - outputLatency())
    for (const [pitch, active] of self.s.active) finishNote(self, pitch, active, end)
    self.s.active.clear()
    self.s.mode = "idle"
    self.s.editor?.setPlayhead(null)
    self.s.editor?.showPreview(null)

    if (self.s.take.length === 0) {
      setStatus(self, "We did not hear any notes. Press Record and try again.")
    } else {
      const { notes, shifted } = placeTake(self.s.take, self.s.maxBeats, option(self, "snap"))
      self.s.history.push(self.s.notes)
      self.s.notes = notes
      self.s.editor?.clearSelection()
      save(self)
      setStatus(
        self,
        shifted
          ? `Nice! You started before the count-in ended, so your melody now begins on beat 1. ${describe(notes)}`
          : `Nice! ${describe(notes)}`
      )
    }
  } else if (mode === "armed") {
    self.s.mode = "idle"
    self.s.editor?.showPreview(null)
    setStatus(self, describe(self.s.notes))
  } else if (mode === "playing") {
    // Disposing the playback piano also cancels the notes that were scheduled ahead.
    self.s.player?.dispose()
    self.s.player = null
    self.s.mode = "idle"
    self.s.editor?.setPlayhead(null)
    setStatus(self, describe(self.s.notes))
  }

  for (const pitch of self.s.lit) highlight(self, pitch, false)
  self.s.lit.clear()
  refreshButtons(self)
}

/**
 * Turns a take into the melody. Notes played during the count-in are kept:
 * when the first note came early, the whole take moves later by whole beats.
 */
function placeTake(take: Note[], maxBeats: number, snap: boolean): { notes: Note[]; shifted: boolean } {
  const earliest = Math.min(...take.map((n) => n.start))
  let shift = 0
  if (earliest < -EARLY_TOLERANCE) shift = Math.ceil(-earliest - 0.001)

  const notes = take
    .map((note) => {
      let start = note.start + shift
      let duration = note.duration
      if (start < 0) {
        duration += start
        start = 0
      }
      if (snap) {
        start = Math.round(start * 4) / 4
        duration = Math.max(Math.round(duration * 4) / 4, 0.25)
      } else {
        start = round(start)
        duration = Math.max(round(duration), 0.05)
      }
      return { ...note, start, duration: Math.min(duration, maxBeats - start) }
    })
    .filter((note) => note.start < maxBeats)
    .sort((a, b) => a.start - b.start || a.pitch - b.pitch)

  return { notes, shifted: shift > 0 }
}

function round(value: number) {
  return Math.round(value * 1000) / 1000
}

// -----------------------------------------------------------------------------
// The animation loop: the count-in, the playhead and the notes while they sound

function loop(self: Self) {
  cancelAnimationFrame(self.s.frame)
  const tick = () => {
    const { mode } = self.s
    if (mode === "count-in" || mode === "recording") tickRecording(self)
    else if (mode === "playing") tickPlayback(self)
    else return
    self.s.frame = requestAnimationFrame(tick)
  }
  tick()
}

function tickRecording(self: Self) {
  const now = beatAt(self, audioNow() - outputLatency())

  if (self.s.mode === "count-in") {
    if (now < 0) {
      setStatus(self, `Get ready... ${Math.ceil(-now)}`)
      return
    }
    self.s.mode = "recording"
  }

  setStatus(self, "Recording... play your melody now.")
  if (now >= self.s.maxBeats) return stop(self)

  self.s.editor?.setPlayhead(now)

  // Redraw the take a few times a second, with the held notes growing.
  const time = performance.now()
  if (time - self.s.lastPreview > 80) {
    self.s.lastPreview = time
    const held = [...self.s.active].map(([pitch, a]) => ({
      pitch,
      start: Math.max(a.start, 0),
      duration: Math.max(now - Math.max(a.start, 0), 0.1),
      velocity: a.velocity,
    }))
    const done = self.s.take.map((n) => (n.start < 0 ? { ...n, duration: n.duration + n.start, start: 0 } : n))
    self.s.editor?.showPreview([...done, ...held].filter((n) => n.duration > 0))
    self.s.editor?.setPlayhead(now)
  }
}

function tickPlayback(self: Self) {
  const now = beatAt(self, audioNow() - outputLatency())
  if (now > self.s.playEnd + 0.1) return stop(self)

  self.s.editor?.setPlayhead(Math.max(now, 0))

  // Light the piano keys of the notes that sound now.
  const sounding = new Set(
    self.s.notes.filter((n) => n.start <= now && now < n.start + n.duration).map((n) => n.pitch)
  )
  for (const pitch of self.s.lit) if (!sounding.has(pitch)) highlight(self, pitch, false)
  for (const pitch of sounding) if (!self.s.lit.has(pitch)) highlight(self, pitch, true)
  self.s.lit = sounding
}

// -----------------------------------------------------------------------------
// Playback and the other buttons

async function play(self: Self) {
  if (self.s.notes.length === 0) return
  await Tone.start()
  prepareSounds(self)

  const b = beat(self)
  const player = createPiano().toDestination()
  self.s.player = player
  self.s.startAt = Tone.now() + 0.05
  self.s.playEnd = self.s.notes.reduce((max, n) => Math.max(max, n.start + n.duration), 0)

  for (const note of self.s.notes) {
    player.triggerAttackRelease(midiToFrequency(note.pitch), note.duration * b, self.s.startAt + note.start * b, note.velocity)
  }

  self.s.mode = "playing"
  self.s.editor?.clearSelection()
  refreshButtons(self)
  setStatus(self, "Playing your melody...")
  loop(self)
}

function undo(self: Self) {
  const previous = self.s.history.pop()
  if (!previous) return
  self.s.notes = previous
  self.s.editor?.clearSelection()
  save(self)
  setStatus(self, `Back to your last take. ${describe(self.s.notes)}`)
  refreshButtons(self)
}

function clear(self: Self) {
  if (self.s.notes.length === 0) return
  self.s.history.push(self.s.notes)
  self.s.notes = []
  save(self)
  setStatus(self, "Melody cleared. Press Undo to bring it back.")
  refreshButtons(self)
}

function save(self: Self) {
  clearTimeout(self.s.saveTimer)
  self.s.saveTimer = window.setTimeout(() => self.pushEvent("save_melody", { notes: self.s.notes }), 250)
}

/** Plays a short note so the person hears the note they picked or moved. */
function preview(self: Self, pitch: number) {
  prepareSounds(self)
  self.s.piano!.triggerAttackRelease(midiToFrequency(pitch), 0.25, audioNow(), 0.7)
}

/** The count-in only matters when the recorder does not wait for the first note. */
function syncOptions(self: Self) {
  const wait = option(self, "waitForNote")
  const countIn = self.el.querySelector("[data-option=countIn]") as HTMLInputElement | null
  if (!countIn) return
  countIn.disabled = wait
  countIn.closest("label")?.classList.toggle("opacity-50", wait)
}

function connectMidi(self: Self) {
  if (!("requestMIDIAccess" in navigator)) {
    const status = $(self, "[data-role=midi-status]")
    if (status) status.textContent = "This browser does not support MIDI keyboards. Try Chrome or Edge."
    return
  }

  navigator.requestMIDIAccess().then(
    (access) => {
      self.s.midiAccess = access
      const attach = () => {
        const names: string[] = []
        access.inputs.forEach((input) => {
          names.push(input.name || "MIDI keyboard")
          input.onmidimessage = (event: MIDIMessageEvent) => {
            const data = event.data
            if (!data) return
            const [status, pitch, velocity] = data
            const command = status & 0xf0
            if (command === 0x90 && velocity > 0) noteOn(self, pitch, velocity / 127)
            else if (command === 0x80 || (command === 0x90 && velocity === 0)) noteOff(self, pitch)
          }
        })
        const status = $(self, "[data-role=midi-status]")
        if (status) {
          status.textContent = names.length
            ? `MIDI keyboard connected: ${names.join(", ")}`
            : "Connect a MIDI keyboard to play with real keys."
        }
      }
      access.onstatechange = attach
      attach()
    },
    () => {
      const status = $(self, "[data-role=midi-status]")
      if (status) status.textContent = "MIDI keyboards are blocked in this browser."
    }
  )
}

export const MelodyRecorder = {
  mounted(this: Self) {
    const self = this
    let notes: Note[] = []
    try {
      notes = JSON.parse(self.el.dataset.notes || "[]")
    } catch (_error) {
      notes = []
    }

    self.s = {
      notes,
      history: [],
      take: [],
      active: new Map(),
      mode: "idle",
      tempo: Number(self.el.dataset.tempo) || 100,
      maxBeats: Number(self.el.dataset.maxBeats) || 64,
      octave: 0,
      startAt: 0,
      playEnd: 0,
      piano: null,
      player: null,
      click: null,
      pressed: new Map(),
      lit: new Set(),
      frame: 0,
      lastPreview: 0,
      midiAccess: null,
      cleanup: [],
      editor: null,
      saveTimer: 0,
    }

    self.s.editor = new NoteEditor({
      el: self.el,
      notes: () => self.s.notes,
      setNotes: (notes) => (self.s.notes = notes),
      maxBeats: () => self.s.maxBeats,
      snap: () => option(self, "snap"),
      busy: () => self.s.mode !== "idle",
      remember: (before) => self.s.history.push(before),
      changed: () => {
        save(self)
        setStatus(self, describe(self.s.notes))
        refreshButtons(self)
      },
      preview: (pitch) => preview(self, pitch),
    })

    setStatus(self, describe(notes))
    refreshButtons(self)
    syncOptions(self)
    self.el.addEventListener("change", (event) => {
      if ((event.target as HTMLElement).matches("[data-option]")) syncOptions(self)
    })

    // Build the sounds on the first touch, so the first note does not wait for them.
    const warmUp = () => prepareSounds(self)
    self.el.addEventListener("pointerdown", warmUp, { once: true })

    const actions: Record<string, () => void> = {
      record: () => record(self),
      stop: () => stop(self),
      play: () => play(self),
      undo: () => undo(self),
      clear: () => clear(self),
    }

    self.el.addEventListener("click", (event) => {
      const target = (event.target as HTMLElement).closest("[data-action]") as HTMLElement | null
      if (target && actions[target.dataset.action!]) actions[target.dataset.action!]()
    })

    const keyboard = $(self, "[data-role=keyboard]")!
    keyboard.addEventListener("pointerdown", (event) => {
      const key = (event.target as HTMLElement).closest("[data-pitch]") as HTMLElement | null
      if (!key) return
      event.preventDefault()
      const pitch = Number(key.dataset.pitch)
      self.s.pressed.set(event.pointerId, pitch)
      noteOn(self, pitch)
    })
    const release = (event: PointerEvent) => {
      const pitch = self.s.pressed.get(event.pointerId)
      if (pitch === undefined) return
      self.s.pressed.delete(event.pointerId)
      noteOff(self, pitch)
    }
    keyboard.addEventListener("pointerup", release)
    keyboard.addEventListener("pointercancel", release)
    keyboard.addEventListener("pointerleave", release)

    // Only fields where people type text keep the keys; toggles and sliders do not.
    const isTextField = (target: HTMLElement) => {
      if (target.tagName === "TEXTAREA" || target.tagName === "SELECT" || target.isContentEditable) return true
      if (target.tagName !== "INPUT") return false
      const type = (target as HTMLInputElement).type
      return !["checkbox", "radio", "range", "button", "submit"].includes(type)
    }
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement
      if (isTextField(target)) return
      // The note editor has shortcuts with Ctrl or Cmd, so it sees the key first.
      if (self.s.editor?.handleKey(event)) return
      if (event.metaKey || event.ctrlKey || event.altKey || event.repeat) return
      const key = event.key.toLowerCase()
      if (key === "z") self.s.octave = Math.max(self.s.octave - 1, -2)
      if (key === "x") self.s.octave = Math.min(self.s.octave + 1, 2)
      if (key in COMPUTER_KEYS) {
        // A focused button would also react to the key, for example Space or Enter.
        event.preventDefault()
        const pitch = 60 + self.s.octave * 12 + COMPUTER_KEYS[key]
        self.s.pressed.set(key, pitch)
        noteOn(self, pitch)
      }
    }
    const onKeyUp = (event: KeyboardEvent) => {
      const key = event.key.toLowerCase()
      const pitch = self.s.pressed.get(key)
      if (pitch === undefined) return
      self.s.pressed.delete(key)
      noteOff(self, pitch)
    }
    window.addEventListener("keydown", onKeyDown)
    window.addEventListener("keyup", onKeyUp)
    self.s.cleanup.push(() => {
      window.removeEventListener("keydown", onKeyDown)
      window.removeEventListener("keyup", onKeyUp)
      self.el.removeEventListener("pointerdown", warmUp)
    })

    connectMidi(self)
  },

  updated(this: Self) {
    this.s.tempo = Number(this.el.dataset.tempo) || this.s.tempo
  },

  destroyed(this: Self) {
    cancelAnimationFrame(this.s.frame)
    if (this.s.saveTimer) {
      clearTimeout(this.s.saveTimer)
      // Send the last edit before the recorder leaves the page.
      try {
        this.pushEvent("save_melody", { notes: this.s.notes })
      } catch (_error) {
        // The page is already gone.
      }
    }
    this.s.cleanup.forEach((fn) => fn())
    this.s.piano?.dispose()
    this.s.player?.dispose()
    this.s.click?.dispose()
    if (this.s.midiAccess) {
      this.s.midiAccess.inputs.forEach((input) => (input.onmidimessage = null))
      this.s.midiAccess.onstatechange = null
    }
  },
}
