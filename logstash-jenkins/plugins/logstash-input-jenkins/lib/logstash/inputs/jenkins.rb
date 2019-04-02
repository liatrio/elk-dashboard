# encoding: utf-8
require "socket" # for Socket.gethostname
require "logstash/inputs/http"
require "ostruct"
require "json"
require "elasticsearch"
require "pp"
require "date"

# This plugin utilizes Jenkins' Logstash plugin linked here:
#   https://wiki.jenkins.io/display/JENKINS/Logstash+Plugin
# The plugin will interpret the Jenkins logs sent to logstash and interpret them according to
# our elasticsearch structure. We currently determine whether or not a project built from a repository
# is a 'build' or 'deploy' job. The plugin then links the a job that has been ran with a corresponding
# bitbucket repo as well as a jira issue. We also calculate the lead-time in this project and report this
# information to elasticsearch.

class LogStash::Inputs::Jenkins < LogStash::Inputs::Http
  
  config_name "jenkins"
  
  # If undefined, Logstash will complain, even if codec is unused.
  default :codec, "json"
  
  config :host, :validate => :string, :default => "jenkins.jx.lead-dev.liatr.io/"
  
  config :port, :validate => :number, :default => 80
  
  # Username for basic authorization
  config :user, :validate => :string, :required => false
  
  # Password for basic authorization
  config :password, :validate => :password, :required => false
  
  config :elastic_port, :validate => :number, :default => 9200
  
  config :elastic_host, :validate => :string, :default => '192.168.0.27'
  
  config :elastic_scheme, :validate => :string, :default => 'http'
  
  public
  
  ## QUERY DATA FROM BUILD JOBS BASED ON GIT COMMIT
  # Make an elasticsearch query based on a git commit (git commits are not 100% guaranteed to be unique but are
  # extremely unlikely to result in collision) and return an existing document, created by the bitbucket logstash
  # plugin, based on that git commit id.
  # arguments:
  #   client: contains an Elasticsearch client object to make the query calls such as .search
  #   body_obj: the current JSON body to extrapolate the git commit from
  # returns: JSON obj containing the document matched
  def get_build_response(client, body_obj)
    commit_id = body_obj['data']['buildVariables']['GIT_COMMIT']
    
    response = client.search index: 'lead_time', body:
      {
        "query": {
          "nested": {
            "path": "commits",
            "query": {
              "term": {
                "commits.id": {
                  "value": commit_id
                }
              }
            }
          }
        }
      }
    return response
  end
  
  ## QUERY DATA FOR DEPLOY JOBS FROM ARTIFACT INFORMATION
  # Make an elasticsearch query based on the artifact information which is created after a job has succeeded
  # in the build stage.
  # arguments:
  #   client: Elasticsearch client
  #   body_obj: JSON body containing the data for the deployment job
  def get_deploy_response(client, body_obj)
    
    artifact_id = body_obj['data']['buildVariables']['id']
    artifact_group = body_obj['data']['buildVariables']['group']
    artifact_version = body_obj['data']['buildVariables']['version']
    
    response = client.search index: 'lead_time', body:
      {
        "query": {
          "bool": {
            "must": [
              {
                "nested": {
                  "path": "builds",
                  "query": {
                    "term": {
                      "builds.artifact.id": {
                        "value": artifact_id
                      }
                    }
                  }
                }
              },
              {
                "nested": {
                  "path": "builds",
                  "query": {
                    "term": {
                      "builds.artifact.group": {
                        "value": artifact_group
                      }
                    }
                  }
                }
              },
              {
                "nested": {
                  "path": "builds",
                  "query": {
                    "term": {
                      "builds.artifact.version": {
                        "value": artifact_version
                      }
                    }
                  }
                }
              }
            ]
          }
        }
      }
    return response
  end


  ## COMMENTS FOR THIS
  # arguments:
  #   client: Elasticsearch client
  #   body_obj: JSON body containing the data for the deployment job
  def handle_build_response(client, body_obj)
    
    artifact_id = body_obj['data']['buildVariables']['id']
    artifact_group = body_obj['data']['buildVariables']['group']
    artifact_version = body_obj['data']['buildVariables']['version']

    c
    
    response = client.search index: 'build_event', body:
      {
        "query": {
          "bool": {
            "must": [
              {
                "query": {
                  "term": {
                    "appName": {
                      "value": artifact_id
                    }
                  }
                }
              },
              {
                "query": {
                  "term": {
                    "groupID": {
                      "value": artifact_group
                    }
                  }
                }
              },
              {
                "query": {
                  "term": {
                    "versionNumber": {
                      "value": artifact_version
                    }
                  }
                }
              }
            ]
          }
        }
      }
    return response
  end
  
  ## CREATING THE LEAD-TIME DOCUMENTS
  # Takes in a JSON body containing all of the logs from a particular build, creates the corresponding needed
  # documents, and generates the data for Lead-time.
  # Arguments:
  #   body: JSON object containing all of the log data from a particular build
  def decode_body(headers, remote_address, body, default_codec, additional_codecs)
    content_type = headers.fetch("content_type", "")
    codec = additional_codecs.fetch(HttpUtil.getMimeType(content_type), default_codec)
    
    client = Elasticsearch::Client.new(:hosts => "#{@elastic_scheme}://#{@elastic_host}:#{@elastic_port}")
    
    #decode the body to get the relevant info we want from JSON from jenkins
    body_obj = JSON.parse(body)
    
    console.log(body_obj)

    build_response = handle_build_response(client, body_obj)
    
    # Iterate through the jenkins' logs to access all of the fields we need
    if build_response['jobType'] == "deploy"
      
      #client.search utilizes the elasticsearch ruby library to send a query to elasticsearch from the logstash plugin
      lt_response = get_deploy_response(client, body_obj)
      
      lt_response["hits"]["hits"].each do |hit|
        lead_time_document = hit["_source"]
        
        deploys = []
        #Determines if the lead_time doc build field exists
        if lead_time_document["deploys"].nil?
          lead_time_document["deploys"] = deploys
        end
        
        #Using the DateTime library, we retrieve the times from the lead-time documents, convert them to epoch format, then converted to an integer
        start_date = DateTime.parse(lead_time_document["started_at"]).to_time.to_i
        create_date = DateTime.parse(lead_time_document["created_at"]).to_time.to_i
        finish_date = DateTime.parse(body_obj['@buildTimestamp']).to_time.to_i
        
        total_time = finish_date - start_date
        progress_time = finish_date - create_date
        
        lead_time_document["deploys"].push(
          {
            environment: body_obj['data']['buildVariables']['ENV'],
            result: body_obj['data']['result'],
            completed_at: body_obj['@buildTimestamp'],
            total_time: total_time,
            progress_time: progress_time,
          }
        )
        
        time_obj =
          {
            total_time: total_time,
            progress_time: progress_time
          }
        if body_obj['data']['buildVariables']['ENV'] == "prod"
          lead_time_document["prod"] = time_obj
        elsif body_obj['data']['buildVariables']['ENV'] == "qa"
          lead_time_document["qa"] = time_obj
        elsif body_obj['data']['buildVariables']['ENV'] == "dev"
          lead_time_document["dev"] = time_obj
        else
          puts "other env"
        end
        
        if body_obj['data']['result'] == 'SUCCESS'
          lead = LogStash::Event.new(lead_time_document)
          lead.set('[@metadata][index]', 'lead_time')
          lead.set('[@metadata][id]', hit['_id'])
          @queue << lead
        end
      end
    
    elsif body_obj['data']['buildVariables']['TYPE'] == nil
      if body_obj['data']['buildVariables']['POM_GROUPID'] != nil &&
        body_obj['data']['buildVariables']['POM_ARTIFACTID'] != nil &&
        body_obj['data']['buildVariables']['POM_VERSION'] != nil
        
        lt_response = get_build_response(client, body_obj)
        builds = []
        
        lt_response["hits"]["hits"].each do |hit|
          lead_time_document = hit["_source"]
          
          #Determines if the lead_time doc build field exists
          if lead_time_document["builds"].nil?
            lead_time_document["builds"] = builds
          end
          
          lead_time_document["builds"].push(
            {
              artifact:
                {
                  id: body_obj['data']['buildVariables']['POM_ARTIFACTID'],
                  group: body_obj['data']['buildVariables']['POM_GROUPID'],
                  name: body_obj['data']['buildVariables']['JOB_NAME'],
                  version: body_obj['data']['buildVariables']['POM_VERSION'],
                  packaging: body_obj['data']['buildVariables']['POM_PACKAGING']
                },
              result: body_obj['data']['result'],
              built_at: body_obj['@buildTimestamp']
            }
          )
          
          if body_obj['data']['result'] == 'SUCCESS'
            lead = LogStash::Event.new(lead_time_document)
            lead.set('[@metadata][index]', 'lead_time')
            lead.set('[@metadata][id]', hit['_id'])
            @queue << lead
          end
        end
      else
        puts "Build job that isn't a maven job"
      end
    else
      puts "Job is neither a build nor deploy"
    end
    
    codec.flush { |event| push_decoded_event(headers, remote_address, event) }
    true
  rescue => e
    @logger.error(
      "unable to process event.",
      :message => e.message,
      :class => e.class.name,
      :backtrace => e.backtrace
    )
    false
  end

end # class LogStash::Inputs::Jenkins
