import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    this.element.requestSubmit()
  }
}
