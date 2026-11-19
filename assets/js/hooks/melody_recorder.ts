import * as Tone from "tone"
import type { HookContext, Note } from "../audio/types"
import { createClick, createPiano } from "../audio/instruments"
import { midiToFrequency } from "../audio/theory"
import { NoteEditor } from "./note_editor"

const COMPUTER_KEYS: Record<string, number> = {
  a: 0, w: 1, s: 2, e: 3, d: 4, f: 5, t: 6, g: 7, y: 8, h: 9, u: 10, j: 11,
  k: 12, o: 13, l: 14, p: 15, ";": 16,
}

type Mode = "idle" | "count-in" | "recording" | "playing"

interface State {
  notes: Note[]
  history: Note[][]
  take: Note[]
  active: Map<number, { start: number; velocity: number }>
  mode: Mode
  tempo: number
  maxBeats: number
  octave: number
  startAt: number
  piano: Tone.PolySynth | null
  click: Tone.Synth | null
  pressed: Map<string | number, number>
  timers: number[]
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
  if (status) status.textContent = text
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

async function ensureAudio(self: Self) {
  await Tone.start()
  if (!self.s.piano) self.s.piano = createPiano().toDestination()
  if (!self.s.click) self.s.click = createClick().toDestination()
}

function nowBeats(self: Self) {
  return (Tone.now() - self.s.startAt) / beat(self)
}

async function noteOn(self: Self, pitch: number, velocity = 0.8) {
  await ensureAudio(self)
  self.s.piano!.triggerAttack(midiToFrequency(pitch), Tone.now(), velocity)
  highlight(self, pitch, true)

  if (self.s.mode === "recording" || self.s.mode === "count-in") {
    self.s.active.set(pitch, { start: nowBeats(self), velocity })
  }
}

function noteOff(self: Self, pitch: number) {
  self.s.piano?.triggerRelease(midiToFrequency(pitch), Tone.now())
  highlight(self, pitch, false)

  const active = self.s.active.get(pitch)
  if (active) {
    self.s.active.delete(pitch)
    finishNote(self, pitch, active, nowBeats(self))
  }
}

function finishNote(self: Self, pitch: number, active: { start: number; velocity: number }, end: number) {
  let start = active.start
  // A note pressed just before the first beat counts as on the first beat.
  if (start < 0 && start > -0.5) start = 0
  if (start < 0 || start >= self.s.maxBeats) return
  const duration = Math.max(Math.min(end, self.s.maxBeats) - start, 0.1)
  self.s.take.push({ pitch, start, duration, velocity: active.velocity })
}

function tidy(notes: Note[], snap: boolean): Note[] {
  return notes
    .map((note) => {
      if (!snap) return { ...note, start: round(note.start), duration: round(note.duration) }
      const start = Math.round(note.start * 4) / 4
      const duration = Math.max(Math.round(note.duration * 4) / 4, 0.25)
      return { ...note, start, duration }
    })
    .sort((a, b) => a.start - b.start || a.pitch - b.pitch)
}

function round(value: number) {
  return Math.round(value * 1000) / 1000
}

function clearTimers(self: Self) {
  self.s.timers.forEach((timer) => clearTimeout(timer))
  self.s.timers = []
}

async function record(self: Self) {
  await ensureAudio(self)
  const countIn = option(self, "countIn") ? 4 : 0
  const metronome = option(self, "metronome")
  const b = beat(self)

  self.s.take = []
  self.s.active.clear()
  self.s.startAt = Tone.now() + 0.15 + countIn * b
  self.s.mode = countIn > 0 ? "count-in" : "recording"
  refreshButtons(self)

  // Metronome clicks: the count-in, then every beat while recording.
  const totalBeats = countIn + self.s.maxBeats
  for (let i = 0; i < totalBeats; i++) {
    const beatIndex = i - countIn
    if (!metronome && beatIndex >= 0) break
    const time = self.s.startAt + beatIndex * b
    const strong = ((beatIndex % 4) + 4) % 4 === 0
    self.s.click!.triggerAttackRelease(strong ? "C6" : "G5", 0.03, time, strong ? 0.9 : 0.5)
    if (i > 64) break
  }

  for (let i = 0; i < countIn; i++) {
    const delay = (self.s.startAt - countIn * b + i * b - Tone.now()) * 1000
    self.s.timers.push(window.setTimeout(() => setStatus(self, `Get ready... ${countIn - i}`), Math.max(delay, 0)))
  }

  const recordDelay = Math.max((self.s.startAt - Tone.now()) * 1000, 0)
  self.s.timers.push(
    window.setTimeout(() => {
      if (self.s.mode === "count-in") self.s.mode = "recording"
      setStatus(self, "Recording... play your melody now.")
    }, recordDelay)
  )

  // Stop on its own at the longest melody length.
  self.s.timers.push(window.setTimeout(() => stop(self), recordDelay + self.s.maxBeats * b * 1000))
}

function stop(self: Self) {
  const { mode } = self.s
  clearTimers(self)
  self.s.click?.dispose()
  self.s.click = null

  if (mode === "recording" || mode === "count-in") {
    const end = nowBeats(self)
    for (const [pitch, active] of self.s.active) finishNote(self, pitch, active, end)
    self.s.active.clear()
    self.s.mode = "idle"

    if (self.s.take.length === 0) {
      setStatus(self, "We did not hear any notes. Press Record and try again.")
    } else {
      self.s.history.push(self.s.notes)
      self.s.notes = tidy(self.s.take, option(self, "snap"))
      save(self)
      setStatus(self, `Nice! ${describe(self.s.notes)}`)
    }
  } else if (mode === "playing") {
    // Disposing the piano also cancels the notes that were scheduled ahead.
    self.s.piano?.dispose()
    self.s.piano = null
    self.el.querySelectorAll(".is-down").forEach((key) => key.classList.remove("is-down"))
    self.s.mode = "idle"
    setStatus(self, describe(self.s.notes))
  }

  refreshButtons(self)
}

async function play(self: Self) {
  if (self.s.notes.length === 0) return
  await ensureAudio(self)
  const b = beat(self)
  const start = Tone.now() + 0.1
  self.s.mode = "playing"
  refreshButtons(self)
  setStatus(self, "Playing your melody...")

  for (const note of self.s.notes) {
    self.s.piano!.triggerAttackRelease(midiToFrequency(note.pitch), note.duration * b, start + note.start * b, note.velocity)
    self.s.timers.push(
      window.setTimeout(() => highlight(self, note.pitch, true), (start + note.start * b - Tone.now()) * 1000),
      window.setTimeout(
        () => highlight(self, note.pitch, false),
        (start + (note.start + note.duration) * b - Tone.now()) * 1000
      )
    )
  }

  const end = self.s.notes.reduce((max, n) => Math.max(max, n.start + n.duration), 0)
  self.s.timers.push(window.setTimeout(() => stop(self), (end * b + 0.4) * 1000))
}

function undo(self: Self) {
  const previous = self.s.history.pop()
  if (!previous) return
  self.s.notes = previous
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
async function preview(self: Self, pitch: number) {
  await ensureAudio(self)
  self.s.piano!.triggerAttackRelease(midiToFrequency(pitch), 0.25, Tone.now(), 0.7)
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
      piano: null,
      click: null,
      pressed: new Map(),
      timers: [],
      midiAccess: null,
      cleanup: [],
      editor: null,
      saveTimer: 0,
    }

    self.s.editor = new NoteEditor({
      el: self.el,
      notes: () => self.s.notes,
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

    const typing = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement
      return ["INPUT", "SELECT", "TEXTAREA"].includes(target.tagName) || event.metaKey || event.ctrlKey || event.altKey
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (typing(event)) return
      if (self.s.editor?.handleKey(event)) return
      if (event.repeat) return
      const key = event.key.toLowerCase()
      if (key === "z") self.s.octave = Math.max(self.s.octave - 1, -2)
      if (key === "x") self.s.octave = Math.min(self.s.octave + 1, 2)
      if (key in COMPUTER_KEYS) {
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
    })

    connectMidi(self)
  },

  updated(this: Self) {
    this.s.tempo = Number(this.el.dataset.tempo) || this.s.tempo
  },

  destroyed(this: Self) {
    clearTimers(this)
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
    this.s.click?.dispose()
    if (this.s.midiAccess) {
      this.s.midiAccess.inputs.forEach((input) => (input.onmidimessage = null))
      this.s.midiAccess.onstatechange = null
    }
  },
}
