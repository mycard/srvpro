settings = require './config.json'

mongoose = require 'mongoose'
User = mongoose.model 'User',
  name: String
  points: Number

module.exports = User