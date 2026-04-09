import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "panel"]
  static values = { default: String }

  connect() {
    this.activate(this.defaultValue || this.buttonTargets[0]?.dataset.panel)
  }

  showPanel(event) {
    event.preventDefault()
    this.activate(event.currentTarget.dataset.panel)
  }

  activate(panelName) {
    if (!panelName) return

    this.buttonTargets.forEach((button) => {
      const active = button.dataset.panel === panelName
      const activeClasses = (button.dataset.activeClasses || "").split(" ").filter(Boolean)
      const inactiveClasses = (button.dataset.inactiveClasses || "").split(" ").filter(Boolean)

      activeClasses.forEach((klass) => button.classList.toggle(klass, active))
      inactiveClasses.forEach((klass) => button.classList.toggle(klass, !active))
    })

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.panel !== panelName)
    })
  }
}
