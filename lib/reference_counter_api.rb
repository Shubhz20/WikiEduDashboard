# frozen_string_literal: true

require_dependency "#{Rails.root}/lib/errors/api_error_handling"

# Gets data from reference-counter Toolforge tool
# https://toolsadmin.wikimedia.org/tools/id/reference-counter
class ReferenceCounterApi
  include ApiErrorHandling

  TOOLFORGE_SERVER_URL = 'https://reference-counter.toolforge.org'

  def self.valid_wiki?(wiki)
    return wiki.project != 'wikidata'
  end

  def initialize(wiki, update_service = nil)
    raise InvalidProjectError unless ReferenceCounterApi.valid_wiki?(wiki)
    @project_code = wiki.project
    @language_code = wiki.language
    @update_service = update_service
  end

  # Return the number of references got from the references counter API.
  # Return -1 if the response is different from 200 OK, or an error happens.
  def get_number_of_references_from_revision_id(rev_id)
    response = toolforge_server.get(references_query_url(rev_id))
    parsed_response = Oj.load(response.body)
    if response.status == 200
      return parsed_response['num_ref']
    else
      # Log the error and return -1
      Sentry.capture_message 'Non-200 response hitting references counter API',
                             level: 'warning', extra: { project_code: @project_code,
                             language_code: @language_code, rev_id:,
                             status_code: response.status, content: parsed_response }
      return -1
    end
  rescue StandardError => e
    # Log any error
    log_error(e, update_service: @update_service,
              sentry_extra: { project_code: @project_code,
              language_code: @language_code, rev_id: })
    return -1
  end

  class InvalidProjectError < StandardError
  end

  private

  def references_query_url(rev_id)
    "/api/v1/references/#{@project_code}/#{@language_code}/#{rev_id}"
  end

  def toolforge_server
    connection = Faraday.new(
      url: TOOLFORGE_SERVER_URL,
      headers: {
        'Content-Type': 'application/json'
      }
    )
    # connection.headers['User-Agent'] = ENV['visualizer_url'] + ' ' + Rails.env
    connection
  end

  TYPICAL_ERRORS = [Faraday::TimeoutError,
                    Faraday::ConnectionFailed].freeze
end
