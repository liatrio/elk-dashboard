# elk-dashboard
### Pipeline Dashboard using ElasticSearch LogStash and Kibana

Creates docker containers to run ElasticSearch, Kibana and LogStash

Edit elk-dashboard/logstash/pipeline/logstash.conf and replace <BIT_BUCKET_TOKEN> with your BitBucket Personal access tokens
```
# setup the containers
docker-compose up -d

# or to update the containers
docker-compose up -d --build
```

When the LogStash container starts up it runs the sample BitBucket pipeline which imports projects, repos and pull requests into separate indexes in ElasticSearch.

View LogStash log output
```
docker-compose logs logstash
```

Re-run LogStash pipeline
```
docker-compose restart logstash
```

Kibana `http://localhost:5601/`
You will need to create index patters in Kinana for the project, repo and pull_request indexes before you can view the documents in Discover
