import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mode", "compact", "raw"]

  toggle() {
    const isRaw = this.modeTarget.value === "raw"
    this.compactTarget.classList.toggle("hidden", isRaw)
    this.rawTarget.classList.toggle("hidden", !isRaw)
    if (isRaw) {
      this.rawTarget.classList.add("grid")
    } else {
      this.rawTarget.classList.remove("grid")
    }
  }
}
