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

      post = Net::HTTP::Post.new(@url.path)
      post.set_form_data('json' => JSON.dump(data))

      post.basic_auth(user, password) if password?

      # make request
      req = Net::HTTP.new(@url.host, @url.port)

      # use SSL if applicable
      req.use_ssl = true if @url.scheme == "https"

      # push it through
      req.start { |http| http.request(post) }
    end
  end
end
