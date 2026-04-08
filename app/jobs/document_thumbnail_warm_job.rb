class DocumentThumbnailWarmJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(entry_id)
    entry = Entry.find_by(id: entry_id)
    return unless entry

    document = entry.documents.first
    return unless document&.representable?

    representation = if document.previewable?
      document.preview(resize_to_limit: [ 360, 480 ])
    else
      document.variant(resize_to_limit: [ 360, 480 ])
    end

    representation.processed
  rescue ActiveStorage::UnpreviewableError, ActiveStorage::InvariableError
    nil
  end
end
