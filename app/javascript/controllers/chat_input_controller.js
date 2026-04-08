import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "submit"]

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    if (this.fieldTarget.value.trim().length === 0) return

    this.submitTarget.click()
  }

  clearOnSubmit() {
    if (this.fieldTarget.value.trim().length === 0) return

    requestAnimationFrame(() => {
      this.fieldTarget.value = ""
      this.fieldTarget.style.height = null
    })
  }
}
