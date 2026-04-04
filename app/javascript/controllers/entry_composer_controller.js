import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "fileInput", "files", "timeFields"]
  static values = { filesLabel: String, dropLabel: String }

  connect() {
    this.renderFiles()
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    this.element.requestSubmit()
  }

  openFilePicker() {
    this.fileInputTarget.click()
  }

  filesChanged() {
    this.renderFiles()
  }

  toggleTime() {
    this.timeFieldsTarget.classList.toggle("hidden")
  }

  dragOver(event) {
    event.preventDefault()
    this.inputTarget.classList.add("border-amber-400", "bg-amber-50")
  }

  dragLeave() {
    this.inputTarget.classList.remove("border-amber-400", "bg-amber-50")
  }

  drop(event) {
    event.preventDefault()
    this.dragLeave()

    const files = Array.from(event.dataTransfer.files)
    if (files.length === 0) return

    const transfer = new DataTransfer()
    Array.from(this.fileInputTarget.files).forEach((file) => transfer.items.add(file))
    files.forEach((file) => transfer.items.add(file))
    this.fileInputTarget.files = transfer.files
    this.renderFiles()
  }

  renderFiles() {
    if (!this.hasFilesTarget) return

    const files = Array.from(this.fileInputTarget.files)
    if (files.length === 0) {
      this.filesTarget.textContent = this.dropLabelValue || this.filesLabelValue
      this.filesTarget.className = "text-sm text-slate-500"
      return
    }

    this.filesTarget.className = "flex flex-wrap gap-2"
    this.filesTarget.innerHTML = files.map((file) => (
      `<span class="inline-flex items-center rounded-full border border-amber-200 bg-white px-3 py-1 text-xs font-medium text-slate-700">${file.name}</span>`
    )).join("")
  }
}
