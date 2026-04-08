class RemoveLocaleAndDateFormatFromPeople < ActiveRecord::Migration[8.1]
  def change
    # Intentionally left as a no-op.
    #
    # In SQLite, removing columns from `people` rebuilds the table. Because
    # `entries` and `llm_logs` reference `people` with `ON DELETE CASCADE`, the
    # temporary drop/recreate path can wipe production data during migration.
    #
    # The app no longer reads these columns, so keeping them in the table is the
    # safe choice for live SQLite deployments.
  end
end
