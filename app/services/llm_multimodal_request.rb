require "json"
require "open3"
require "tmpdir"
require "stringio"

class LlmMultimodalRequest
  Response = Struct.new(:content, :status_code, :body, keyword_init: true)

  def self.call(request_kind:, preference:, instructions:, prompt:, attachments:, person: nil, entry: nil, temperature: nil, model: nil)
    chat = ResearchChatRuntime.build_chat(setting: preference, model:, temperature:)
    chat.with_instructions(instructions)

    response = nil
    raw = nil

    with_built_attachments(attachments) do |built_attachments|
      response = chat.ask(prompt, with: built_attachments)
      raw = response.raw
    end

    Response.new(
      content: response.content.to_s,
      status_code: LlmChatRequest.raw_status(raw),
      body: LlmChatRequest.raw_body(raw)
    )
  end

  def self.with_built_attachments(attachments)
    tempfiles = []
    built_attachments = Array(attachments).flat_map do |attachment|
      attachment_inputs(attachment, tempfiles: tempfiles)
    end

    yield built_attachments
  ensure
    tempfiles.each do |tempfile|
      tempfile.close!
    rescue StandardError
      nil
    end
  end

  def self.attachment_inputs(attachment, tempfiles: [])
    llm_attachment = RubyLLM::Attachment.new(attachment)

    case llm_attachment.type
    when :image
      [ attachment ]
    when :pdf
      pdf_attachment_inputs(attachment, tempfiles: tempfiles)
    when :text
      [ attachment ]
    else
      raise ArgumentError, "Unsupported attachment type: #{llm_attachment.type}"
    end
  end

  def self.pdf_attachment_inputs(attachment, tempfiles: [])
    pdf_image_parts(attachment, tempfiles: tempfiles)
  rescue Errno::ENOENT => error
    Rails.logger.warn("PDF rasterization unavailable, falling back to native PDF attachment: #{error.message}")
    [ attachment ]
  end

  def self.pdf_image_parts(attachment, tempfiles: [])
    blob = attachment.respond_to?(:download) ? attachment : attachment.blob
    png_images = rasterize_pdf(blob.download)

    raise ArgumentError, "Could not rasterize PDF attachment" if png_images.empty?

    png_images.each_with_index.map do |png_bytes, index|
      tempfile = Tempfile.new([ "uncledoc-document-page-#{index + 1}", ".png" ])
      tempfile.binmode
      tempfile.write(png_bytes)
      tempfile.flush
      tempfiles << tempfile
      tempfile.path
    end
  end

  def self.rasterize_pdf(pdf_bytes)
    Dir.mktmpdir("uncledoc-pdf") do |dir|
      pdf_path = File.join(dir, "document.pdf")
      File.binwrite(pdf_path, pdf_bytes)

      stdout, stderr, status = Open3.capture3("pdftoppm", "-r", "300", "-png", "-f", "1", "-l", "5", pdf_path, File.join(dir, "page"))
      raise "pdftoppm failed: #{stderr.presence || stdout}" unless status.success?

      Dir[File.join(dir, "page-*.png")].sort.map { |path| File.binread(path) }
    end
  end
end
