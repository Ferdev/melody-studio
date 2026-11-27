import type { HookContext, Note } from "../audio/types"
import { renderMelody } from "../audio/song"
import { encodeWav } from "../audio/wav"

type Self = HookContext & { onClick?: (event: Event) => void }

/**
 * Renders the melody to a WAV file in the browser and uploads it, so the AI
 * music model can follow the melody. The server starts the build when the
 * upload is done. If the render fails, the build starts without the audio.
 */
export const BuildSong = {
  mounted(this: Self) {
    const self = this
    self.onClick = async (event: Event) => {
      event.preventDefault()
      const button = self.el as HTMLButtonElement
      if (button.disabled) return
      button.disabled = true

      try {
        const notes: Note[] = JSON.parse(self.el.dataset.notes || "[]")
        const tempo = Number(self.el.dataset.tempo) || 100
        if (notes.length === 0) throw new Error("no notes")

        const buffer = await renderMelody(notes, tempo)
        const file = new File([encodeWav(buffer)], "melody.wav", { type: "audio/wav" })
        self.upload("melody_audio", [file])
      } catch (_error) {
        self.pushEvent("build_song", {})
      }
    }
    self.el.addEventListener("click", self.onClick)
  },

  destroyed(this: Self) {
    if (this.onClick) this.el.removeEventListener("click", this.onClick)
  },
}
