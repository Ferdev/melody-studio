import type { Note } from "../audio/types"
import { noteName } from "../audio/theory"

const PX_PER_BEAT = 48
const ROW_HEIGHT = 18
const RULER_HEIGHT = 24
const BEATS_PER_BAR = 4
const EPSILON = 0.001

export type EditKind = "earlier" | "later" | "shorter" | "longer" | "lower" | "higher" | "delete"
export type BarEditKind = "earlier" | "later" | "duplicate" | "insert" | "delete"
type Tool = "pointer" | "box" | "lasso"

export interface EditorHost {
  el: HTMLElement
  notes(): Note[]
  /** Replaces all the notes, for edits that make new notes. */
  setNotes(notes: Note[]): void
  maxBeats(): number
  snap(): boolean
  busy(): boolean
  /** Called before a change, with a copy of the notes, so the change can be undone. */
  remember(before: Note[]): void
  /** Called after a change. */
  changed(): void
  preview(pitch: number): void
}

interface Point {
  x: number
  y: number
}

interface Drag {
  pointerId: number
  mode: "move" | "resize"
  origin: Point
  originals: Map<Note, { start: number; duration: number; pitch: number }>
  before: Note[]
  moved: boolean
}

interface Marquee {
  pointerId: number
  kind: "box" | "lasso" | "tap"
  points: Point[]
  base: Set<Note>
  overlay: SVGSVGElement | null
}

interface BarRange {
  from: number
  to: number
}

interface BarDrag {
  pointerId: number
  anchor: number
  current: number
  /** The bar was already the only picked bar, so a plain tap unpicks it. */
  wasPicked: boolean
}

/**
 * The note editor: notes are blocks on a grid with a bar ruler on top.
 * People pick notes one by one, with a box or with a lasso, and then move,
 * resize, transpose or delete all the picked notes at once. Picking bars in
 * the ruler lets them move, repeat, insert or remove whole bars.
 */
export class NoteEditor {
  private selected = new Set<Note>()
  private bars: BarRange | null = null
  private tool: Tool = "pointer"
  private drag: Drag | null = null
  private marquee: Marquee | null = null
  private barDrag: BarDrag | null = null
  /** Notes shown while recording, in place of the saved notes. */
  private preview: Note[] | null = null
  /** The beat that plays now, or null when nothing plays. */
  private playBeat: number | null = null
  private playhead: HTMLElement | null = null
  private blocks = new Map<Note, HTMLElement>()
  private low = 60
  private high = 72
  private shownBars = 2
  private roll: HTMLElement
  private editor: HTMLElement

  constructor(private host: EditorHost) {
    this.editor = host.el.querySelector("[data-role=editor]") as HTMLElement
    this.roll = host.el.querySelector("[data-role=roll]") as HTMLElement

    this.roll.addEventListener("pointerdown", (event) => this.onPointerDown(event))
    this.roll.addEventListener("pointermove", (event) => this.onPointerMove(event))
    this.roll.addEventListener("pointerup", (event) => this.onPointerUp(event))
    this.roll.addEventListener("pointercancel", (event) => this.onPointerCancel(event))

    host.el.addEventListener("click", (event) => {
      const target = event.target as HTMLElement
      const edit = target.closest("[data-edit]") as HTMLElement | null
      if (edit) return this.edit(edit.dataset.edit as EditKind)
      const barEdit = target.closest("[data-bar-edit]") as HTMLElement | null
      if (barEdit) return this.editBars(barEdit.dataset.barEdit as BarEditKind)
      const tool = target.closest("[data-tool]") as HTMLElement | null
      if (tool) return this.setTool(tool.dataset.tool as Tool)
      const select = target.closest("[data-select]") as HTMLElement | null
      if (select) return select.dataset.select === "all" ? this.selectAll() : this.selectNone()
    })
  }

  hasSelection() {
    return this.selected.size > 0
  }

  clearSelection() {
    this.selected.clear()
    this.bars = null
    this.render()
  }

  selectAll() {
    if (this.host.busy()) return
    this.selected = new Set(this.host.notes())
    this.dropBars()
  }

  selectNone() {
    this.selected.clear()
    this.dropBars()
  }

  /** Unpicks the bars and redraws: the whole grid when bars were picked, else only the notes. */
  private dropBars() {
    if (this.bars) {
      this.bars = null
      this.render()
    } else {
      this.paint()
    }
  }

  setTool(tool: Tool) {
    this.tool = tool
    // Box and lasso need the finger to draw, so the grid stops scrolling with touch.
    this.roll.style.touchAction = tool === "pointer" ? "pan-x" : "none"
    this.roll.style.cursor = tool === "pointer" ? "" : "crosshair"
    this.host.el.querySelectorAll<HTMLElement>("[data-tool]").forEach((button) => {
      const active = button.dataset.tool === tool
      button.classList.toggle("btn-active", active)
      button.setAttribute("aria-pressed", String(active))
    })
  }

  /** Handles the editor's keyboard shortcuts. Returns true when it used the key. */
  handleKey(event: KeyboardEvent): boolean {
    if (this.host.busy() || this.host.notes().length === 0) return false

    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "a") {
      event.preventDefault()
      this.selectAll()
      return true
    }
    if (event.key === "Escape" && (this.selected.size > 0 || this.bars)) {
      this.selectNone()
      return true
    }
    if (this.selected.size === 0) return false

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

  // ---------------------------------------------------------------------------
  // Note edits

  edit(kind: EditKind) {
    if (this.selected.size === 0 || this.host.busy()) return
    const picked = [...this.selected]
    const before = copy(this.host.notes())
    const step = this.step()
    const max = this.host.maxBeats()

    switch (kind) {
      case "earlier":
      case "later": {
        const wanted = kind === "earlier" ? -step : step
        const delta = clamp(wanted, -minOf(picked, (n) => n.start), max - maxOf(picked, (n) => n.start + n.duration))
        if (Math.abs(delta) < EPSILON) return
        picked.forEach((n) => (n.start = round(n.start + delta)))
        break
      }
      case "shorter":
        picked.forEach((n) => (n.duration = Math.max(step, round(n.duration - step))))
        break
      case "longer":
        picked.forEach((n) => (n.duration = Math.min(max - n.start, round(n.duration + step))))
        break
      case "lower":
      case "higher": {
        const wanted = kind === "lower" ? -1 : 1
        const delta = clamp(wanted, 21 - minOf(picked, (n) => n.pitch), 108 - maxOf(picked, (n) => n.pitch))
        if (delta === 0) return
        picked.forEach((n) => (n.pitch += delta))
        this.host.preview(minOf(picked, (n) => n.pitch))
        break
      }
      case "delete":
        this.host.setNotes(this.host.notes().filter((n) => !this.selected.has(n)))
        this.selected.clear()
        this.bars = null
        break
    }

    this.host.remember(before)
    this.commit()
  }

  // ---------------------------------------------------------------------------
  // Bar edits

  editBars(kind: BarEditKind) {
    const range = this.bars
    if (!range || this.host.busy() || !this.canEditBars(kind)) return

    const notes = this.host.notes()
    const before = copy(notes)
    const beat = (bar: number) => bar * BEATS_PER_BAR
    const length = range.to - range.from + 1
    const start = beat(range.from)
    const end = beat(range.to + 1)
    const span = length * BEATS_PER_BAR
    const inside = (n: Note) => n.start >= start - EPSILON && n.start < end - EPSILON
    let next: Note[] = notes
    let selection: BarRange | null = range

    switch (kind) {
      case "delete": {
        next = notes
          .filter((n) => !inside(n))
          .map((n) => {
            if (n.start >= end - EPSILON) n.start = round(n.start - span)
            // A note that starts before the removed bars stops where they started.
            else if (n.start < start && n.start + n.duration > start) n.duration = round(start - n.start)
            return n
          })
        selection = null
        break
      }
      case "earlier": {
        const previous = (n: Note) => n.start >= beat(range.from - 1) - EPSILON && n.start < start - EPSILON
        notes.forEach((n) => {
          if (inside(n)) n.start = round(n.start - BEATS_PER_BAR)
          else if (previous(n)) n.start = round(n.start + span)
        })
        selection = { from: range.from - 1, to: range.to - 1 }
        break
      }
      case "later": {
        const following = (n: Note) => n.start >= end - EPSILON && n.start < beat(range.to + 2) - EPSILON
        notes.forEach((n) => {
          if (inside(n)) n.start = round(n.start + BEATS_PER_BAR)
          else if (following(n)) n.start = round(n.start - span)
        })
        selection = { from: range.from + 1, to: range.to + 1 }
        break
      }
      case "duplicate": {
        const copies = notes.filter(inside).map((n) => ({ ...n, start: round(n.start + span) }))
        notes.forEach((n) => {
          if (n.start >= end - EPSILON) n.start = round(n.start + span)
        })
        next = [...notes, ...copies]
        selection = { from: range.to + 1, to: range.to + length }
        break
      }
      case "insert": {
        notes.forEach((n) => {
          if (n.start >= start - EPSILON) n.start = round(n.start + BEATS_PER_BAR)
        })
        selection = { from: range.from + 1, to: range.to + 1 }
        break
      }
    }

    // Keep every note inside the longest melody.
    const max = this.host.maxBeats()
    next = next
      .filter((n) => n.start < max - EPSILON)
      .map((n) => ({ ...n, duration: Math.min(n.duration, round(max - n.start)) }))

    this.host.setNotes(next)
    this.host.remember(before)
    this.bars = selection
    this.selected = new Set(selection ? this.notesInBars(selection) : [])
    this.commit()
  }

  private canEditBars(kind: BarEditKind): boolean {
    const range = this.bars
    if (!range) return false
    const maxBars = this.host.maxBeats() / BEATS_PER_BAR
    const lastBar = this.lastUsedBar()
    const length = range.to - range.from + 1

    switch (kind) {
      case "earlier":
        return range.from > 0
      case "later":
        return range.to + 1 < maxBars
      case "duplicate":
        return Math.max(lastBar, range.to) + length < maxBars
      case "insert":
        return lastBar + 1 < maxBars
      case "delete":
        return true
    }
  }

  /**
   * Shows the notes of a take while it is recorded, or the saved notes again
   * when `notes` is null.
   */
  showPreview(notes: Note[] | null) {
    this.preview = notes
    this.render()
  }

  /** Moves the playhead to a beat and marks the notes that sound there. Null hides it. */
  setPlayhead(beat: number | null) {
    this.playBeat = beat

    // The grid shows more bars when the playhead goes past them.
    if (beat !== null && Math.floor(beat / BEATS_PER_BAR) >= this.shownBars - 1 && this.shownBars * BEATS_PER_BAR < this.host.maxBeats()) {
      this.render()
      return
    }

    this.placePlayhead()
    this.markSounding()
  }

  private placePlayhead() {
    const head = this.playhead
    if (!head) return
    if (this.playBeat === null) {
      head.classList.add("hidden")
      return
    }

    const x = this.playBeat * PX_PER_BEAT
    head.classList.remove("hidden")
    head.style.left = `${x}px`

    // Keep the playhead in view.
    const scroller = this.roll.parentElement
    if (scroller && (x < scroller.scrollLeft || x > scroller.scrollLeft + scroller.clientWidth - 40)) {
      scroller.scrollLeft = Math.max(0, x - 40)
    }
  }

  private markSounding() {
    const beat = this.playBeat
    for (const [note, block] of this.blocks) {
      const sounding = beat !== null && note.start <= beat + EPSILON && beat < note.start + note.duration
      block.classList.toggle("ring-4", sounding)
      block.classList.toggle("ring-accent", sounding)
      block.classList.toggle("brightness-110", sounding)
      block.classList.toggle("z-20", sounding)
    }
  }

  private lastUsedBar(notes = this.host.notes()) {
    if (notes.length === 0) return -1
    return Math.floor((maxOf(notes, (n) => n.start + n.duration) - EPSILON) / BEATS_PER_BAR)
  }

  private notesInBars(range: BarRange) {
    const start = range.from * BEATS_PER_BAR
    const end = (range.to + 1) * BEATS_PER_BAR
    return this.host.notes().filter((n) => n.start >= start - EPSILON && n.start < end - EPSILON)
  }

  // ---------------------------------------------------------------------------
  // Drawing

  render() {
    const recording = this.preview !== null
    const notes = this.preview ?? this.host.notes()
    this.editor.classList.toggle("hidden", notes.length === 0 && !recording)
    const saved = this.host.notes()
    for (const note of [...this.selected]) if (!saved.includes(note)) this.selected.delete(note)

    const pitches = notes.map((n) => n.pitch)
    this.low = Math.min(...pitches, 60) - 2
    this.high = Math.max(...pitches, this.low + 14) + 2

    const maxBars = this.host.maxBeats() / BEATS_PER_BAR
    const playBar = this.playBeat === null ? 0 : Math.floor(this.playBeat / BEATS_PER_BAR)
    this.shownBars = Math.min(
      maxBars,
      Math.max(2, this.lastUsedBar(notes) + 2, (this.bars?.to ?? 0) + 2, playBar + 2)
    )
    if (this.bars && this.bars.to >= this.shownBars) this.bars = null

    const width = this.shownBars * BEATS_PER_BAR * PX_PER_BEAT
    const rows = this.high - this.low + 1

    this.roll.style.width = `${width}px`
    this.roll.style.height = `${RULER_HEIGHT + rows * ROW_HEIGHT}px`
    this.roll.style.backgroundImage = [
      "linear-gradient(to right, rgb(0 0 0 / 0.18) 1px, transparent 1px)",
      "linear-gradient(to right, rgb(0 0 0 / 0.06) 1px, transparent 1px)",
    ].join(", ")
    this.roll.style.backgroundSize = `${PX_PER_BEAT * BEATS_PER_BAR}px 100%, ${PX_PER_BEAT}px 100%`
    this.roll.replaceChildren()
    this.blocks.clear()

    // Bar ruler and the tint of the picked bars.
    for (let bar = 0; bar < this.shownBars; bar++) {
      const picked = this.bars !== null && bar >= this.bars.from && bar <= this.bars.to
      const cell = document.createElement("button")
      cell.type = "button"
      cell.dataset.bar = String(bar)
      cell.setAttribute("aria-label", `Bar ${bar + 1}`)
      cell.setAttribute("aria-pressed", String(picked))
      cell.className = [
        "absolute top-0 border-b border-l border-base-300 text-left pl-1.5 text-xs font-bold",
        picked ? "bg-secondary text-secondary-content" : "bg-base-100/80 text-base-content/60 hover:bg-secondary/20",
      ].join(" ")
      cell.style.left = `${bar * BEATS_PER_BAR * PX_PER_BEAT}px`
      cell.style.width = `${BEATS_PER_BAR * PX_PER_BEAT}px`
      cell.style.height = `${RULER_HEIGHT}px`
      cell.style.touchAction = "none"
      cell.textContent = String(bar + 1)
      this.roll.appendChild(cell)

      if (picked) {
        const tint = document.createElement("div")
        tint.className = "pointer-events-none absolute bg-secondary/10"
        tint.style.left = cell.style.left
        tint.style.width = cell.style.width
        tint.style.top = `${RULER_HEIGHT}px`
        tint.style.bottom = "0"
        this.roll.appendChild(tint)
      }
    }

    notes.forEach((note, index) => {
      const block = document.createElement("div")
      block.dataset.note = String(index)
      block.setAttribute("role", "button")
      block.setAttribute("aria-label", `${noteName(note.pitch)} at beat ${formatBeat(note.start)}`)
      block.style.touchAction = "none"
      block.textContent = note.duration * PX_PER_BEAT > 26 ? noteName(note.pitch) : ""

      const handle = document.createElement("div")
      handle.dataset.handle = "true"
      handle.className = "absolute inset-y-0 right-0 w-2.5 cursor-ew-resize bg-black/15"
      block.appendChild(handle)

      this.position(block, note)
      this.blocks.set(note, block)
      this.roll.appendChild(block)
    })

    const head = document.createElement("div")
    head.dataset.role = "playhead"
    head.className = "pointer-events-none absolute top-0 bottom-0 z-30 hidden w-0.5 -translate-x-1/2 bg-accent shadow"
    this.roll.appendChild(head)
    this.playhead = head

    this.paint()
    this.placePlayhead()
  }

  /** Updates the look of the picked notes and the buttons, without rebuilding the grid. */
  private paint() {
    const recording = this.preview !== null
    for (const [note, block] of this.blocks) {
      const picked = !recording && this.selected.has(note)
      const look = recording
        ? "bg-primary/70 text-primary-content"
        : picked
          ? "cursor-grab bg-secondary text-secondary-content ring-2 ring-secondary/40 z-10"
          : "cursor-grab bg-primary text-primary-content"
      block.className = `absolute flex items-center overflow-hidden rounded-md pl-1.5 text-[11px] font-bold leading-none shadow-sm ${look}`
    }
    this.markSounding()

    const busy = this.host.busy()
    const count = this.selected.size
    const label = this.host.el.querySelector("[data-role=selection]")
    if (label) label.textContent = this.describeSelection()

    this.host.el.querySelectorAll<HTMLButtonElement>("[data-edit]").forEach((button) => {
      button.disabled = count === 0 || busy
    })
    const none = this.host.el.querySelector<HTMLButtonElement>("[data-select=none]")
    if (none) none.disabled = count === 0 && !this.bars

    const tools = this.host.el.querySelector("[data-role=bar-tools]") as HTMLElement | null
    if (tools) {
      tools.classList.toggle("hidden", !this.bars)
      tools.classList.toggle("flex", !!this.bars)
    }
    if (this.bars) {
      const { from, to } = this.bars
      const barLabel = this.host.el.querySelector("[data-role=bar-label]")
      if (barLabel) barLabel.textContent = from === to ? `Bar ${from + 1}` : `Bars ${from + 1} to ${to + 1}`

      this.host.el.querySelectorAll<HTMLButtonElement>("[data-bar-edit]").forEach((button) => {
        button.disabled = busy || !this.canEditBars(button.dataset.barEdit as BarEditKind)
      })

      const hint = this.host.el.querySelector("[data-role=bar-hint]")
      if (hint) {
        const full = !this.canEditBars("duplicate") || !this.canEditBars("insert")
        hint.textContent = full
          ? `A melody can be ${this.host.maxBeats() / BEATS_PER_BAR} bars long at most, so some bar tools are off.`
          : "To pick several bars, drag across the bar numbers, or hold Shift and tap another one."
      }
    }
  }

  private describeSelection() {
    const notes = [...this.selected]
    if (notes.length === 0) {
      return this.bars ? "There are no notes in the picked bars." : "No notes picked yet."
    }
    if (notes.length === 1) {
      const note = notes[0]
      return `${noteName(note.pitch)}, starts on beat ${formatBeat(note.start)}, lasts ${formatLength(note.duration)}`
    }
    return `${notes.length} notes picked`
  }

  private position(block: HTMLElement, note: Note) {
    block.style.left = `${note.start * PX_PER_BEAT}px`
    block.style.width = `${Math.max(note.duration * PX_PER_BEAT - 1, 6)}px`
    block.style.top = `${RULER_HEIGHT + (this.high - note.pitch) * ROW_HEIGHT}px`
    block.style.height = `${ROW_HEIGHT - 1}px`
  }

  // ---------------------------------------------------------------------------
  // Pointer

  private point(event: PointerEvent): Point {
    const rect = this.roll.getBoundingClientRect()
    return { x: event.clientX - rect.left, y: event.clientY - rect.top }
  }

  private onPointerDown(event: PointerEvent) {
    if (this.host.busy() || event.button > 0) return
    const target = event.target as HTMLElement
    const additive = event.shiftKey || event.metaKey || event.ctrlKey

    const barCell = target.closest("[data-bar]") as HTMLElement | null
    if (barCell) {
      event.preventDefault()
      const bar = Number(barCell.dataset.bar)
      if (event.shiftKey && this.bars) {
        this.pickBars({ from: Math.min(this.bars.from, bar), to: Math.max(this.bars.to, bar) })
        return
      }
      const wasPicked = this.bars?.from === bar && this.bars?.to === bar
      this.barDrag = { pointerId: event.pointerId, anchor: bar, current: bar, wasPicked }
      this.roll.setPointerCapture(event.pointerId)
      if (!wasPicked) this.pickBars({ from: bar, to: bar })
      return
    }

    const block = target.closest("[data-note]") as HTMLElement | null
    if (block && this.tool === "pointer") {
      event.preventDefault()
      const note = this.host.notes()[Number(block.dataset.note)]
      if (!note) return

      if (additive) {
        if (this.selected.has(note)) this.selected.delete(note)
        else this.selected.add(note)
        this.dropBars()
        return
      }

      if (!this.selected.has(note)) {
        this.selected = new Set([note])
        this.dropBars()
      }
      this.host.preview(note.pitch)

      this.drag = {
        pointerId: event.pointerId,
        mode: target.closest("[data-handle]") ? "resize" : "move",
        origin: this.point(event),
        originals: new Map([...this.selected].map((n) => [n, { start: n.start, duration: n.duration, pitch: n.pitch }])),
        before: copy(this.host.notes()),
        moved: false,
      }
      this.roll.setPointerCapture(event.pointerId)
      return
    }

    // A drag on an empty spot (or any drag with the box or lasso tool) picks notes.
    // With the pick tool, a finger on an empty spot scrolls the grid instead.
    const kind = this.tool === "lasso" ? "lasso" : this.tool === "pointer" && event.pointerType === "touch" ? "tap" : "box"
    if (kind !== "tap") event.preventDefault()

    this.marquee = {
      pointerId: event.pointerId,
      kind,
      points: [this.point(event)],
      base: additive ? new Set(this.selected) : new Set(),
      overlay: null,
    }
    if (kind !== "tap") this.roll.setPointerCapture(event.pointerId)
  }

  private onPointerMove(event: PointerEvent) {
    if (this.drag && event.pointerId === this.drag.pointerId) return this.moveDrag(event, this.drag)

    const barDrag = this.barDrag
    if (barDrag && event.pointerId === barDrag.pointerId) {
      // Dragging across the bar numbers picks a range of bars.
      const bar = clamp(Math.floor(this.point(event).x / (BEATS_PER_BAR * PX_PER_BEAT)), 0, this.shownBars - 1)
      if (bar !== barDrag.current) {
        barDrag.current = bar
        this.pickBars({ from: Math.min(barDrag.anchor, bar), to: Math.max(barDrag.anchor, bar) })
      }
      return
    }

    const marquee = this.marquee
    if (!marquee || event.pointerId !== marquee.pointerId || marquee.kind === "tap") return

    const point = this.point(event)
    if (marquee.kind === "box") marquee.points = [marquee.points[0], point]
    else marquee.points.push(point)

    this.selected = new Set([...marquee.base, ...this.notesInside(marquee)])
    this.dropBars()
    this.drawMarquee(marquee)
  }

  private onPointerUp(event: PointerEvent) {
    const barDrag = this.barDrag
    if (barDrag && event.pointerId === barDrag.pointerId) {
      this.barDrag = null
      this.release(event)
      // A tap on the only picked bar unpicks it.
      if (barDrag.wasPicked && barDrag.current === barDrag.anchor) this.pickBars(null)
      return
    }

    const drag = this.drag
    if (drag && event.pointerId === drag.pointerId) {
      this.drag = null
      this.release(event)
      if (drag.moved) {
        this.host.remember(drag.before)
        this.commit()
      }
      return
    }

    const marquee = this.marquee
    if (marquee && event.pointerId === marquee.pointerId) {
      this.marquee = null
      this.release(event)
      marquee.overlay?.remove()

      // A lasso can end where it started, so measure the whole shape.
      const points = marquee.kind === "tap" ? [marquee.points[0], this.point(event)] : marquee.points
      const xs = points.map((p) => p.x)
      const ys = points.map((p) => p.y)
      const tiny = Math.max(...xs) - Math.min(...xs) < 4 && Math.max(...ys) - Math.min(...ys) < 4
      // A tap on an empty spot picks nothing.
      if (tiny && marquee.base.size === 0) this.selectNone()
    }
  }

  private onPointerCancel(event: PointerEvent) {
    if (this.barDrag && event.pointerId === this.barDrag.pointerId) this.barDrag = null
    const drag = this.drag
    if (drag && event.pointerId === drag.pointerId) {
      // Put the notes back where they were.
      for (const [note, original] of drag.originals) Object.assign(note, original)
      this.drag = null
      this.render()
    }
    if (this.marquee && event.pointerId === this.marquee.pointerId) {
      this.marquee.overlay?.remove()
      this.marquee = null
    }
  }

  private release(event: PointerEvent) {
    if (this.roll.hasPointerCapture(event.pointerId)) this.roll.releasePointerCapture(event.pointerId)
  }

  private moveDrag(event: PointerEvent, drag: Drag) {
    const step = this.step()
    const max = this.host.maxBeats()
    const point = this.point(event)
    const picked = [...drag.originals.entries()]
    const quantize = (value: number) => round(Math.round(value / step) * step)
    const dx = quantize((point.x - drag.origin.x) / PX_PER_BEAT)

    if (drag.mode === "resize") {
      for (const [note, original] of picked) {
        note.duration = clamp(round(original.duration + dx), step, max - note.start)
      }
    } else {
      const earliest = minOf(picked, ([, o]) => o.start)
      const latest = maxOf(picked, ([, o]) => o.start + o.duration)
      const lowest = minOf(picked, ([, o]) => o.pitch)
      const highest = maxOf(picked, ([, o]) => o.pitch)
      const dt = clamp(dx, -earliest, max - latest)
      const dp = clamp(-Math.round((point.y - drag.origin.y) / ROW_HEIGHT), this.low - lowest, this.high - highest)

      const pitchChanged = picked.some(([note, o]) => note.pitch !== o.pitch + dp)
      for (const [note, original] of picked) {
        note.start = round(original.start + dt)
        note.pitch = original.pitch + dp
      }
      if (pitchChanged) this.host.preview(lowest + dp)
    }

    drag.moved = picked.some(([n, o]) => n.start !== o.start || n.duration !== o.duration || n.pitch !== o.pitch)
    for (const [note] of picked) {
      const block = this.blocks.get(note)
      if (block) this.position(block, note)
    }
    this.paint()
  }

  private pickBars(range: BarRange | null) {
    this.bars = range
    this.selected = new Set(range ? this.notesInBars(range) : [])
    this.render()
  }

  private drawMarquee(marquee: Marquee) {
    const ns = "http://www.w3.org/2000/svg"
    // A redraw of the grid removes the overlay, so make it again when needed.
    if (!marquee.overlay || !marquee.overlay.isConnected) {
      const svg = document.createElementNS(ns, "svg")
      svg.setAttribute("class", "pointer-events-none absolute inset-0 z-20 h-full w-full overflow-visible")
      this.roll.appendChild(svg)
      marquee.overlay = svg
    }

    const svg = marquee.overlay
    svg.replaceChildren()
    const shape = document.createElementNS(ns, "polygon")
    shape.setAttribute("points", this.outline(marquee).map((p) => `${p.x},${p.y}`).join(" "))
    shape.setAttribute("fill", "rgb(14 165 233 / 0.12)")
    shape.setAttribute("stroke", "rgb(14 116 144)")
    shape.setAttribute("stroke-width", "1.5")
    shape.setAttribute("stroke-dasharray", "4 3")
    svg.appendChild(shape)
  }

  /** The shape that the person drew, as a polygon. */
  private outline(marquee: Marquee): Point[] {
    if (marquee.kind === "lasso") return marquee.points
    const [a, b] = [marquee.points[0], marquee.points[marquee.points.length - 1]]
    return [
      { x: a.x, y: a.y },
      { x: b.x, y: a.y },
      { x: b.x, y: b.y },
      { x: a.x, y: b.y },
    ]
  }

  private notesInside(marquee: Marquee): Note[] {
    const notes = this.host.notes()

    if (marquee.kind === "box") {
      const [a, b] = [marquee.points[0], marquee.points[marquee.points.length - 1]]
      const left = Math.min(a.x, b.x)
      const right = Math.max(a.x, b.x)
      const top = Math.min(a.y, b.y)
      const bottom = Math.max(a.y, b.y)
      return notes.filter((note) => {
        const box = this.noteBox(note)
        return box.left < right && box.right > left && box.top < bottom && box.bottom > top
      })
    }

    const polygon = marquee.points
    if (polygon.length < 3) return []
    return notes.filter((note) => {
      const box = this.noteBox(note)
      const middle = (box.top + box.bottom) / 2
      const samples = [box.left + 3, (box.left + box.right) / 2, box.right - 3]
      return samples.some((x) => insidePolygon({ x, y: middle }, polygon))
    })
  }

  private noteBox(note: Note) {
    const left = note.start * PX_PER_BEAT
    const top = RULER_HEIGHT + (this.high - note.pitch) * ROW_HEIGHT
    return { left, right: left + Math.max(note.duration * PX_PER_BEAT, 6), top, bottom: top + ROW_HEIGHT }
  }

  // ---------------------------------------------------------------------------

  private commit() {
    this.host.notes().sort((a, b) => a.start - b.start || a.pitch - b.pitch)
    this.render()
    this.host.changed()
  }

  private step() {
    return this.host.snap() ? 0.25 : 0.05
  }
}

function insidePolygon(point: Point, polygon: Point[]): boolean {
  let inside = false
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[i]
    const b = polygon[j]
    const crosses = a.y > point.y !== b.y > point.y && point.x < ((b.x - a.x) * (point.y - a.y)) / (b.y - a.y) + a.x
    if (crosses) inside = !inside
  }
  return inside
}

function copy(notes: Note[]): Note[] {
  return notes.map((note) => ({ ...note }))
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max)
}

function minOf<T>(items: T[], value: (item: T) => number) {
  return Math.min(...items.map(value))
}

function maxOf<T>(items: T[], value: (item: T) => number) {
  return Math.max(...items.map(value))
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
