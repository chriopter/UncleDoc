import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pill", "tables"]

  connect() {
    // Show all tables by default
    this.showAll()
  }

  showAll() {
    // Show all table sections
    this.tableSections.forEach(section => {
      section.classList.remove("hidden")
    })
    
    // Update pill styles
    this.updatePillStyles("all")
  }

  showTable(event) {
    const tableName = event.currentTarget.dataset.table
    
    // Hide all tables first
    this.tableSections.forEach(section => {
      section.classList.add("hidden")
    })
    
    // Show only the selected table
    const selectedSection = this.element.querySelector(`section[data-table="${tableName}"]`)
    if (selectedSection) {
      selectedSection.classList.remove("hidden")
    }
    
    // Update pill styles
    this.updatePillStyles(tableName)
  }

  updatePillStyles(activeTable) {
    this.pillTargets.forEach(pill => {
      const pillTable = pill.dataset.table
      
      if (pillTable === activeTable) {
        // Active style
        pill.classList.remove("border", "border-slate-200", "bg-white", "text-slate-600")
        pill.classList.add("bg-slate-950", "text-white")
      } else {
        // Inactive style
        pill.classList.remove("bg-slate-950", "text-white")
        pill.classList.add("border", "border-slate-200", "bg-white", "text-slate-600")
      }
    })
  }

  get tableSections() {
    return this.element.querySelectorAll("section[data-table]")
  }
}
