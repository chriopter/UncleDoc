// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

function syncBrowserTimeZone() {
  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone
  if (!timeZone) return

  const cookieMatch = document.cookie.match(/(?:^|; )browser_time_zone=([^;]+)/)
  const currentValue = cookieMatch ? decodeURIComponent(cookieMatch[1]) : null

  if (currentValue === timeZone) return

  document.cookie = `browser_time_zone=${encodeURIComponent(timeZone)}; path=/; max-age=31536000; samesite=lax`

  const reloadKey = `uncledoc-time-zone-reload:${timeZone}`
  if (sessionStorage.getItem(reloadKey) === "done") return

  sessionStorage.setItem(reloadKey, "done")
  window.location.reload()
}

document.addEventListener("DOMContentLoaded", syncBrowserTimeZone)
document.addEventListener("turbo:load", syncBrowserTimeZone)

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
