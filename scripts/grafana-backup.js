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

if (!fs.existsSync(argv.path)) {
  fs.mkdirSync(argv.path);
}
const templatePath = argv.path + '/templates/'
if (!fs.existsSync(templatePath)) {
  fs.mkdirSync(templatePath);
}

request(host + '/api/search?tag=default', options, (error, response, body) => {
  if (error) {
    console.log(error);
    return false;
  }

  if (response.statusCode != 200) {
    console.log(response.statusMessage || body.message);
    return false;
  }

  JSON.parse(body).forEach((searchResult) => {
    console.log('Found template: ' + searchResult.uid + ' - ' + searchResult.title);
    request(host + '/api/dashboards/uid/' + searchResult.uid, options, (error, response, template) => {
      if (error) {
        console.log(error);
        return false;
      }

      if (response.statusCode != 200) {
        console.log(response.statusMessage || body.message);
        return false;
      }

      let filename = templatePath + searchResult.uid + '.json';
      fs.writeFile(filename, template, (error) => {
        if (error) {
          console.error(error);
        }

        console.log('Saved template file ' + filename);
      });
    });
  });
});
