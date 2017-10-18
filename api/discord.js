const express = require('express');

const router = express.Router();

const CLIENT_ID = process.env.CLIENT_ID;
const CLIENT_SECRET = process.env.CLIENT_SECRET;
const redirect = encodeURIComponent('http://50.53.229.66:7911/api/discord/callback');

router.get('/login', (req, res) => {
  res.redirect(`https://discordapp.com/oauth2/authorize?client_id=${CLIENT_ID}&scope=identify&response_type=code&redirect_uri=${redirect}`);
});

module.exports = router;