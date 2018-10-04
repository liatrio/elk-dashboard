FROM docker.elastic.co/logstash/logstash:6.4.0

RUN logstash-plugin install logstash-filter-prune

USER root
RUN yum install -y sudo git vim

USER logstash
ENV PATH=$PATH:/usr/share/logstash/vendor/jruby/bin/
RUN gem install bundler
