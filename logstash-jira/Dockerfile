FROM docker.elastic.co/logstash/logstash:6.4.0

USER root

RUN logstash-plugin install logstash-filter-prune
RUN yum install -y sudo git vim

USER logstash
ENV PATH=$PATH:/usr/share/logstash/vendor/jruby/bin/
RUN gem install bundler

ADD --chown=logstash config /usr/share/logstash/config
ADD --chown=logstash pipeline /usr/share/logstash/pipeline
ADD --chown=logstash plugins /usr/share/logstash/plugins

WORKDIR /usr/share/logstash/plugins/logstash-input-jira
RUN bundler install 
RUN gem build /usr/share/logstash/plugins/logstash-input-jira/logstash-input-jira.gemspec
RUN logstash-plugin install /usr/share/logstash/plugins/logstash-input-jira/logstash-input-jira-*.gem

WORKDIR /usr/share/logstash
