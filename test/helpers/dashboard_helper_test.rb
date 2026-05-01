require "test_helper"

class DashboardHelperTest < ActionView::TestCase
  test "documents are a first level menu item between cockpit and data" do
    person = Person.create!(name: "Nav Nora", birth_date: Date.new(2024, 1, 1))

    nav_items = shell_nav_items(person, person_files_path(person_slug: person.name))
    labels = nav_items.map { |item| item[:label] }
    files_item = nav_items.find { |item| item[:label] == I18n.t("nav.files") }

    assert_operator labels.index(I18n.t("nav.overview")), :<, labels.index(I18n.t("nav.files"))
    assert_operator labels.index(I18n.t("nav.files")), :<, labels.index(I18n.t("nav.data"))
    assert_not files_item[:child]
    assert files_item[:active]
  end

  test "baby mode adds baby as a first level menu item" do
    person = Person.create!(name: "Baby Bea", birth_date: Date.new(2026, 1, 1), baby_mode: true)

    nav_items = shell_nav_items(person, person_baby_path(person_slug: person.name))
    labels = nav_items.map { |item| item[:label] }
    baby_item = nav_items.find { |item| item[:label] == I18n.t("nav.baby") }

    assert_operator labels.index(I18n.t("nav.overview")), :<, labels.index(I18n.t("nav.baby"))
    assert_not baby_item[:child]
    assert baby_item[:active]
  end

  test "cockpit stays a first level menu item before baby" do
    person = Person.create!(name: "Calendar Clara", birth_date: Date.new(2026, 1, 1), baby_mode: true)

    nav_items = shell_nav_items(person, person_root_path(person_slug: person.name))
    labels = nav_items.map { |item| item[:label] }
    cockpit_item = nav_items.find { |item| item[:label] == I18n.t("nav.overview") }

    assert_operator labels.index(I18n.t("nav.overview")), :<, labels.index(I18n.t("nav.baby"))
    assert_nil labels.index(I18n.t("nav.summary"))
    assert_not cockpit_item[:child]
    assert cockpit_item[:active]
  end
end
