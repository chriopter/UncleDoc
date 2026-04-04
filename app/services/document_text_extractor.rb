require "open3"
require "tempfile"

class DocumentTextExtractor
  def self.extract_many(documents)
    Array(documents).filter_map do |document|
      extracted = extract(document)
      next if extracted.blank?

      "File #{filename_for(document)}:\n#{extracted.strip}"
    end.join("\n\n")
  end

  def self.extract(document)
    blob = normalize_blob(document)
    return if blob.nil?

    case blob.content_type
    when "text/plain"
      blob.download.force_encoding("UTF-8")
    when "application/pdf"
      extract_pdf(blob)
    end
  end

  def self.extract_pdf(blob)
    pdf_bytes = blob.download
    tempfile = Tempfile.new([ "uncledoc-document", ".pdf" ])
    tempfile.binmode
    tempfile.write(pdf_bytes)
    tempfile.flush

    stdout, status = Open3.capture2("pdftotext", "-layout", tempfile.path, "-")
    extracted = status.success? ? stdout : nil
    extracted.presence || extract_printable_text(pdf_bytes)
  ensure
    tempfile&.close!
  end

  def self.normalize_blob(document)
    return document if document.respond_to?(:download) && document.respond_to?(:content_type)
    return document.blob if document.respond_to?(:blob)

    nil
  end

  def self.filename_for(document)
    blob = normalize_blob(document)
    blob&.filename&.to_s || "document"
  end

  def self.extract_printable_text(content)
    content.to_s.scan(/[[:alnum:][:space:][:punct:]]{8,}/).map(&:strip).reject(&:blank?).uniq.join("\n")
  end
end
