settings = require './config.json'

mongoose = require 'mongoose'
Deck = mongoose.model 'Deck',
  name: String
  card_usages: [{
    card_id: Number,
    side: Boolean,
    count: Number
  }],
  user: mongoose.Schema.ObjectId
  created_at: { type: Date, default: Date.now },
  used_count: Number,
  last_used_at: Date

module.exports = Deck