module Hubble
  # Rack middleware that rescues exceptions raised from the downstream app and
  # reports to Hubble::Client. The exception is reraised after being sent to
  # hubble so upstream middleware can still display an error page or
  # whathaveyou.
  class Rescuer
    def initialize(app, other={})
      @app = app
      @other = other
    end

    def call(env)
      start = Time.now
      @app.call(env)
    rescue Object => boom
      elapsed = Time.now - start
      self.class.report(boom, env, @other.merge(:time => elapsed.to_s))
      raise
    end

    def self.report(boom, env, other={})
      request = Rack::Request.new(env)
      Hubble.report(boom, other.merge({
        :method       => request.request_method,
        :user_agent   => env['HTTP_USER_AGENT'],
        :params       => (request.params.inspect rescue nil),
        :session      => (request.session.inspect rescue nil),
        :referrer     => request.referrer,
        :remote_ip    => request.ip,
        :url          => request.url
      }))
    end
  end
end
