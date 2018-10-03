FROM docker.elastic.co/logstash/logstash:6.4.0

RUN logstash-plugin install logstash-filter-prune

USER root
RUN yum install -y rubygems vim

USER logstash
