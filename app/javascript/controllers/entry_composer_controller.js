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

  async drop(event) {
    event.preventDefault()
    this.dragLeave()

    const files = await this.extractDroppedFiles(event.dataTransfer)
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

  async extractDroppedFiles(dataTransfer) {
    const items = Array.from(dataTransfer?.items || [])
    if (items.length === 0) return Array.from(dataTransfer?.files || [])

    const files = []

    for (const item of items) {
      if (item.kind !== "file") continue

      if (typeof item.getAsFileSystemHandle === "function") {
        const handle = await item.getAsFileSystemHandle()
        if (handle) {
          await this.collectHandleFiles(handle, files)
          continue
        }
      }

      if (typeof item.webkitGetAsEntry === "function") {
        const entry = item.webkitGetAsEntry()
        if (entry) {
          await this.collectEntryFiles(entry, files)
          continue
        }
      }

      const file = item.getAsFile()
      if (file) files.push(file)
    }

    return files
  }

  async collectHandleFiles(handle, files) {
    if (handle.kind === "file") {
      files.push(await handle.getFile())
      return
    }

    for await (const child of handle.values()) {
      await this.collectHandleFiles(child, files)
    }
  }

  async collectEntryFiles(entry, files) {
    if (entry.isFile) {
      await new Promise((resolve) => {
        entry.file((file) => {
          files.push(file)
          resolve()
        }, () => resolve())
      })
      return
    }

    const reader = entry.createReader()
    const entries = await this.readAllDirectoryEntries(reader)

    for (const child of entries) {
      await this.collectEntryFiles(child, files)
    }
  }

  async readAllDirectoryEntries(reader) {
    const entries = []

    while (true) {
      const batch = await new Promise((resolve) => reader.readEntries(resolve, () => resolve([])))
      if (!batch.length) break
      entries.push(...batch)
    }

    return entries
  }
}
