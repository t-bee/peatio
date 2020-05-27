# frozen_string_literal: true

module Coingecko
  class Client

    DEFAULT_ENDPOINT = "https://api.coingecko.com/"
    DEFAULT_API_PREFIX = "/api/v3"

    attr_accessor :headers, :endpoint

    def initialize(options={})
      @idle_timeout = options.fetch(:idle_timeout, 5)
      @api_prefix = options.fetch(:api_prefix, DEFAULT_API_PREFIX)
      @endpoint = options.fetch(:endpoint, DEFAULT_ENDPOINT)
      @headers = {"Accept"       => "application/json",
                  "Content-Type" => "application/json"}
    end

    def get(path, params={})
      path_with_prefix = File.join(@api_prefix, path)
      response = connection.get(path_with_prefix) do |req|
        req.headers = headers
        req.params  = params.as_json
      end

      JSON(response.body).deep_symbolize_keys
    end

    private

    def connection
      @connection ||= Faraday.new(@endpoint) do |f|
        f.response :raise_error
        f.adapter :net_http_persistent, pool_size: 5, idle_timeout: @idle_timeout
      end
    end
  end
end

# contract_address = '0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2'
# Coingecko.default_client.get("coins/ethereum/contract/#{contract_address}")
#
