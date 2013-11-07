request = require 'request'
@key = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_="
@load_card_usages_from_cards = (main, side)->
  result = []
  last_id = null
  for card_id in main
    if card_id == last_id
      count++
    else
      result.push {card_id: last_id, side: false, count: count} if last_id
      last_id = card_id
      count = 1
  result.push {card_id: last_id, side: false, count: count} if last_id
  last_id = null
  for card_id in side
    if card_id == last_id
      count++
    else
      result.push {card_id: last_id, side: true, count: count} if last_id
      last_id = card_id
      count = 1
  result.push {card_id: last_id, side: true, count: count} if last_id
  result

@encode = (card_usages)->
  result = ''
  for card_usage in card_usages
    c = card_usage.side << 29 | card_usage.count << 27 | card_usage.card_id
    for i in [4..0]
      result += @key.charAt((c >> i * 6) & 0x3F)
  result

@deck_url = (name, card_usages, format)->
  "https://my-card.in/decks/new#{if format then '.' + format else ''}?name=#{encodeURIComponent name}&cards=#{@encode card_usages}"

@deck_url_short = (name, card_usages, callback)->
  request = require 'request'
  request @deck_url(name, card_usages, 'short.url'), (error, response, body)->
    callback body