import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["raw", "rendered"]

  connect() {
    this.render = this.render.bind(this)
    this.observer = new MutationObserver(this.render)
    this.observer.observe(this.rawTarget, { childList: true, characterData: true, subtree: true })
    this.render()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  render() {
    const text = this.rawTarget.textContent || ""

    if (!text.trim()) {
      return
    }

    this.renderedTarget.innerHTML = this.renderMarkdown(text)
  }

  renderMarkdown(text) {
    const lines = text.replace(/\r\n/g, "\n").split("\n")
    const blocks = []

    for (let index = 0; index < lines.length;) {
      const line = lines[index].replace(/\s+$/, "")

      if (!line.trim()) {
        index += 1
        continue
      }

      if (line.startsWith("```")) {
        const codeLines = [line]
        index += 1

        while (index < lines.length) {
          const nextLine = lines[index].replace(/\s+$/, "")
          codeLines.push(nextLine)
          index += 1
          if (nextLine === "```") break
        }

        blocks.push(this.renderBlock(codeLines))
        continue
      }

      if (this.headingLine(line)) {
        blocks.push(this.renderBlock([line]))
        index += 1
        continue
      }

      const group = [line]
      index += 1

      while (index < lines.length) {
        const nextLine = lines[index].replace(/\s+$/, "")
        if (!nextLine.trim() || nextLine.startsWith("```") || this.headingLine(nextLine)) break

        if (this.listLine(group[0])) {
          if (!(this.listLine(nextLine) && this.orderedListLine(group[0]) === this.orderedListLine(nextLine))) break
        }

        group.push(nextLine)
        index += 1
      }

      blocks.push(this.renderBlock(group))
    }

    return blocks.join("")
  }

  renderBlock(lines) {
    if (this.codeBlock(lines)) {
      const code = this.escapeHtml(lines.slice(1, -1).join("\n"))
      return `<pre class="overflow-x-auto rounded-2xl bg-slate-950 px-4 py-3 text-xs leading-6 text-slate-100"><code>${code}</code></pre>`
    }

    if (lines.every((line) => this.unorderedListLine(line))) {
      const items = lines.map((line) => `<li>${this.inlineMarkdown(line.trim().slice(2))}</li>`).join("")
      return `<ul class="list-disc space-y-1 pl-5">${items}</ul>`
    }

    if (lines.every((line) => this.orderedListLine(line))) {
      const items = lines.map((line) => `<li>${this.inlineMarkdown(line.trim().replace(/^\d+\.\s+/, ""))}</li>`).join("")
      return `<ol class="list-decimal space-y-1 pl-5">${items}</ol>`
    }

    if (lines[0].startsWith("### ")) {
      return `<h3 class="mt-3 text-sm font-bold text-slate-900">${this.inlineMarkdown(lines[0].slice(4))}</h3>`
    }

    if (lines[0].startsWith("## ")) {
      return `<h2 class="mt-3 text-base font-bold text-slate-900">${this.inlineMarkdown(lines[0].slice(3))}</h2>`
    }

    if (lines[0].startsWith("# ")) {
      return `<h1 class="mt-3 text-lg font-bold text-slate-900">${this.inlineMarkdown(lines[0].slice(2))}</h1>`
    }

    return `<p class="leading-7">${this.inlineMarkdown(lines.join("<br>"), true)}</p>`
  }

  inlineMarkdown(text, allowBreaks = false) {
    let escaped = this.escapeHtml(text)

    if (allowBreaks) {
      escaped = escaped.replace(/&lt;br&gt;/g, "<br>")
    }

    escaped = escaped.replace(/`([^`]+)`/g, '<code class="rounded bg-slate-100 px-1 py-0.5 font-mono text-[0.9em] text-slate-900">$1</code>')
    escaped = escaped.replace(/\*\*([^*]+)\*\*/g, '<strong class="font-semibold text-slate-900">$1</strong>')
    escaped = escaped.replace(/\*([^*]+)\*/g, "<em>$1</em>")
    return escaped
  }

  escapeHtml(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }

  headingLine(line) {
    return line.startsWith("# ") || line.startsWith("## ") || line.startsWith("### ")
  }

  listLine(line) {
    return this.unorderedListLine(line) || this.orderedListLine(line)
  }

  unorderedListLine(line) {
    const trimmed = line.trimStart()
    return trimmed.startsWith("- ") || trimmed.startsWith("* ")
  }

  orderedListLine(line) {
    return /^\s*\d+\.\s+/.test(line)
  }

  codeBlock(lines) {
    return lines.length >= 2 && lines[0].startsWith("```") && lines[lines.length - 1] === "```"
  }
}
