import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "submit", "icon", "spinner"]

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

  startSubmitting() {
    if (this.fieldTarget.value.trim().length === 0) return

    this.fieldTarget.disabled = true
    this.submitTarget.disabled = true
    this.iconTarget.classList.add("hidden")
    this.spinnerTarget.classList.remove("hidden")
  }

  finishSubmitting() {
    this.fieldTarget.disabled = false
    this.submitTarget.disabled = false
    this.iconTarget.classList.remove("hidden")
    this.spinnerTarget.classList.add("hidden")
    this.fieldTarget.focus()
  }
}
