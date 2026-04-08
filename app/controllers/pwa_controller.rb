class PwaController < ApplicationController
  def manifest
    render formats: :json
  end

  def service_worker
    render formats: :js
  end
end
