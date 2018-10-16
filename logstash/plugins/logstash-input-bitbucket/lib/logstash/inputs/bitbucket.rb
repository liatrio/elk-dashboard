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

  config :scheme, :validate => :string, :default => 'http'

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

    request_async(
        queue,
        'rest/api/1.0/projects',
        {},
        {},
        'handle_projects_response')

    # request_async(
    #   queue,
    #   "rest/api/1.0/projects/%{project}/repos",
    #   {:project => 'SOCK', :start => 0},
    #   {:headers => {'Authorization' => @authorization}},
    #   'handle_repos_response')

    client.execute!
  end

  private
  def request_async(queue, path, parameters, request_options, callback)
    started = Time.now

    method = parameters[:method] ? parameters.delete(:method) : :get

    uri = "#{@scheme}://#{@hostname}/#{path}" % parameters

    request_options[:headers] = {'Authorization' => @authorization}

    @logger.info("Fetching URL", :method => method, :request => uri)

    client.parallel.send(method, uri, request_options).
        on_success {|response| self.send(callback, queue, uri, parameters, response, Time.now - started)}.
        on_failure {|exception|
          handle_failure(queue, uri, parameters, exception, Time.now - started)
        }
  end

  def handle_projects_response(queue, uri, parameters, response, execution_time)
    # Decode JSON
    body = JSON.parse(response.body)

    @logger.info("Handle Projects Response", :uri => uri, :start => body['start'], :size => body['size'])

    request_count = 0

    # Fetch addition project pages
    unless body['isLastPage']
      request_async(
          queue,
          "rest/api/1.0/projects",
          {},
          {:queue => {'start' => body['nextPageStart']}},
          'handle_projects_response'
      )

      client.execute!
    end

    # Iterate over each project
    body['values'].each do |project|
      @logger.info("Add project", :project => project['key'])

      # Send get repos request
      request_async(
          queue,
          "rest/api/1.0/projects/%{project}/repos",
          {:project => project['key']},
          {},
          'handle_repos_response')

      request_count += 1

      if request_count > 1
        request_count = 0
        client.execute!
      end

      # Push project event into queue
      event = LogStash::Event.new(project)
      event.set('[@metadata][index]', 'project')
      event.set('[@metadata][id]', project['id'])
      queue << event
    end

    if request_count > 0
      # Send HTTP requests
      client.execute!
    end
  end

  # Process response from get repos API request
  def handle_repos_response(queue, uri, parameters, response, execution_time)
    # Decode JSON
    body = JSON.parse(response.body)

    @logger.info("Handle Repos Response", :uri => uri, :project => parameters[:project], :start => body['start'], :size => body['size'])

    request_count = 0

    # Fetch addition repo pages
    unless body['isLastPage']
      request_async(
          queue,
          "rest/api/1.0/projects/%{project}/repos",
        {:project => parameters[:project]},
          {:queue => {'start' => body['nextPageStart']}},
          'handle_repos_response'
      )

      client.execute!
    end

    # Iterate over each repo
    body['values'].each { |repo|
      @logger.info("Add repo", :project => parameters[:project], :repo => repo['slug'])

      # Send get pull requests request
      request_async(
          queue,
          "rest/api/1.0/projects/%{project}/repos/%{repo}/pull-requests",
          {:project => parameters[:project], :repo => repo['slug']},
          {:query => {'state' => 'ALL'}},
          'handle_pull_requests_response')

      request_count +=1

      if request_count > 1
        request_count = 0
        client.execute!
      end

      # Push repo event into queue
      event = LogStash::Event.new(repo)
      event.set("[@metadata][index]", "repo")
      event.set("[@metadata][id]", repo['id'])
      queue << event
    }

    if request_count > 0
      # Send HTTP requests
      client.execute!
    end
  end

  def handle_pull_requests_response(queue, uri, parameters, response, execution_time)
    # Decode JSON
    body = JSON.parse(response.body)

    @logger.info("Handle Pull Requests Response", :uri => uri, :project => parameters[:project], :repo => parameters[:repo], :start => body['start'], :size => body['size'])

    # Fetch addition pull request pages
    unless body['isLastPage']
      request_async(
          queue,
          "rest/api/1.0/projects/%{project}/repos/%{repo}/pull-requests",
          {:project => parameters[:project], :repo => parameters[:repo]},
          {:query => {'state' => 'ALL', 'start' => body['nextPageStart']}},
          'handle_pull_requests_response')

      # Send HTTP requests
      client.execute!
    end

    # Iterate over each pull request
    body['values'].each { |pull_request|
      @logger.info("Add Pull Request", :project => parameters[:project], :repo => parameters[:repo], :pull_request => pull_request['title'])

      # Push repo event into queue
      event = LogStash::Event.new(pull_request)
      event.set("[@metadata][index]", "pull_request")
      event.set("[@metadata][id]", "#{pull_request['toRef']['repository']['project']['id']}-#{pull_request['toRef']['repository']['id']}-#{pull_request['id']}")
      queue << event
    }
  end

  def handle_failure(queue, path, parameters, exception, execution_time)
    @logger.error('HTTP Request failed', :path => path, :parameters => parameters, :exception => exception, :backtrace => exception.backtrace);
  end

  def stop
    # nothing to do in this case so it is not necessary to define stop
    # examples of common "stop" tasks:
    #  * close sockets (unblocking blocking reads/accepts)
    #  * cleanup temporary files
    #  * terminate spawned threads
  end

end # class LogStash::Inputs::Bitbucket
