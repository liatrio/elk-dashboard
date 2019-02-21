#!/usr/bin/env node

const request = require('request');
const fs = require('fs');

const argv = require('minimist')(process.argv.slice(2), {default: {scheme: 'http', host: 'localhost', port: '3000', path: 'grafana'}});

// console.log(argv);
const host = argv['scheme'] + '://' + argv['host'] + ':' + argv['port'];

let options = {};
if (argv.user && argv.pass) {
  options.auth = {
    user: argv.user,
    pass: argv.pass
  }
}
if (argv.token) {
  options.auth = {
    bearer: argv.token
  }
}

const templatesPath = argv.path + '/templates/';
if (fs.existsSync(templatesPath)) {
  fs.readdir(templatesPath, (error, files) => {
    if (error) {
      return console.error(error);
    }

    console.log(files);
    files.forEach((filename) => {
      fs.readFile(templatesPath + filename, (error, data) => {
        let dashboard = JSON.parse(data).dashboard;
        console.log(dashboard);
        request.post({url: host + '/api/dashboards/db', body: {dashboard: dashboard}, json: true, auth: options.auth, headers: {name: 'content-type',
          value: 'application/json'}}, (error, response, body) => {
          if (error) {
            return console.error(error);
          }
          if (response.statusCode != 200) {
            return console.error(response.statusCode, response.statusMessage || body.message);
          }

          console.log(body);
        });
      });
    });

  });
}
