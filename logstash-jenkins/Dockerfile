FROM docker.elastic.co/logstash/logstash:6.5.4

USER root

RUN yum install -y sudo git vim

USER logstash
ENV PATH=$PATH:/usr/share/logstash/vendor/jruby/bin/
RUN gem install bundler

ADD --chown=logstash config /usr/share/logstash/config
ADD --chown=logstash pipeline /usr/share/logstash/pipeline
RUN git clone https://github.com/liatrio/logstash-input-jenkins.git /usr/share/logstash/plugins/logstash-input-jenkins

WORKDIR /usr/share/logstash/plugins/logstash-input-jenkins
RUN bundler install 
RUN gem build /usr/share/logstash/plugins/logstash-input-jenkins/logstash-input-jenkins.gemspec

WORKDIR /usr/share/logstash
RUN logstash-plugin install /usr/share/logstash/plugins/logstash-input-jenkins/logstash-input-jenkins-*.gem
