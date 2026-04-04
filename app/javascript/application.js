// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Preserve scroll position for links marked with data-turbo-preserve-scroll
let preserveScroll = false
document.addEventListener("click", (e) => {
  const link = e.target.closest("[data-turbo-preserve-scroll]")
  if (link) preserveScroll = true
})
document.addEventListener("turbo:before-render", () => {
  if (preserveScroll) {
    Turbo.navigator.currentVisit.scrolled = true
    preserveScroll = false
  }
})
