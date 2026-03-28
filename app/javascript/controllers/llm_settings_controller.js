import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["provider", "apiKey", "model", "status", "credentialsHint", "endpointHint"]
  static values = { path: String, initialModel: String }

  connect() {
    this.lookup()
  }

  queueLookup() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.lookup(), 350)
  }

  lookup() {
    this.updateStatus(this.statusTarget.dataset.loadingText || "Loading available models...")

    fetch(this.pathValue, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({
        llm_provider: this.providerTarget.value,
        llm_api_key: this.apiKeyTarget.value,
        llm_model: this.modelTarget.value || this.initialModelValue
      })
    })
      .then((response) => response.json())
      .then((payload) => this.renderModels(payload))
      .catch(() => this.renderModels({ models: [], status: this.statusTarget.dataset.failedText, empty_label: "No models available" }))
  }

  renderModels(payload) {
    const selectedModel = payload.selected_model || ""

    this.modelTarget.innerHTML = ""

    if (payload.models && payload.models.length > 0) {
      payload.models.forEach((modelId) => {
        const option = document.createElement("option")
        option.value = modelId
        option.textContent = modelId
        option.selected = modelId === selectedModel
        this.modelTarget.appendChild(option)
      })

      this.modelTarget.disabled = false
    } else {
      const option = document.createElement("option")
      option.value = ""
      option.textContent = payload.empty_label || "No models available"
      this.modelTarget.appendChild(option)
      this.modelTarget.disabled = true
    }

    if (payload.env_key) {
      this.credentialsHintTarget.textContent = this.credentialsHintTarget.dataset.template.replace("%{env_key}", payload.env_key)
    }

    if (payload.api_base) {
      this.endpointHintTarget.textContent = this.endpointHintTarget.dataset.template.replace("%{endpoint}", payload.api_base)
      this.endpointHintTarget.classList.remove("hidden")
    } else {
      this.endpointHintTarget.textContent = ""
      this.endpointHintTarget.classList.add("hidden")
    }

    this.initialModelValue = selectedModel
    this.updateStatus(payload.status)
  }

  updateStatus(message) {
    this.statusTarget.textContent = message || ""
  }
}
