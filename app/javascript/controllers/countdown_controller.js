import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { fireAt: String }
  static targets = ["display"]

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const remaining = new Date(this.fireAtValue) - Date.now()
    if (remaining <= 0) {
      this.element.hidden = true
      clearInterval(this.timer)
      return
    }
    const totalSeconds = Math.floor(remaining / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    this.displayTarget.textContent =
      `${minutes}:${seconds.toString().padStart(2, "0")} remaining`
  }
}
