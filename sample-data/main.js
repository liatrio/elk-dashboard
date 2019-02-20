const crypto = require('crypto');

const elasticsearch = require('elasticsearch');
const client = new elasticsearch.Client({
  host: 'localhost:9200',
  log: 'trace'
});

async function run() {
  let now = Date.now();

  await client.deleteByQuery({
    index: 'build',
    body: {
      query: {
        term: { 'sample-data': true }
      }
    }
  });

  let timestamp = Date.now(), env, r;
  for (let i = 0; i < 180; i++) {
    timestamp -= Math.floor(Math.random() * 86400000);
    r = Math.random();
    if (r < .6) {
      env = 'dev';
    } else if (r < .9) {
      env = 'qa';
    } else {
      env = 'prod';
    }
    await client.index({
      index: 'build',
      type: 'doc',
      body: {
        '@timestamp': timestamp,
        'sample-data': true,
        data: {
          buildVariables: {
            TYPE: 'deploy',
            ENV: env
          }
        }
      }
    });
    //console.log(response);
  }

  await client.deleteByQuery({
    index: 'lead_time',
    body: {
      query: {
        term: { 'sample-data': true }
      }
    }
  });

  timestamp = Date.now(), env, r;
  for (i = 0; i < 180; i++) {
    timestamp -= Math.floor(Math.random() * 259200000);

    let prod_completed_at = timestamp - Math.floor(Math.random() * 86400);
    let qa_completed_at = prod_completed_at - Math.floor(Math.random() * 432000); // 5 days
    let dev_completed_at = qa_completed_at - Math.floor(Math.random() * 604800); // 7 days
    let started_at = dev_completed_at - Math.floor(Math.random() * 604800); // 7 days
    let created_at = started_at - Math.floor(Math.random() * 604800); // 7 days

    let commit1 = crypto.createHash('sha1').update(Date.now() + Math.random().toString()).digest('hex');
    let commit2 = crypto.createHash('sha1').update(Date.now() + Math.random().toString()).digest('hex');
    let commit3 = crypto.createHash('sha1').update(Date.now() + Math.random().toString()).digest('hex');

    await client.index({
      index: 'lead_time',
      type: 'doc',
      body: {
        '@timestamp': timestamp,
        'sample-data': true,
        created_at: created_at,
        started_at: started_at,
        dev: {
          total_time: dev_completed_at - created_at,
          progress_time: dev_completed_at - started_at,
        },
        qa: {
          total_time: qa_completed_at - created_at,
          progress_time: qa_completed_at - started_at,
        },
        prod: {
          total_time: prod_completed_at - created_at,
          progress_time: prod_completed_at - started_at,
        },
        commits: [
          {id: commit1},
          {id: commit2},
          {id: commit3},
        ],
        deploys:
        [{
          environment: 'production',
          result: 'SUCCESS',
          completed_at: prod_completed_at,
          progress_time: prod_completed_at - started_at,
          total_time: prod_completed_at - created_at,
        },
        {
          environment: 'quality_assurance',
          result: 'SUCCESS',
          completed_at: qa_completed_at,
          progress_time: qa_completed_at - started_at,
          total_time: qa_completed_at - created_at,
        },
        {
          environment: 'development',
          result: 'SUCCESS',
          completed_at: dev_completed_at,
          progress_time: dev_completed_at - started_at,
          total_time: dev_completed_at - created_at
        }]
      }
    });
  }
}

run();
