import * as Tone from "tone"
import type { Mix, Note, Rhythm, Section, SongData, TrackData } from "./types"
import {
  createBass,
  createDrumKit,
  createGuitar,
  createKeys,
  createLead,
  createPads,
  createStrings,
  DrumKit,
} from "./instruments"
import { chordNotes, chordRoot, midiToFrequency, parseChord } from "./theory"

type Transport = ReturnType<typeof Tone.getTransport>

const ENERGY_VELOCITY = { low: 0.5, medium: 0.7, high: 0.9 }
const TAIL_SECONDS = 2.5

export function beatSeconds(tempo: number) {
  return 60 / tempo
}

export function songDuration(data: SongData): number {
  const bars = data.sections.reduce((sum, section) => sum + section.bars, 0)
  return bars * 4 * beatSeconds(data.tempo) + TAIL_SECONDS
}

/** The start time of each section, in seconds. */
export function sectionStarts(data: SongData): number[] {
  const bar = 4 * beatSeconds(data.tempo)
  let time = 0
  return data.sections.map((section) => {
    const start = time
    time += section.bars * bar
    return start
  })
}

/** Loads the AI audio of every track that has it. */
export async function loadBuffers(data: SongData): Promise<Map<number, Tone.ToneAudioBuffer>> {
  const buffers = new Map<number, Tone.ToneAudioBuffer>()
  await Promise.all(
    data.tracks
      .filter((track) => track.audioUrl)
      .map(async (track) => {
        try {
          buffers.set(track.id, await Tone.ToneAudioBuffer.fromUrl(track.audioUrl!))
        } catch (_error) {
          // A missing file falls back to the built-in sound of the instrument.
        }
      })
  )
  return buffers
}

interface ChannelStrip {
  input: Tone.ToneAudioNode
  eq: Tone.EQ3
  compressor: Tone.Compressor
  panner: Tone.Panner
  volume: Tone.Volume
  reverbSend: Tone.Gain
  delaySend: Tone.Gain
  nodes: { dispose(): void }[]
}

export interface SongGraph {
  duration: number
  applyMix(tracks: TrackData[]): void
  setParam(trackId: number, param: keyof Mix, value: number): void
  dispose(): void
}

/**
 * Builds every instrument, effect and event of the song on the current Tone
 * context. It works the same way for live playback and for offline export.
 */
export async function buildSongGraph(
  data: SongData,
  buffers: Map<number, Tone.ToneAudioBuffer>,
  transport: Transport
): Promise<SongGraph> {
  const disposables: { dispose(): void }[] = []
  const limiter = new Tone.Limiter(-1).toDestination()
  const master = new Tone.Gain(0.9).connect(limiter)
  const reverb = new Tone.Reverb({ decay: 2.8, preDelay: 0.02, wet: 1 }).connect(master)
  const delay = new Tone.FeedbackDelay({ delayTime: beatSeconds(data.tempo) * 0.75, feedback: 0.35, wet: 1 }).connect(master)
  await reverb.ready
  disposables.push(limiter, master, reverb, delay)

  const strips = new Map<number, ChannelStrip>()
  const mixes = new Map<number, Mix>()

  for (const track of data.tracks) {
    const strip = createStrip(master, reverb, delay)
    strips.set(track.id, strip)
    mixes.set(track.id, { ...track.mix })
    disposables.push(...strip.nodes)

    const buffer = buffers.get(track.id)
    if (buffer) {
      const player = new Tone.Player(buffer).connect(strip.input)
      player.sync().start(0)
      disposables.push(player)
    } else {
      disposables.push(...scheduleSketch(track, data, strip.input, transport))
    }
  }

  const applyAll = () => {
    const anySolo = [...mixes.values()].some((mix) => mix.solo)
    for (const [id, mix] of mixes) applyStrip(strips.get(id)!, mix, anySolo)
  }
  applyAll()

  return {
    duration: songDuration(data),
    applyMix(tracks) {
      for (const track of tracks) if (mixes.has(track.id)) mixes.set(track.id, { ...track.mix })
      applyAll()
    },
    setParam(trackId, param, value) {
      const mix = mixes.get(trackId)
      if (!mix) return
      ;(mix as any)[param] = value
      applyAll()
    },
    dispose() {
      transport.cancel(0)
      for (const node of disposables) {
        try {
          node.dispose()
        } catch (_error) {
          // Already disposed.
        }
      }
    },
  }
}

function createStrip(master: Tone.Gain, reverb: Tone.Reverb, delay: Tone.FeedbackDelay): ChannelStrip {
  const eq = new Tone.EQ3()
  const compressor = new Tone.Compressor({ attack: 0.01, release: 0.2 })
  const panner = new Tone.Panner(0)
  const volume = new Tone.Volume(0)
  const reverbSend = new Tone.Gain(0)
  const delaySend = new Tone.Gain(0)

  eq.chain(compressor, panner, volume, master)
  volume.connect(reverbSend)
  volume.connect(delaySend)
  reverbSend.connect(reverb)
  delaySend.connect(delay)

  return {
    input: eq,
    eq,
    compressor,
    panner,
    volume,
    reverbSend,
    delaySend,
    nodes: [eq, compressor, panner, volume, reverbSend, delaySend],
  }
}

function applyStrip(strip: ChannelStrip, mix: Mix, anySolo: boolean) {
  const silent = mix.mute || (anySolo && !mix.solo) || mix.volume <= 0
  strip.volume.volume.value = silent ? -Infinity : 20 * Math.log10(mix.volume / 80)
  strip.panner.pan.value = Math.max(-1, Math.min(1, mix.pan / 100))
  strip.reverbSend.gain.value = (mix.reverb / 100) * 0.8
  strip.delaySend.gain.value = (mix.delay / 100) * 0.6
  strip.eq.low.value = mix.low
  strip.eq.mid.value = mix.mid
  strip.eq.high.value = mix.high
  strip.compressor.threshold.value = -(mix.punch * 0.3)
  strip.compressor.ratio.value = 1 + (mix.punch / 100) * 7
}

/** Schedules the built-in sound of an instrument from the arrangement plan. */
function scheduleSketch(
  track: TrackData,
  data: SongData,
  output: Tone.ToneAudioNode,
  transport: Transport
): { dispose(): void }[] {
  const beat = beatSeconds(data.tempo)
  const bar = beat * 4
  const starts = sectionStarts(data)

  const eachBar = (callback: (time: number, chord: string, section: Section) => void) => {
    data.sections.forEach((section, index) => {
      for (let b = 0; b < section.bars; b++) {
        const chord = section.chords[b % Math.max(section.chords.length, 1)] ?? "C"
        callback(starts[index] + b * bar, chord, section)
      }
    })
  }

  switch (track.instrument) {
    case "melody": {
      const lead = createLead().connect(output)
      scheduleMelody(data, transport, (time, note) => {
        lead.triggerAttackRelease(midiToFrequency(note.pitch), note.duration * beat * 0.95, time, note.velocity)
      })
      return [lead]
    }

    case "drums": {
      const kit = createDrumKit()
      kit.output.connect(output)
      scheduleDrums(data, transport, kit)
      return [kit]
    }

    case "bass": {
      const bass = createBass().connect(output)
      const kick = data.rhythm?.steps.kick ?? []
      eachBar((barTime, symbol, section) => {
        const root = chordRoot(parseChord(symbol), 36)
        const velocity = ENERGY_VELOCITY[section.energy]
        let hits = kick.map((hit, i) => (hit ? i : -1)).filter((i) => i >= 0)
        if (section.energy === "low" || hits.length === 0) hits = [0, 8]
        hits.forEach((step, i) => {
          const next = hits[i + 1] ?? 16
          const length = Math.min(next - step, 4) * (beat / 4)
          transport.schedule((time) => {
            bass.triggerAttackRelease(midiToFrequency(root), length * 0.9, time, velocity)
          }, barTime + step * (beat / 4))
        })
      })
      return [bass]
    }

    case "keys": {
      const keys = createKeys().connect(output)
      eachBar((barTime, symbol, section) => {
        const notes = chordNotes(parseChord(symbol), 60).map(midiToFrequency)
        const velocity = ENERGY_VELOCITY[section.energy]
        const hits = section.energy === "high" ? [0, 1, 2, 3] : section.energy === "medium" ? [0, 2] : [0]
        const length = (4 / hits.length) * beat
        hits.forEach((b) =>
          transport.schedule((time) => keys.triggerAttackRelease(notes, length * 0.9, time, velocity), barTime + b * beat)
        )
      })
      return [keys]
    }

    case "guitar": {
      const guitar = createGuitar().connect(output)
      eachBar((barTime, symbol, section) => {
        const notes = chordNotes(parseChord(symbol), 52).map(midiToFrequency)
        const velocity = ENERGY_VELOCITY[section.energy]
        const eighths = section.energy === "high" ? [0, 1, 2, 3, 4, 5, 6, 7] : section.energy === "medium" ? [0, 2, 3, 4, 6] : [0, 4]
        eighths.forEach((e) =>
          transport.schedule((time) => {
            notes.forEach((frequency, i) => {
              guitar.triggerAttackRelease(frequency, beat * 0.45, time + i * 0.012, velocity * (e % 2 ? 0.7 : 1))
            })
          }, barTime + e * (beat / 2))
        )
      })
      return [guitar]
    }

    case "strings": {
      const strings = createStrings()
      const filter = new Tone.Filter(2200, "lowpass").connect(output)
      strings.connect(filter)
      eachBar((barTime, symbol, section) => {
        const notes = chordNotes(parseChord(symbol), 60).map(midiToFrequency)
        const velocity = ENERGY_VELOCITY[section.energy] * 0.8
        transport.schedule((time) => strings.triggerAttackRelease(notes, bar * 0.98, time, velocity), barTime)
      })
      return [strings, filter]
    }

    default: {
      const pads = createPads().connect(output)
      eachBar((barTime, symbol, section) => {
        const notes = chordNotes(parseChord(symbol), 48).map(midiToFrequency)
        const velocity = ENERGY_VELOCITY[section.energy] * 0.7
        transport.schedule((time) => pads.triggerAttackRelease(notes, bar, time, velocity), barTime)
      })
      return [pads]
    }
  }
}

/** Schedules the melody in each section where it plays, repeated to fill the section. */
export function scheduleMelody(
  data: SongData,
  transport: Transport,
  play: (time: number, note: Note) => void
) {
  const beat = beatSeconds(data.tempo)
  const starts = sectionStarts(data)
  const loopBeats = Math.max(data.melodyBars, 1) * 4

  data.sections.forEach((section, index) => {
    if (!section.melody || data.melody.length === 0) return
    const sectionBeats = section.bars * 4
    for (let offset = 0; offset < sectionBeats; offset += loopBeats) {
      for (const note of data.melody) {
        const startBeat = offset + note.start
        if (startBeat >= sectionBeats) continue
        transport.schedule((time) => play(time, note), starts[index] + startBeat * beat)
      }
    }
  })
}

function scheduleDrums(data: SongData, transport: Transport, kit: DrumKit) {
  const rhythm: Rhythm = data.rhythm ?? {
    name: "Basic",
    feel: "straight",
    steps: {
      kick: [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
      snare: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
      hihat: [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
    },
  }
  const beat = beatSeconds(data.tempo)
  const bar = beat * 4
  const starts = sectionStarts(data)

  data.sections.forEach((section, index) => {
    for (let b = 0; b < section.bars; b++) {
      const barTime = starts[index] + b * bar
      const last = b === section.bars - 1
      scheduleDrumBar(rhythm, barTime, beat, section.energy, last, transport, kit)
    }
  })
}

/** Schedules one bar of a drum pattern. Exported for the rhythm preview. */
export function scheduleDrumBar(
  rhythm: Rhythm,
  barTime: number,
  beat: number,
  energy: "low" | "medium" | "high",
  fill: boolean,
  transport: Transport | null,
  kit: DrumKit
) {
  const velocity = ENERGY_VELOCITY[energy]
  const step = beat / 4

  for (let i = 0; i < 16; i++) {
    const swing = rhythm.feel === "swing" && i % 2 === 1 ? step * 0.33 : 0
    const at = barTime + i * step + swing
    const hits: ["kick" | "snare" | "hihat", number][] = []

    if (rhythm.steps.kick[i] && (energy !== "low" || i === 0)) hits.push(["kick", velocity])
    if (rhythm.steps.snare[i] && energy !== "low") hits.push(["snare", velocity])
    if (fill && energy !== "low" && i >= 12 && !rhythm.steps.snare[i]) hits.push(["snare", velocity * 0.6])
    if (rhythm.steps.hihat[i]) hits.push(["hihat", velocity * (i % 4 === 0 ? 1 : 0.7)])

    for (const [kind, v] of hits) {
      if (transport) transport.schedule((time) => kit.hit(kind, time, v), at)
      else kit.hit(kind, at, v)
    }
  }
}

/** Renders the whole song without playing it, for the WAV download. */
export async function renderSong(
  data: SongData,
  buffers: Map<number, Tone.ToneAudioBuffer>
): Promise<AudioBuffer> {
  const duration = songDuration(data)
  const rendered = await Tone.Offline(async (context) => {
    await buildSongGraph(data, buffers, context.transport)
    context.transport.start(0)
  }, duration, 2, 44100)
  return rendered.get() as AudioBuffer
}

/** Renders the melody alone, to guide the AI music model. */
export async function renderMelody(notes: Note[], tempo: number): Promise<AudioBuffer> {
  const beat = beatSeconds(tempo)
  const end = notes.reduce((max, note) => Math.max(max, note.start + note.duration), 0)
  const duration = Math.min(end * beat + 1, 60)

  const rendered = await Tone.Offline(() => {
    const lead = createLead().toDestination()
    for (const note of notes) {
      lead.triggerAttackRelease(midiToFrequency(note.pitch), note.duration * beat * 0.95, note.start * beat, note.velocity)
    }
  }, duration, 1, 32000)
  return rendered.get() as AudioBuffer
}
