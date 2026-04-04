require "json"
require "net/http"
require "uri"
require "base64"
require "open3"
require "tempfile"
require "tmpdir"

class LlmMultimodalRequest
  Response = Struct.new(:content, :status_code, :body, keyword_init: true)
  RETRIABLE_ERRORS = [Errno::ECONNRESET, EOFError, Net::ReadTimeout, Net::OpenTimeout, IOError].freeze

  def self.call(request_kind:, preference:, instructions:, prompt:, attachments:, person: nil, entry: nil, temperature: nil, model: nil)
    endpoint = "#{preference.llm_api_base.chomp('/')}/chat/completions"
    payload = build_payload(preference:, instructions:, prompt:, attachments:, temperature:, model:)

    log = LlmLog.create!(
      person: person,
      entry: entry,
      request_kind: request_kind,
      provider: preference.llm_provider,
      model: payload[:model],
      endpoint: endpoint,
      request_payload: JSON.pretty_generate(payload)
    )

    response = perform_request(endpoint:, payload:, preference:)

    normalized_body = normalize_body(response.body)
    log.update!(status_code: response.code.to_i, response_body: normalized_body)

    raise "LLM request failed with status #{response.code}" unless response.code.to_i.between?(200, 299)

    Response.new(
      content: JSON.parse(normalized_body).dig("choices", 0, "message", "content").to_s,
      status_code: response.code.to_i,
      body: normalized_body
    )
  rescue StandardError => error
    log&.update!(error_message: error.message, response_body: log.response_body.presence)
    raise
  end

  def self.build_payload(preference:, instructions:, prompt:, attachments:, temperature: nil, model: nil)
    payload = {
      model: model || preference.llm_model,
      messages: [
        { role: "system", content: instructions },
        { role: "user", content: build_content(prompt:, attachments:) }
      ]
    }
    payload[:temperature] = temperature unless temperature.nil?
    payload
  end

  def self.build_content(prompt:, attachments:)
    [ { type: "text", text: prompt } ] + Array(attachments).flat_map { |attachment| attachment_parts(attachment) }
  end

  def self.attachment_parts(attachment)
    llm_attachment = RubyLLM::Attachment.new(attachment)

    case llm_attachment.type
    when :image
      [ {
        type: "image_url",
        image_url: {
          url: llm_attachment.for_llm
        }
      } ]
    when :pdf
      pdf_image_parts(attachment)
    when :text
      [ {
        type: "text",
        text: llm_attachment.for_llm
      } ]
    else
      raise ArgumentError, "Unsupported attachment type: #{llm_attachment.type}"
    end
  end

  def self.pdf_image_parts(attachment)
    blob = attachment.respond_to?(:download) ? attachment : attachment.blob
    png_images = rasterize_pdf(blob.download)

    raise ArgumentError, "Could not rasterize PDF attachment" if png_images.empty?

    png_images.map do |png_bytes|
      {
        type: "image_url",
        image_url: {
          url: "data:image/png;base64,#{Base64.strict_encode64(png_bytes)}"
        }
      }
    end
  end

  def self.rasterize_pdf(pdf_bytes)
    Dir.mktmpdir("uncledoc-pdf") do |dir|
      pdf_path = File.join(dir, "document.pdf")
      File.binwrite(pdf_path, pdf_bytes)

      stdout, stderr, status = Open3.capture3("pdftoppm", "-png", "-f", "1", "-l", "3", pdf_path, File.join(dir, "page"))
      raise "pdftoppm failed: #{stderr.presence || stdout}" unless status.success?

      Dir[File.join(dir, "page-*.png")].sort.map { |path| File.binread(path) }
    end
  end

  def self.perform_request(endpoint:, payload:, preference:)
    uri = URI.parse(endpoint)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{preference.llm_runtime_api_key}" if preference.llm_runtime_api_key.present?

    if preference.llm_provider == "openrouter"
      request["HTTP-Referer"] = "http://localhost:3000"
      request["X-Title"] = "UncleDoc"
    end

    request.body = payload.to_json

    attempts = 0

    begin
      attempts += 1

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
    rescue *RETRIABLE_ERRORS
      raise if attempts >= 3

      retry
    end
  end

  def self.normalize_body(body)
    body.to_s.dup.force_encoding("UTF-8").scrub
  end
end
