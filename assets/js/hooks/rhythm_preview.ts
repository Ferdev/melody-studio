import * as Tone from "tone"
import type { Rhythm } from "../audio/types"
import { createDrumKit, DrumKit } from "../audio/instruments"
import { scheduleDrumBar } from "../audio/song"

let kit: DrumKit | null = null

/**
 * Plays two bars of a rhythm idea. Buttons send the `ms:preview-rhythm` event
 * with the steps, the feel and the tempo.
 */
export function listenForRhythmPreviews() {
  window.addEventListener("ms:preview-rhythm", async (event: Event) => {
    const detail = (event as CustomEvent).detail as { steps: Rhythm["steps"]; feel: Rhythm["feel"]; tempo: number }
    await Tone.start()

    // A new kit for each preview stops the one that is still playing.
    kit?.dispose()
    kit = createDrumKit()
    kit.output.toDestination()

    const beat = 60 / (detail.tempo || 100)
    const start = Tone.now() + 0.1
    const rhythm: Rhythm = { name: "Preview", feel: detail.feel, steps: detail.steps }
    for (let bar = 0; bar < 2; bar++) {
      scheduleDrumBar(rhythm, start + bar * beat * 4, beat, "medium", bar === 1, null, kit)
    }
  })
}
