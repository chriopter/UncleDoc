class HealthkitController < ApplicationController
  skip_forgery_protection only: [ :sync, :reset ]
  before_action :set_healthkit_person, only: [ :status, :sync, :reset ]

  def people
    render json: {
      people: Person.recent_first.map { |person| { uuid: person.uuid, name: person.name } }
    }
  end

  def status
    sync = @person.healthkit_sync

    render json: {
      person: { uuid: @person.uuid, name: @person.name },
      sync: {
        status: sync&.status || "pending",
        last_synced_at: sync&.last_synced_at,
        last_successful_sync_at: sync&.last_successful_sync_at,
        synced_record_count: sync&.synced_record_count.to_i,
        last_error: sync&.last_error,
        details: sync&.details || {}
      }
    }
  end

  def sync
    records = Array(params[:records]).filter_map { |record| build_record_payload(record) }

    sync = HealthkitSync.find_or_initialize_by(person: @person, device_id: params[:device_id].to_s)
    sync.assign_attributes(
      status: params[:status].presence_in(HealthkitSync::STATUSES) || (params[:completed] ? "synced" : "syncing"),
      last_synced_at: Time.current,
      last_successful_sync_at: params[:completed] ? Time.current : sync.last_successful_sync_at,
      synced_record_count: @person.healthkit_records.count + records.size,
      last_error: params[:last_error].presence,
      details: sync.details.merge(sync_details_payload)
    )
    sync.save!

    upsert_healthkit_records(records) if records.any?
    sync.update!(synced_record_count: @person.healthkit_records.count)

    render json: {
      ok: true,
      imported_count: records.size,
      total_count: @person.healthkit_records.count,
      sync: {
        status: sync.status,
        last_synced_at: sync.last_synced_at,
        last_successful_sync_at: sync.last_successful_sync_at,
        synced_record_count: sync.synced_record_count,
        last_error: sync.last_error,
        details: sync.details
      }
    }
  end

  def reset
    @person.healthkit_records.destroy_all
    @person.healthkit_sync&.destroy

    respond_to do |format|
      format.html { redirect_to settings_path(section: :healthkit), notice: t("settings.healthkit.flash.reset") }
      format.json { render json: { ok: true } }
    end
  end

  private

  def set_healthkit_person
    uuid = params[:person_uuid].presence || params.dig(:healthkit, :person_uuid).presence
    @person = Person.find_by!(uuid: uuid)
  end

  def build_record_payload(record)
    return unless record.respond_to?(:to_h)

    payload = record.to_h.deep_symbolize_keys
    return if payload[:external_id].blank? || payload[:record_type].blank? || payload[:start_at].blank?

    {
      person_id: @person.id,
      device_id: params[:device_id].to_s,
      external_id: payload[:external_id],
      record_type: payload[:record_type],
      source_name: payload[:source_name],
      start_at: Time.zone.parse(payload[:start_at].to_s),
      end_at: payload[:end_at].present? ? Time.zone.parse(payload[:end_at].to_s) : nil,
      payload: payload[:payload].is_a?(Hash) ? payload[:payload] : {},
      created_at: Time.current,
      updated_at: Time.current
    }
  rescue ArgumentError
    nil
  end

  def upsert_healthkit_records(records)
    HealthkitRecord.upsert_all(records, unique_by: :index_healthkit_records_on_person_id_and_external_id)
  end

  def sync_details_payload
    {}.tap do |details|
      details[:phase] = params[:phase] if params[:phase].present?
      details[:sample_type] = params[:sample_type] if params[:sample_type].present?
      details[:batch_count] = params[:batch_count].to_i if params[:batch_count].present?
      details[:estimated_total_count] = params[:estimated_total_count].to_i if params[:estimated_total_count].present?
      details[:initial_sync_completed] = ActiveModel::Type::Boolean.new.cast(params[:initial_sync_completed]) if params.key?(:initial_sync_completed)
    end
  end
end
