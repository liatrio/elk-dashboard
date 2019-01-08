FROM docker.elastic.co/logstash/logstash:6.5.4

EXPOSE 9000

ADD --chown=logstash config /usr/share/logstash/config
ADD --chown=logstash pipeline /usr/share/logstash/pipeline
