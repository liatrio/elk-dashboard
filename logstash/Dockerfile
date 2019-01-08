FROM docker.elastic.co/logstash/logstash:6.5.4

USER root

RUN logstash-plugin install logstash-filter-prune
RUN yum install -y sudo git vim

USER logstash
ENV PATH=$PATH:/usr/share/logstash/vendor/jruby/bin/
RUN gem install bundler

ADD --chown=logstash config /usr/share/logstash/config
ADD --chown=logstash pipeline /usr/share/logstash/pipeline
ADD --chown=logstash plugins /usr/share/logstash/plugins

WORKDIR /usr/share/logstash/plugins/logstash-input-bitbucket
RUN bundler install 
RUN gem build /usr/share/logstash/plugins/logstash-input-bitbucket/logstash-input-bitbucket.gemspec

WORKDIR /usr/share/logstash
RUN env
RUN logstash-plugin install /usr/share/logstash/plugins/logstash-input-bitbucket/logstash-input-bitbucket-*.gem
