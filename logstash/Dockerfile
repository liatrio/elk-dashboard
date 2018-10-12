FROM docker.elastic.co/logstash/logstash:6.4.0

RUN logstash-plugin install logstash-filter-prune

USER root
RUN yum install -y sudo git vim

USER logstash
ENV PATH=$PATH:/usr/share/logstash/vendor/jruby/bin/
RUN gem install bundler

ADD config /usr/share/logstash/config
ADD pipeline /usr/share/logstash/pipeline
ADD plugins /usr/share/logstash/plugins

RUN bundler install --gemfile /usr/share/logstash/plugins/logstash-input-bitbucket/Gemfile
RUN gem build /usr/share/logstash/plugins/logstash-input-bitbucket/logstash-input-bitbucket.gemspec
RUN logstash-plugin install /usr/share/logstash/plugins/logstash-input-bitbucket/logstash-input-bitbucket-*.gem

