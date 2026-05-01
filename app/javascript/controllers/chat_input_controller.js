import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "fileInput", "fileStatus", "submit", "icon", "spinner", "dropOverlay"]

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    if (!this.hasSubmissionContent()) return

    this.submitTarget.click()
  }

  clearOnSubmit() {
    if (!this.hasSubmissionContent()) return

    requestAnimationFrame(() => {
      this.fieldTarget.value = ""
      this.fieldTarget.style.height = null
      if (this.hasFileInputTarget) this.fileInputTarget.value = ""
      this.updateFileStatus()
    })
  }

  startSubmitting() {
    if (!this.hasSubmissionContent()) return

    this.fieldTarget.disabled = true
    if (this.hasFileInputTarget) this.fileInputTarget.disabled = true
    this.submitTarget.disabled = true
    this.iconTarget.classList.add("hidden")
    this.spinnerTarget.classList.remove("hidden")
  }

  finishSubmitting() {
    this.fieldTarget.disabled = false
    if (this.hasFileInputTarget) this.fileInputTarget.disabled = false
    this.submitTarget.disabled = false
    this.iconTarget.classList.remove("hidden")
    this.spinnerTarget.classList.add("hidden")
    this.fieldTarget.focus()
  }

  allowDrop(event) {
    if (!this.dragContainsFiles(event)) return

    event.preventDefault()
    this.showDropTarget(event)
  }

  showDropTarget(event) {
    if (!this.dragContainsFiles(event)) return

    event.preventDefault()
    if (this.hasDropOverlayTarget) this.dropOverlayTarget.classList.remove("hidden")
    if (this.hasDropOverlayTarget) this.dropOverlayTarget.classList.add("flex")
  }

  hideDropTarget(event) {
    if (event.relatedTarget && this.element.contains(event.relatedTarget)) return

    this.hideDropOverlay()
  }

  dropFiles(event) {
    if (!this.dragContainsFiles(event) || !this.hasFileInputTarget) return

    event.preventDefault()
    this.fileInputTarget.files = event.dataTransfer.files
    this.updateFileStatus()
    this.hideDropOverlay()
    this.fieldTarget.focus()
  }

  updateFileStatus() {
    if (!this.hasFileStatusTarget || !this.hasFileInputTarget) return

    const count = this.fileInputTarget.files.length
    if (count === 0) {
      this.fileStatusTarget.textContent = ""
      this.fileStatusTarget.classList.add("hidden")
      return
    }

    const label = count === 1
      ? this.fileStatusTarget.dataset.singularLabel
      : this.fileStatusTarget.dataset.pluralLabel.replace("__count__", count)
    this.fileStatusTarget.textContent = label
    this.fileStatusTarget.classList.remove("hidden")
  }

  hasSubmissionContent() {
    return this.fieldTarget.value.trim().length > 0 || (this.hasFileInputTarget && this.fileInputTarget.files.length > 0)
  }

  dragContainsFiles(event) {
    return Array.from(event.dataTransfer?.types || []).includes("Files")
  }

  hideDropOverlay() {
    if (!this.hasDropOverlayTarget) return

    this.dropOverlayTarget.classList.add("hidden")
    this.dropOverlayTarget.classList.remove("flex")
  }
}
