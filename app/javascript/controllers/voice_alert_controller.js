import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { token: String, url: String }

  connect() {
    this.playAlert()
  }

  async playAlert() {
    const response = await fetch(this.urlValue)
    if (!response.ok) {
      this.element.remove()
      return
    }

    const arrayBuffer = await response.arrayBuffer()
    const audioContext = new AudioContext()
    const audioBuffer = await audioContext.decodeAudioData(arrayBuffer)
    const source = audioContext.createBufferSource()
    source.buffer = audioBuffer
    source.connect(audioContext.destination)
    source.onended = () => this.element.remove()
    source.start()
  }
}
