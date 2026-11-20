import * as Tone from "tone"

/** The bright lead sound that plays the user's melody. */
export function createLead(): Tone.PolySynth {
  return new Tone.PolySynth(Tone.Synth, {
    oscillator: { type: "triangle" },
    envelope: { attack: 0.01, decay: 0.15, sustain: 0.5, release: 0.4 },
    volume: -6,
  })
}

/** A soft electric piano for the on-screen keyboard. */
export function createPiano(): Tone.PolySynth {
  return new Tone.PolySynth(Tone.FMSynth, {
    harmonicity: 3,
    modulationIndex: 8,
    oscillator: { type: "sine" },
    envelope: { attack: 0.005, decay: 0.9, sustain: 0.15, release: 0.8 },
    modulation: { type: "sine" },
    modulationEnvelope: { attack: 0.002, decay: 0.3, sustain: 0, release: 0.2 },
    volume: -8,
  })
}

export function createKeys(): Tone.PolySynth {
  return new Tone.PolySynth(Tone.FMSynth, {
    harmonicity: 2,
    modulationIndex: 4,
    envelope: { attack: 0.01, decay: 1.2, sustain: 0.3, release: 1 },
    modulationEnvelope: { attack: 0.005, decay: 0.4, sustain: 0.1, release: 0.3 },
    volume: -14,
  })
}

export function createGuitar(): Tone.PolySynth {
  return new Tone.PolySynth(Tone.Synth, {
    oscillator: { type: "fatsawtooth", count: 2, spread: 12 },
    envelope: { attack: 0.003, decay: 0.5, sustain: 0.08, release: 0.3 },
    volume: -22,
  })
}

export function createStrings(): Tone.PolySynth {
  return new Tone.PolySynth(Tone.Synth, {
    oscillator: { type: "fatsawtooth", count: 3, spread: 25 },
    envelope: { attack: 0.35, decay: 0.2, sustain: 0.8, release: 1.2 },
    volume: -22,
  })
}

export function createPads(): Tone.PolySynth {
  return new Tone.PolySynth(Tone.AMSynth, {
    harmonicity: 1.5,
    envelope: { attack: 0.9, decay: 0.5, sustain: 0.9, release: 2 },
    volume: -16,
  })
}

export function createBass(): Tone.MonoSynth {
  return new Tone.MonoSynth({
    oscillator: { type: "fmsquare" },
    filter: { Q: 2, type: "lowpass", rolloff: -24 },
    envelope: { attack: 0.01, decay: 0.3, sustain: 0.6, release: 0.2 },
    filterEnvelope: { attack: 0.01, decay: 0.2, sustain: 0.3, release: 0.3, baseFrequency: 80, octaves: 2.5 },
    volume: -10,
  })
}

export interface DrumKit {
  output: Tone.Gain
  hit(kind: "kick" | "snare" | "hihat", time: number, velocity: number): void
  dispose(): void
}

export function createDrumKit(): DrumKit {
  const output = new Tone.Gain(1)

  const kick = new Tone.MembraneSynth({
    pitchDecay: 0.05,
    octaves: 6,
    envelope: { attack: 0.001, decay: 0.4, sustain: 0, release: 0.1 },
    volume: -2,
  }).connect(output)

  const snareFilter = new Tone.Filter(1800, "highpass").connect(output)
  const snare = new Tone.NoiseSynth({
    noise: { type: "white" },
    envelope: { attack: 0.001, decay: 0.18, sustain: 0, release: 0.05 },
    volume: -10,
  }).connect(snareFilter)

  const hihat = new Tone.MetalSynth({
    envelope: { attack: 0.001, decay: 0.06, release: 0.01 },
    harmonicity: 5.1,
    modulationIndex: 32,
    resonance: 4000,
    octaves: 1.5,
    volume: -28,
  }).connect(output)

  return {
    output,
    hit(kind, time, velocity) {
      if (kind === "kick") kick.triggerAttackRelease("C1", "8n", time, velocity)
      if (kind === "snare") snare.triggerAttackRelease("16n", time, velocity)
      if (kind === "hihat") hihat.triggerAttackRelease(300, "32n", time, velocity)
    },
    dispose() {
      kick.dispose()
      snare.dispose()
      snareFilter.dispose()
      hihat.dispose()
      output.dispose()
    },
  }
}

export function createClick(): Tone.Synth {
  return new Tone.Synth({
    oscillator: { type: "square" },
    envelope: { attack: 0.001, decay: 0.05, sustain: 0, release: 0.01 },
    volume: -14,
  })
}

/**
 * 8-bit sounds for chiptune songs: square and triangle waves with short
 * envelopes, like the sound chips of old game consoles.
 */
export function createChipVoice(kind: "lead" | "chords" | "pad"): Tone.PolySynth {
  const settings = {
    lead: { type: "square", envelope: { attack: 0.002, decay: 0.1, sustain: 0.6, release: 0.05 }, volume: -16 },
    chords: { type: "pulse", envelope: { attack: 0.002, decay: 0.15, sustain: 0.2, release: 0.05 }, volume: -24 },
    pad: { type: "triangle", envelope: { attack: 0.05, decay: 0.2, sustain: 0.7, release: 0.2 }, volume: -16 },
  }[kind]

  return new Tone.PolySynth(Tone.Synth, {
    oscillator: { type: settings.type } as any,
    envelope: settings.envelope,
    volume: settings.volume,
  })
}

export function createChipBass(): Tone.MonoSynth {
  return new Tone.MonoSynth({
    oscillator: { type: "triangle" },
    filter: { type: "lowpass", frequency: 8000, Q: 0 },
    envelope: { attack: 0.002, decay: 0.1, sustain: 0.8, release: 0.05 },
    filterEnvelope: { attack: 0.001, decay: 0.01, sustain: 1, release: 0.01, baseFrequency: 8000, octaves: 0 },
    volume: -6,
  })
}
