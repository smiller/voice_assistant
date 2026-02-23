import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["lat", "lng"]

  connect() {
    if (!navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
      (position) => this.save(position),
      () => {}
    )
  }

  save(position) {
    this.latTarget.value = position.coords.latitude
    this.lngTarget.value = position.coords.longitude
  }
}
