const express = require('express')
const app = express()

app.engine('html', require('ejs').renderFile);
app.set('view engine', 'html');

app.get('/', function (req, res) {
  res.render('index', { title: 'ejs' });
})

app.listen(3000, function () {
  console.log('Example app listening on port 3000!')
})

