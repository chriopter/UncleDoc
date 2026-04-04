import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["section"]

  connect() {
    this.highlightCurrentPage()
    document.addEventListener("turbo:load", this.highlightCurrentPage.bind(this))
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.highlightCurrentPage.bind(this))
  }

  toggle(event) {
    const details = event.currentTarget.closest("details")
    if (!details) return

    event.preventDefault()
    details.open = !details.open

    const id = details.dataset.sectionId
    if (id) localStorage.setItem(`sidebar-${id}`, details.open)
  }

  highlightCurrentPage() {
    const path = window.location.pathname

    this.sectionTargets.forEach((section) => {
      const links = section.querySelectorAll("a[href]")
      let hasActive = false

      links.forEach((link) => {
        const href = link.getAttribute("href")
        const isActive = href && path.startsWith(href)
        link.classList.toggle("active", isActive)
        if (isActive) hasActive = true
      })

      if (hasActive) {
        section.open = true
      } else {
        const id = section.dataset.sectionId
        const saved = id ? localStorage.getItem(`sidebar-${id}`) : null
        section.open = saved === "true"
      }
    })
  }
}
