#-------------------------------------------------------------------------------
# # Copyright (c) Microsoft Open Technologies, Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A
# PARTICULAR PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
#
# See the Apache License, Version 2.0 for the specific language
# governing permissions and limitations under the License.
#-------------------------------------------------------------------------------

require_relative './logging'

require 'json'
require 'jwt'
require 'openssl'
require 'securerandom'

module ADAL
  # The return type of all of the instance methods that return tokens.
  class TokenResponse
    extend Logging

    ##
    # Constructs a TokenResponse from a raw hash. It will return either a
    # SuccessResponse or an ErrorResponse depending on the fields of the hash.
    #
    # @param Hash raw_response
    #   The body of the HTTP response expressed as a raw hash.
    # @return TokenResponse
    def self.parse(raw_response)
      logger.verbose('Attempting to create a TokenResponse from raw response.')
      if raw_response.nil?
        ErrorResponse.new
      elsif raw_response['error']
        ErrorResponse.new(JSON.parse(raw_response))
      else
        SuccessResponse.new(JSON.parse(raw_response))
      end
    end

    public

    ##
    # Shorthand for checking if a token response is successful or failed.
    #
    # @return Boolean
    def error?
      self.respond_to? :error
    end
  end

  # A token response that contains an access token. All fields are read only
  # and may be nil. Some fields are only populated in certain flows.
  class SuccessResponse < TokenResponse
    include Logging

    # These fields may or may not be included in the response from the token
    # endpoint.
    OAUTH_FIELDS = [:access_token, :expires_in, :expires_on, :id_token,
                    :not_before, :refresh_token, :resource, :scope, :token_type]
    OAUTH_FIELDS.each { |field| attr_reader field }
    attr_reader :user_id

    ##
    # Constructs a SuccessResponse from a collection of fields returned from a
    # token endpoint.
    #
    # @param Hash
    def initialize(fields = {})
      fields.each { |k, v| instance_variable_set("@#{k}", v) }
      parse_id_token(id_token)
      @expires_on = @expires_in.to_i + Time.now.to_i
      logger.info('Parsed a SuccessResponse with access token digest ' \
                  "#{Digest::SHA256.hexdigest @access_token.to_s} and " \
                  'refresh token digest ' \
                  "#{Digest::SHA256.hexdigest @refresh_token.to_s}.")
    end

    ##
    # Parses the raw id token into an ADAL::UserIdentifier.
    #
    # @param String id_token
    #   The id token to parse
    #   Adds an id token to the token response if one is not present
    def parse_id_token(id_token)
      if id_token.nil?
        logger.warn('No id token found.')
        return
      end
      logger.verbose('Attempting to decode id token in token response.')
      claims = JWT.decode(id_token.to_s, nil, false).first
      @id_token = id_token
      @user_id = ADAL::UserIdentifier.new(claims || {})
    end
  end

  # A token response that contains an error code.
  class ErrorResponse < TokenResponse
    include Logging

    OAUTH_FIELDS = [:error, :error_description, :error_codes, :timestamp,
                    :trace_id, :correlation_id, :submit_url, :context]
    OAUTH_FIELDS.each { |field| attr_reader field }

    # Constructs a Error from a collection of fields returned from a
    # token endpoint.
    #
    # @param Hash
    def initialize(fields = {})
      fields.each { |k, v| instance_variable_set("@#{k}", v) }
      logger.error("Parsed an ErrorResponse with error: #{@error} and error " \
                   "description: #{@error_description}.")
    end
  end
end
