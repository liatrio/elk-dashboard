# elk-dashboard
### Pipeline Dashboard using ElasticSearch LogStash and Kibana

Creates docker containers to run ElasticSearch, Kibana and LogStash

Edit logstash/pipeline/bitbucket-projects.conf and replace "TOKEN" with your BitBucket Personal access tokens
```
docker-compose up -d
```

When the LogStash container starts up it runs the sample BitBucket pipeline which imports projects.

View LogStash log output

```
docker-compose logs logstash
```

Re-run LogStash pipeline

```
docker-compose restart logstash
```

Kibana `http://localhost:5601/`