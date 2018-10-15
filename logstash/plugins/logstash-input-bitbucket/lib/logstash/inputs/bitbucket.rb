# encoding: utf-8
require "logstash/inputs/base"
require 'logstash/plugin_mixins/http_client'
require 'logstash/event'
require 'logstash/json'
require "stud/interval"
require "socket" # for Socket.gethostname
require "rufus/scheduler"
require "json"
require "ostruct"


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
    @authorization = "Bearer #{@token}"
    @logger.info('Register BitBucket Input', :schedule => @schedule, :hostname => @hostname, :port => @port)
  end

  def run(queue)
    @logger.info('RUN')
    #schedule hash must contain exactly one of the allowed keys
    msg_invalid_schedule = "Invalid config. schedule hash must contain " +
        "exactly one of the following keys - cron, at, every or in"
    raise Logstash::ConfigurationError, msg_invalid_schedule if @schedule.keys.length != 1
    schedule_type = @schedule.keys.first
    schedule_value = @schedule[schedule_type]
    raise LogStash::ConfigurationError, msg_invalid_schedule unless Schedule_types.include?(schedule_type)

    @scheduler = Rufus::Scheduler.new(:max_work_threads => 1)
    #as of v3.0.9, :first_in => :now doesn't work. Use the following workaround instead
    opts = schedule_type == "every" ? {:first_in => 0.01} : {}
    @scheduler.send(schedule_type, schedule_value, opts) {run_once(queue)}
    @scheduler.join
  end

  def run_once(queue)
    @logger.info('RUN ONCE')

    request_async(queue, [:get, 'http://bitbucket.liatr.io/rest/api/1.0/projects', Hash[:headers => {'Authorization' => @authorization}]], 'handle_projects_response')

    client.execute!
  end

  private
  def request_async(queue, request, callback)
    @logger.info("Fetching URL", :request => request)
    started = Time.now

    method, *request_opts = request
    client.async.send(method, *request_opts).
        on_success {|response| self.send(callback, queue, request, response, Time.now - started)}.
        on_failure {|exception|
          handle_failure(queue, request, exception, Time.now - started)
        }
  end

  def handle_projects_response(queue, request, response, execution_time)
    #@logger.info('HANDLE PROJECTS RESPONSE', :headers => response.headers, :body => response.body)
    obj = JSON.parse(response.body)

    obj['values'].each do |project|
      request_async(queue, [:get, "http://bitbucket.liatr.io/rest/api/1.0/projects/#{project['key']}/repos", Hash[:headers => {'Authorization' => @authorization}]], 'handle_repos_response')
      event = LogStash::Event.new(project)
      @logger.info("PROJECT EVENT", :event => event)
      queue << event
    end
    client.execute!
  end

  # Process response from get repos API request
  def handle_repos_response(queue, request, response, execution_time)
    # Decode JSON
    decoded = LogStash::Json.load(response.body)

    @logger.info("Handle Repos Response", :request => request, :start => decoded['start'], :size => decoded['size'])

    # Fetch addition repo pages
    unless decoded['isLastPage']
      request_async(
          queue,
          [:get, "http://bitbucket.liatr.io/rest/api/1.0/projects/SOCK/repos?start=#{decoded['nextPageStart']}"],
          'handle_repos_response'
      )
    end

    # Iterate over each repo
    decoded['values'].each { |repo|
      @logger.info("Add repo", :project => repo['project']['name'], :repo => repo['name'])

      # Send get pull requests request
      request_async(
          queue,
          [:get, "http://bitbucket.liatr.io/rest/api/1.0/projects/#{repo['project']['key']}/repos/#{repo['slug']}/pull-requests?state=ALL", Hash[:headers => {'Authorization' => @authorization}]],
          'handle_pull_requests_response')

      # Push repo event into queue
      event = LogStash::Event.new(repo)
      queue << event
    }

    # Send HTTP requests
    client.execute!
  end

  def handle_pull_requests_response(queue, request, response, execution_time)
    @logger.info("HANDLE PULL REQUESTS RESPONSE")
    # @logger.info("HANDLE PULL REQUESTS RESPONSE", :body => response.body)

  end

  def handle_failure(queue, request, exception, execution_time)
    @logger.error('HTTP Request failed', :request => request, :exception => exception, :backtrace => exception.backtrace);
  end

  def stop
    # nothing to do in this case so it is not necessary to define stop
    # examples of common "stop" tasks:
    #  * close sockets (unblocking blocking reads/accepts)
    #  * cleanup temporary files
    #  * terminate spawned threads
  end

end # class LogStash::Inputs::Bitbucket
