require 'faraday'

module Hubble::Backend
  class Haystack
    def initialize(url)
      @url = URI.parse(url)
    end

    def report(data)
      send_data(data)
    end

    def reports
      []
    end

    def user
      ENV["HUBBLE_USER"] || "hubble"
    end

    def password
      ENV["HUBBLE_PASSWORD"] || "unknown"
    end

    def password?
      password != "unknown"
    end

    def send_data(data)
      # make a post
      http_client.post do |req|
        req.body = { 'json' => JSON.dump(data) }
      end
    end

    def http_client
      Faraday.new(@url, http_options) do |f|
        f.request :url_encoded
        f.adapter :net_http
        f.basic_auth(user, password) if password?
      end
    end

    def http_options
      if Hubble.config['ssl']
        { :ssl => Hubble.config['ssl'] }
      else
        { }
      end
    end
  end
end
