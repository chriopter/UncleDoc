class LlmToolCall < ApplicationRecord
  self.table_name = "llm_tool_calls"

  acts_as_tool_call message: :llm_message, message_class: "LlmMessage", result: :result, result_class: "LlmMessage"
end
