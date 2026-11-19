export interface Note {
  pitch: number
  start: number
  duration: number
  velocity: number
}

export interface Rhythm {
  name: string
  description?: string
  feel: "straight" | "swing"
  steps: { kick: number[]; snare: number[]; hihat: number[] }
}

export interface Section {
  name: string
  bars: number
  chords: string[]
  energy: "low" | "medium" | "high"
  melody: boolean
}

export interface Mix {
  volume: number
  pan: number
  mute: boolean
  solo: boolean
  reverb: number
  delay: number
  low: number
  mid: number
  high: number
  punch: number
}

export interface TrackData {
  id: number
  instrument: string
  role: string
  status: string
  audioUrl: string | null
  mix: Mix
}

export interface SongData {
  tempo: number
  key: string
  melody: Note[]
  melodyBars: number
  rhythm: Rhythm | null
  sections: Section[]
  tracks: TrackData[]
}

/** The small part of the LiveView hook API that these hooks use. */
export interface HookContext {
  el: HTMLElement
  pushEvent(event: string, payload: object, onReply?: (reply: any) => void): void
  upload(name: string, files: File[] | FileList): void
}
