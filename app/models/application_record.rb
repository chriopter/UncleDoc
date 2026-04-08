class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  require "ruby_llm/active_record/acts_as"
  include RubyLLM::ActiveRecord::ActsAs
end
