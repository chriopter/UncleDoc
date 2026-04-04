import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "messages", "form", "submit"]

  connect() {
    this.inputTarget.focus()
  }

  async send(event) {
    event.preventDefault()

    const message = this.inputTarget.value.trim()
    if (!message) return

    this.appendMessage("user", message)
    this.inputTarget.value = ""
    this.inputTarget.style.height = "auto"
    this.submitTarget.disabled = true

    const assistantEl = this.appendMessage("assistant", "…")

    try {
      const response = await fetch(this.element.dataset.chatUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ message })
      })

      const data = await response.json()

      if (data.error) {
        assistantEl.querySelector("[data-role='content']").textContent = data.error
      } else {
        assistantEl.querySelector("[data-role='content']").innerHTML = this.formatMarkdown(data.reply)
      }
    } catch (e) {
      assistantEl.querySelector("[data-role='content']").textContent = "Request failed. Check your LLM settings."
    }

    this.submitTarget.disabled = false
    this.inputTarget.focus()
    this.scrollToBottom()
  }

  appendMessage(role, content) {
    const wrapper = document.createElement("div")
    wrapper.className = role === "user"
      ? "flex justify-end"
      : "flex justify-start"

    const bubble = document.createElement("div")
    bubble.className = role === "user"
      ? "max-w-[80%] rounded-2xl rounded-tr-md bg-amber-600 px-4 py-3 text-sm leading-relaxed text-white"
      : "max-w-[80%] rounded-2xl rounded-tl-md bg-white/10 px-4 py-3 text-sm leading-relaxed text-slate-100"

    const contentEl = document.createElement("div")
    contentEl.setAttribute("data-role", "content")
    contentEl.className = "whitespace-pre-wrap"
    contentEl.textContent = content

    bubble.appendChild(contentEl)
    wrapper.appendChild(bubble)
    this.messagesTarget.appendChild(wrapper)
    this.scrollToBottom()

    return wrapper
  }

  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  autoResize() {
    const el = this.inputTarget
    el.style.height = "auto"
    el.style.height = Math.min(el.scrollHeight, 160) + "px"
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  formatMarkdown(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/\n/g, "<br>")
  }
}
