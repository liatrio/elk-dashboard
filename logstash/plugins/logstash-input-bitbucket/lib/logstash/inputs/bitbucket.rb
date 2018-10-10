# encoding: utf-8
require "logstash/inputs/base"
require 'logstash/plugin_mixins/http_client'
require "stud/interval"
require "socket" # for Socket.gethostname
require "rufus/scheduler"

# Generate a repeating message.
#
# This plugin is intented only as an example.

class LogStash::Inputs::Bitbucket < LogStash::Inputs::Base
  include LogStash::PluginMixins::HttpClient

  config_name "bitbucket"

  # If undefined, Logstash will complain, even if codec is unused.
  default :codec, "json"

  # Schedule of when to periodically poll from the urls
  # Format: A hash with
  #   + key: "cron" | "every" | "in" | "at"
  #   + value: string
  # Examples:
  #   a) { "every" => "1h" }
  #   b) { "cron" => "* * * * * UTC" }
  # See: rufus/scheduler for details about different schedule options and value string format
  config :schedule, :validate => :hash, :required => true

  config :hostname, :validate => :string, :default => 'localhost'

  config :port, :validate => :number, :default => 80

  config :token, :validate => :string, :required => true

  public

  Schedule_types = %w(cron every at in)

  def register
    @host = Socket.gethostname.force_encoding(Encoding::UTF_8)

    @logger.info('Register BitBucket Input', :schedule => @schedule, :hostname => @hostname, :port => @port)
  end # def register

  def run(queue)
    #schedule hash must contain exactly one of the allowed keys
    msg_invalid_schedule = "Invalid config. schedule hash must contain " +
        "exactly one of the following keys - cron, at, every or in"
    raise Logstash::ConfigurationError, msg_invalid_schedule if @schedule.keys.length !=1
    schedule_type = @schedule.keys.first
    schedule_value = @schedule[schedule_type]
    raise LogStash::ConfigurationError, msg_invalid_schedule unless Schedule_types.include?(schedule_type)

    @scheduler = Rufus::Scheduler.new(:max_work_threads => 1)
    #as of v3.0.9, :first_in => :now doesn't work. Use the following workaround instead
    opts = schedule_type == "every" ? { :first_in => 0.01 } : {}
    @scheduler.send(schedule_type, schedule_value, opts) { run_once(queue) }
    @scheduler.join
  end # def run

  def run_once(queue)

  end

  private
  def request_async(queue, name, request, callback)
    @logger.debug? && @logger.debug("Fetching URL", :name => name, :url => request)
    started = Time.now

    method, *request_opts = request
    client.async.send(method, *request_opts).
        on_success {|response| self.send(callback, queue, name, request, response, Time.now - started)}.
        on_failure {|exception|
          handle_failure(queue, name, request, exception, Time.now - started)
        }
  end

  def handle_projects_response(queue, name, request, response, execution_time)

  end

  def handle_repos_response(queue, name, request, response, execution_time)

  end

  def handle_pull_requests_response(queue, name, request, response, execution_time)

  end

  def stop
    # nothing to do in this case so it is not necessary to define stop
    # examples of common "stop" tasks:
    #  * close sockets (unblocking blocking reads/accepts)
    #  * cleanup temporary files
    #  * terminate spawned threads
  end
end # class LogStash::Inputs::Bitbucket
