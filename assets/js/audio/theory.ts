const NOTE_INDEX: Record<string, number> = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 }

const QUALITIES: Record<string, number[]> = {
  "": [0, 4, 7],
  m: [0, 3, 7],
  "7": [0, 4, 7, 10],
  maj7: [0, 4, 7, 11],
  m7: [0, 3, 7, 10],
  dim: [0, 3, 6],
  aug: [0, 4, 8],
  sus2: [0, 2, 7],
  sus4: [0, 5, 7],
  "6": [0, 4, 7, 9],
  "9": [0, 4, 7, 10, 14],
  add9: [0, 4, 7, 14],
}

export interface Chord {
  root: number
  intervals: number[]
}

/** Reads a chord symbol such as "F#m7" or "C/G". Unknown symbols give a C major chord. */
export function parseChord(symbol: string): Chord {
  const match = /^([A-G])(#|b)?([a-z0-9]*)/.exec(symbol.trim())
  if (!match) return { root: 0, intervals: QUALITIES[""] }

  let root = NOTE_INDEX[match[1]]
  if (match[2] === "#") root += 1
  if (match[2] === "b") root -= 1
  root = (root + 12) % 12

  return { root, intervals: QUALITIES[match[3]] ?? QUALITIES[""] }
}

/** MIDI notes of a chord, with its root in the octave that starts at `base`. */
export function chordNotes(chord: Chord, base: number): number[] {
  const root = base + chord.root
  return chord.intervals.map((interval) => root + interval)
}

/** The root note of a chord in the octave that starts at `base`. */
export function chordRoot(chord: Chord, base: number): number {
  return base + chord.root
}

export function midiToFrequency(midi: number): number {
  return 440 * Math.pow(2, (midi - 69) / 12)
}

export function noteName(midi: number): string {
  const names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
  return `${names[midi % 12]}${Math.floor(midi / 12) - 1}`
}
