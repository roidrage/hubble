hubble
======

You need a few environmental variables set.

* `export HUBBLE_ENV="production`"
* `export HUBBLE_USER="<myuser>"`
* `export HUBBLE_PASSWORD="<mypassword>"`
* `export HUBBLE_ENDPOINT="http://my-haystack.herokuapp.com/async"`

Test posting from a console trivially:

    $ bundle exec irb
    irb(main):001:0> require "hubble"; Hubble.setup; Hubble.boomtown!
    => #<Net::HTTPOK 200 OK readbody=true>

Using inside a rails app

In application.rb

```ruby
  # Push extra information into the failbot context
  def exception_reporting_filter
    Failbot.reset!
    env = request.env || {}
    request_url =
      "#{request.protocol}#{request.host_with_port}#{request.fullpath}" rescue nil
    context = {
      :user         => current_user.to_s,
      :method       => request.try(:method),
      :user_agent   => env['HTTP_USER_AGENT'],
      :accept       => env['HTTP_ACCEPT'],
      :language     => env['HTTP_ACCEPT_LANGUAGE'],
      :params       => params,
      :session      => session.try(:to_hash),
      :referrer     => request.try(:referrer),
      :remote_ip    => request.try(:remote_ip),
      :url          => request_url,
      :controller   => self.class,
      :action       => params[:action]
    }
    Failbot.push(context)
  end
  before_filter :exception_reporting_filter

```

In config application

```
  require 'hubble/middleware'
  config.middleware.use "Hubble::Rescuer"
```
