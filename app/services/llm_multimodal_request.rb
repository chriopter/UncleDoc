require "json"
require "open3"
require "tmpdir"
require "stringio"

class LlmMultimodalRequest
  Response = Struct.new(:content, :status_code, :body, keyword_init: true)

  def self.call(request_kind:, preference:, instructions:, prompt:, attachments:, person: nil, entry: nil, temperature: nil, model: nil)
    chat = ResearchChatRuntime.build_chat(setting: preference, model:, temperature:)
    chat.with_instructions(instructions)

    response = chat.ask(prompt, with: build_attachments(attachments))
    raw = response.raw

    Response.new(
      content: response.content.to_s,
      status_code: LlmChatRequest.raw_status(raw),
      body: LlmChatRequest.raw_body(raw)
    )
  end

  def self.build_attachments(attachments)
    Array(attachments).flat_map do |attachment|
      attachment_inputs(attachment)
    end
  end

  def self.attachment_inputs(attachment)
    llm_attachment = RubyLLM::Attachment.new(attachment)

    case llm_attachment.type
    when :image
      [ attachment ]
    when :pdf
      pdf_image_parts(attachment)
    when :text
      [ attachment ]
    else
      raise ArgumentError, "Unsupported attachment type: #{llm_attachment.type}"
    end
  end

  def self.pdf_image_parts(attachment)
    blob = attachment.respond_to?(:download) ? attachment : attachment.blob
    png_images = rasterize_pdf(blob.download)

    raise ArgumentError, "Could not rasterize PDF attachment" if png_images.empty?

    png_images.each_with_index.map do |png_bytes, index|
      {
        io: StringIO.new(png_bytes),
        filename: "document-page-#{index + 1}.png",
        content_type: "image/png"
      }
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
