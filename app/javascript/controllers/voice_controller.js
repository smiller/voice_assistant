import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { recording: Boolean }

  MAX_DURATION_MS = 15000
  MIN_DURATION_MS = 500

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleKeyup = this.handleKeyup.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
    document.addEventListener("keyup", this.handleKeyup)
    this.chunks = []
    this.mediaRecorder = null
    this.autoStopTimeout = null
    this.loadConfig()
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("keyup", this.handleKeyup)
  }

  async loadConfig() {
    try {
      const resp = await fetch("/config")
      const data = await resp.json()
      this.voiceId = data.voice_id
    } catch (e) {
      this.updateStatus("Failed to load config")
    }
  }

  handleKeydown(e) {
    if (e.code !== "Space") return
    if (["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)) return
    if (this.recordingValue) return
    e.preventDefault()
    this.startRecording()
  }

  handleKeyup(e) {
    if (e.code !== "Space") return
    if (!this.recordingValue) return
    e.preventDefault()
    this.stopRecording()
  }

  async startRecording() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      this.chunks = []
      this.mediaRecorder = new MediaRecorder(stream)
      this.mediaRecorder.ondataavailable = (e) => this.chunks.push(e.data)
      this.mediaRecorder.start()
      this.recordingStartedAt = Date.now()
      this.recordingValue = true
      this.updateStatus("Listening…")
      this.autoStopTimeout = setTimeout(() => this.stopRecording(), this.MAX_DURATION_MS)
    } catch (e) {
      this.updateStatus("Microphone access denied")
    }
  }

  stopRecording() {
    clearTimeout(this.autoStopTimeout)
    if (!this.mediaRecorder) return

    const elapsed = Date.now() - this.recordingStartedAt
    if (elapsed < this.MIN_DURATION_MS) {
      this.autoStopTimeout = setTimeout(() => this.stopRecording(), this.MIN_DURATION_MS - elapsed)
      return
    }

    this.mediaRecorder.onstop = () => {
      const blob = new Blob(this.chunks, { type: "audio/webm" })
      this.mediaRecorder.stream.getTracks().forEach(t => t.stop())
      this.postAudio(blob)
    }
    this.mediaRecorder.stop()
    this.recordingValue = false
    this.updateStatus("Processing…")
  }

  async postAudio(blob) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const form = new FormData()
    form.append("audio", blob, "recording.webm")
    try {
      const resp = await fetch("/voice_commands", {
        method: "POST",
        headers: { "X-CSRF-Token": token },
        body: form
      })
      if (!resp.ok) throw new Error(`Server error: ${resp.status}`)
      const statusText = resp.headers.get("X-Status-Text")
      const buffer = await resp.arrayBuffer()
      this.playAudio(buffer, statusText)
    } catch (e) {
      this.updateStatus(`Error: ${e.message}`)
    }
  }

  async playAudio(arrayBuffer, statusText = null) {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)()
      const decoded = await ctx.decodeAudioData(arrayBuffer)
      const source = ctx.createBufferSource()
      source.buffer = decoded
      source.connect(ctx.destination)
      source.onended = () => this.updateStatus("Ready")
      source.start()
      this.updateStatus(statusText || "Ready")
    } catch (e) {
      this.updateStatus("Audio playback failed")
    }
  }

  updateStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
