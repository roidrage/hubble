require 'yaml'
require 'json'
require 'net/https'
require 'digest/md5'
require 'logger'
require 'socket'

require 'hubble/version'

module Hubble
  # Backends for local testing or hitting a Haystack Endpoint
  module Backend
    autoload :Memory,   'hubble/backend/memory'
    autoload :Haystack, 'hubble/backend/haystack'
  end

  # Reset the backend and optionally override the environment configuration.
  #
  # config - The optional configuration Hash.
  #
  # Returns nothing.
  def setup(_config={})
    config.merge!(_config)
    @backend = nil
    @raise_errors = nil
  end

  # Hash of configuration data from lib/hubble/config.yml.
  def config
    @config ||= YAML.load_file(config_file)[environment]
  end

  # Location of config.yml config file.
  def config_file
    File.expand_path('../hubble/config.yml', __FILE__)
  end

  # The current "environment". This dictates which section will be read
  # from the config.yml config file.
  def environment
    @environment ||= ENV['HUBBLE_ENV'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
  end

  # The name of the backend that should be used to post exceptions to the
  # exceptions-collection service. The fellowing backends are available:
  #
  # memory - Dummy backend that simply save exceptions in memory. Typically
  #          used in testing environments.
  #
  # heroku - In-process posting for outside of vpn apps
  #
  # Returns the String backend name. See also `Hubble.backend`.
  def backend_name
    config['backend']
  end

  # Determines whether exceptions are raised instead of being reported to
  # the exception tracking service. This is typically enabled in development
  # and test environments. When set true, no exception information is reported
  # and the exception is raised instead. When false (default in production
  # environments), the exception is reported to the exception tracking service
  # but not raised.
  def raise_errors?
    if @raise_errors.nil?
      config['raise_errors']
    else
      @raise_errors
    end
  end
  attr_writer :raise_errors

  # The URL where exceptions should be posted. Each exception is converted into
  # JSON and posted to this URL.
  def haystack
    ENV['HUBBLE_ENDPOINT'] || config['haystack']
  end

  # Stack of context information to include in the next Hubble report. These
  # hashes are condensed down into one and included in the next report. Don't
  # mess with this structure directly - use the #push and #pop methods.
  def context
    @context ||= [{'server' => hostname, 'type' => 'exception'}]
  end

  # Add info to be sent in the next Hubble report, should one occur.
  #
  # info  - Hash of name => value pairs to include in the exception report.
  # block - When given, the info is removed from the current context after the
  #         block is executed.
  #
  # Returns the value returned by the block when given; otherwise, returns nil.
  def push(info={})
    context.push(info)
    yield if block_given?
  ensure
    pop if block_given?
  end

  # Remove the last info hash from the context stack.
  def pop
    context.pop if context.size > 1
  end

  # Reset the context stack to a pristine state.
  def reset!
    @context = [context[0]]
  end

  # Public: Sends an exception to the exception tracking service along
  # with a hash of custom attributes to be included with the report. When the
  # raise_errors option is set, this method raises the exception instead of
  # reporting to the exception tracking service.
  #
  # e     - The Exception object. Must respond to #message and #backtrace.
  # other - Hash of additional attributes to include with the report.
  #
  # Examples
  #
  #   begin
  #     my_code
  #   rescue => e
  #     Hubble.report(e, :user => current_user)
  #   end
  #
  # Returns nothing.
  def report(e, other = {})
    if raise_errors?
      squash_context(exception_info(e), other) # surface problems squashing
      raise e
    else
      report!(e, other)
    end
  end

  def report!(e, other = {})
    data = squash_context(exception_info(e), other)
    backend.report(data)
  rescue Object => i
    # don't fail for any reason
    logger.debug "Hubble: #{data.inspect}" rescue nil
    logger.debug e.message rescue nil
    logger.debug e.backtrace.join("\n") rescue nil
    logger.debug i.message rescue nil
    logger.debug i.backtrace.join("\n") rescue nil
  end

  # Public: exceptions that were reported. Only available when using the
  # memory and file backends.
  #
  # Returns an Array of exceptions data Hash.
  def reports
    backend.reports
  end

  # Combines all context hashes into a single hash converting non-standard
  # data types in values to strings, then combines the result with a custom
  # info hash provided in the other argument.
  #
  # other - Optional array of hashes to also squash in on top of the context
  #         stack hashes.
  #
  # Returns a Hash with all keys and values.
  def squash_context(*other)
    merged = {}
    (context + other).each do |hash|
      hash.each do |key, value|
        value = (value.call rescue nil) if value.kind_of?(Proc)
        merged[key.to_s] =
          case value
          when String, Numeric, true, false
            value.to_s
          else
            value.inspect
          end
      end
    end
    merged
  end

  # Extract exception info into a simple Hash.
  #
  # e - The exception object to turn into a Hash.
  #
  # Returns a Hash including a 'class', 'message', 'backtrace', and 'rollup'
  #   keys. The rollup value is a MD5 hash of the exception class, file, and line
  #   number and is used to group exceptions.
  def exception_info(e)
    backtrace = Array(e.backtrace)[0, 500]

    res = {
      'class'      => e.class.to_s,
      'message'    => e.message,
      'backtrace'  => backtrace.join("\n"),
      'rollup'     => Digest::MD5.hexdigest("#{e.class}#{backtrace[0]}")
    }

    if original = (e.respond_to?(:original_exception) && e.original_exception)
      remote_backtrace  = []
      remote_backtrace << original.message
      if original.backtrace
        remote_backtrace.concat(Array(original.backtrace)[0,500])
      end
      res['remote_backtrace'] = remote_backtrace.join("\n")
    end

    res
  end

  # Load and initialize the exception reporting backend as specified by
  # the 'backend' configuration option.
  #
  # Raises ArgumentError for invalid backends.
  def backend
    @backend ||= backend!
  end
  attr_writer :backend

  def backend!
    case backend_name
    when 'memory'
      Hubble::Backend::Memory.new
    when 'haystack'
      Hubble::Backend::Haystack.new(haystack)
    else
      raise ArgumentError, "Unknown backend: #{backend_name.inspect}"
    end
  end

  # Installs an at_exit hook to report exceptions that raise all the way out of
  # the stack and halt the interpreter. This is useful for catching boot time
  # errors as well and even signal kills.
  #
  # To use, call this method very early during the program's boot to cover as
  # much code as possible:
  #
  #   require 'hubble'
  #   Hubble.install_unhandled_exception_hook!
  #
  # Returns true when the hook was installed, nil when the hook had previously
  # been installed by another component.
  def install_unhandled_exception_hook!
    # only install the hook once, even when called from multiple locations
    return if @unhandled_exception_hook_installed

    # the $! is set when the interpreter is exiting due to an exception
    at_exit do
      boom = $!
      if boom && !raise_errors? && !boom.is_a?(SystemExit)
        report(boom, 'argv' => ([$0]+ARGV).join(" "), 'halting' => true)
      end
    end

    @unhandled_exception_hook_installed = true
  end

  def logger
    @logger ||= Logger.new($stderr)
  end

  def logger=(logger)
    @logger = logger
  end

  def hostname
    @hostname ||= Socket.gethostname
  end

  # Public: Trigger an Exception
  #
  # Returns nothing.
  def boomtown!
    e = ArgumentError.new("BOOMTOWN")
    report(e)
  end

  extend self
end
