import type { Note } from "../audio/types"
import { noteName } from "../audio/theory"

const PX_PER_BEAT = 48
const ROW_HEIGHT = 18

export type EditKind = "earlier" | "later" | "shorter" | "longer" | "lower" | "higher" | "delete"

export interface EditorHost {
  el: HTMLElement
  notes(): Note[]
  maxBeats(): number
  snap(): boolean
  busy(): boolean
  /** Called before a change, with a copy of the notes, so the change can be undone. */
  remember(before: Note[]): void
  /** Called after a change. */
  changed(): void
  preview(pitch: number): void
}

interface Drag {
  pointerId: number
  mode: "move" | "resize"
  x0: number
  y0: number
  start: number
  duration: number
  pitch: number
  before: Note[]
  moved: boolean
  block: HTMLElement
}

/**
 * A small note editor: the notes are blocks on a grid. Each block can be
 * picked, dragged in time or pitch, resized, or changed with buttons.
 */
export class NoteEditor {
  private selected: Note | null = null
  private drag: Drag | null = null
  private low = 60
  private high = 72
  private roll: HTMLElement
  private editor: HTMLElement

  constructor(private host: EditorHost) {
    this.editor = host.el.querySelector("[data-role=editor]") as HTMLElement
    this.roll = host.el.querySelector("[data-role=roll]") as HTMLElement

    this.roll.addEventListener("pointerdown", (event) => this.onPointerDown(event))
    this.roll.addEventListener("pointermove", (event) => this.onPointerMove(event))
    this.roll.addEventListener("pointerup", (event) => this.onPointerUp(event))
    this.roll.addEventListener("pointercancel", (event) => this.onPointerUp(event))

    host.el.addEventListener("click", (event) => {
      const button = (event.target as HTMLElement).closest("[data-edit]") as HTMLElement | null
      if (button) this.edit(button.dataset.edit as EditKind)
    })
  }

  hasSelection() {
    return this.selected !== null
  }

  clearSelection() {
    this.selected = null
    this.render()
  }

  /** Handles the arrow and Delete keys. Returns true when it used the key. */
  handleKey(event: KeyboardEvent): boolean {
    if (!this.selected || this.host.busy()) return false
    const keys: Record<string, EditKind> = {
      ArrowLeft: event.shiftKey ? "shorter" : "earlier",
      ArrowRight: event.shiftKey ? "longer" : "later",
      ArrowUp: "higher",
      ArrowDown: "lower",
      Delete: "delete",
      Backspace: "delete",
    }
    const kind = keys[event.key]
    if (!kind) return false
    event.preventDefault()
    this.edit(kind)
    return true
  }

  edit(kind: EditKind) {
    const note = this.selected
    if (!note || this.host.busy()) return
    const notes = this.host.notes()
    const before = copy(notes)
    const step = this.step()
    const max = this.host.maxBeats()

    switch (kind) {
      case "earlier":
        note.start = Math.max(0, round(note.start - step))
        break
      case "later":
        note.start = Math.min(max - note.duration, round(note.start + step))
        break
      case "shorter":
        note.duration = Math.max(step, round(note.duration - step))
        break
      case "longer":
        note.duration = Math.min(max - note.start, round(note.duration + step))
        break
      case "lower":
        note.pitch = Math.max(21, note.pitch - 1)
        this.host.preview(note.pitch)
        break
      case "higher":
        note.pitch = Math.min(108, note.pitch + 1)
        this.host.preview(note.pitch)
        break
      case "delete":
        notes.splice(notes.indexOf(note), 1)
        this.selected = null
        break
    }

    this.host.remember(before)
    this.commit()
  }

  render() {
    const notes = this.host.notes()
    this.editor.classList.toggle("hidden", notes.length === 0)
    if (this.selected && !notes.includes(this.selected)) this.selected = null

    const pitches = notes.map((n) => n.pitch)
    this.low = Math.min(...pitches, 60) - 2
    this.high = Math.max(...pitches, this.low + 14) + 2

    const lastBeat = notes.reduce((max, n) => Math.max(max, n.start + n.duration), 0)
    const beats = Math.min(this.host.maxBeats(), Math.max(8, Math.ceil(lastBeat / 4) * 4 + 4))
    const rows = this.high - this.low + 1

    this.roll.style.width = `${beats * PX_PER_BEAT}px`
    this.roll.style.height = `${rows * ROW_HEIGHT}px`
    this.roll.style.backgroundImage = [
      "linear-gradient(to right, rgb(0 0 0 / 0.16) 1px, transparent 1px)",
      "linear-gradient(to right, rgb(0 0 0 / 0.06) 1px, transparent 1px)",
    ].join(", ")
    this.roll.style.backgroundSize = `${PX_PER_BEAT * 4}px 100%, ${PX_PER_BEAT}px 100%`
    this.roll.replaceChildren()

    notes.forEach((note, index) => {
      const block = document.createElement("div")
      block.dataset.note = String(index)
      block.setAttribute("role", "button")
      block.setAttribute("aria-label", `${noteName(note.pitch)} at beat ${formatBeat(note.start)}`)
      block.className = [
        "absolute flex cursor-grab items-center overflow-hidden rounded-md pl-1.5 text-[11px] font-bold leading-none shadow-sm",
        note === this.selected ? "bg-secondary text-secondary-content ring-2 ring-secondary/40 z-10" : "bg-primary text-primary-content",
      ].join(" ")
      block.style.touchAction = "none"
      this.position(block, note)
      block.textContent = note.duration * PX_PER_BEAT > 26 ? noteName(note.pitch) : ""

      const handle = document.createElement("div")
      handle.dataset.handle = "true"
      handle.className = "absolute inset-y-0 right-0 w-2.5 cursor-ew-resize bg-black/15"
      block.appendChild(handle)

      this.roll.appendChild(block)
    })

    this.renderSelection()
  }

  private position(block: HTMLElement, note: Note) {
    block.style.left = `${note.start * PX_PER_BEAT}px`
    block.style.width = `${Math.max(note.duration * PX_PER_BEAT - 1, 6)}px`
    block.style.top = `${(this.high - note.pitch) * ROW_HEIGHT}px`
    block.style.height = `${ROW_HEIGHT - 1}px`
  }

  private renderSelection() {
    const label = this.host.el.querySelector("[data-role=selection]")
    const note = this.selected
    if (label) {
      label.textContent = note
        ? `${noteName(note.pitch)}, starts on beat ${formatBeat(note.start)}, lasts ${formatLength(note.duration)}`
        : "No note picked yet."
    }
    this.host.el.querySelectorAll<HTMLButtonElement>("[data-edit]").forEach((button) => {
      button.disabled = !note || this.host.busy()
    })
  }

  private onPointerDown(event: PointerEvent) {
    if (this.host.busy()) return
    const target = event.target as HTMLElement
    const block = target.closest("[data-note]") as HTMLElement | null

    if (!block) {
      this.selected = null
      this.render()
      return
    }

    event.preventDefault()
    const note = this.host.notes()[Number(block.dataset.note)]
    if (!note) return

    if (this.selected !== note) {
      this.selected = note
      this.render()
    }
    this.host.preview(note.pitch)

    // render() made new blocks, so find the block of the picked note again.
    const current = this.roll.querySelector(`[data-note="${this.host.notes().indexOf(note)}"]`) as HTMLElement
    this.drag = {
      pointerId: event.pointerId,
      mode: target.closest("[data-handle]") ? "resize" : "move",
      x0: event.clientX,
      y0: event.clientY,
      start: note.start,
      duration: note.duration,
      pitch: note.pitch,
      before: copy(this.host.notes()),
      moved: false,
      block: current,
    }
    this.roll.setPointerCapture(event.pointerId)
  }

  private onPointerMove(event: PointerEvent) {
    const drag = this.drag
    const note = this.selected
    if (!drag || !note || event.pointerId !== drag.pointerId) return

    const step = this.step()
    const max = this.host.maxBeats()
    const quantize = (value: number) => round(Math.round(value / step) * step)
    const dx = (event.clientX - drag.x0) / PX_PER_BEAT

    if (drag.mode === "resize") {
      note.duration = clamp(quantize(drag.duration + dx), step, max - note.start)
    } else {
      note.start = clamp(quantize(drag.start + dx), 0, max - note.duration)
      const pitch = clamp(drag.pitch - Math.round((event.clientY - drag.y0) / ROW_HEIGHT), this.low, this.high)
      if (pitch !== note.pitch) {
        note.pitch = pitch
        this.host.preview(pitch)
      }
    }

    const moved = note.start !== drag.start || note.duration !== drag.duration || note.pitch !== drag.pitch
    if (moved) {
      drag.moved = true
      this.position(drag.block, note)
      this.renderSelection()
    }
  }

  private onPointerUp(event: PointerEvent) {
    const drag = this.drag
    if (!drag || event.pointerId !== drag.pointerId) return
    this.drag = null
    if (this.roll.hasPointerCapture(event.pointerId)) this.roll.releasePointerCapture(event.pointerId)

    if (drag.moved) {
      this.host.remember(drag.before)
      this.commit()
    }
  }

  private commit() {
    this.host.notes().sort((a, b) => a.start - b.start || a.pitch - b.pitch)
    this.render()
    this.host.changed()
  }

  private step() {
    return this.host.snap() ? 0.25 : 0.05
  }
}

function copy(notes: Note[]): Note[] {
  return notes.map((note) => ({ ...note }))
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max)
}

function round(value: number) {
  return Math.round(value * 1000) / 1000
}

function formatBeat(start: number) {
  return String(round(start + 1))
}

function formatLength(duration: number) {
  const value = round(duration)
  return `${value} ${value === 1 ? "beat" : "beats"}`
}
