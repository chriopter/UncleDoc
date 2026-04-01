class BabyDashboardBroadcaster
  def self.broadcast(person)
    new(person).broadcast
  end

  def initialize(person)
    @person = person
  end

  def broadcast
    broadcast_replace("overview_baby_actions", "shared/baby_actions_widget", card_classes: "h-full")
    broadcast_replace("overview_baby_tracking_feeding", "shared/baby_feeding_tracker_widget", card_classes: "flex-1")
    broadcast_replace("overview_baby_tracking_sleep", "shared/baby_sleep_tracker_widget", card_classes: "flex-1")
    broadcast_replace("overview_baby_tracking_diaper", "shared/baby_diaper_tracker_widget", card_classes: "flex-1")
    broadcast_replace("overview_recent_activity", "shared/overview_recent_activity", entries: @person.entries.recent_first, entry_limit: 5, card_classes: "h-full")
    broadcast_replace("entries_list", @person.baby_mode? ? "entries/baby_list" : "entries/protocol_list", entries: @person.entries.recent_first)
    broadcast_replace("overview_person_meta", "shared/overview_person_meta", entries: @person.entries.recent_first)
    broadcast_replace("overview_weight_activity", "shared/weight_activity_widget", card_classes: "h-full")
    broadcast_replace("overview_height_activity", "shared/height_activity_widget", card_classes: "h-full")
  end

  private

  def broadcast_replace(target, partial, extra_locals = {})
    Turbo::StreamsChannel.broadcast_replace_to(
      [ @person, :entries ],
      target: target,
      partial: partial,
      locals: { person: @person }.merge(extra_locals)
    )
  end
end
