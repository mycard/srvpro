#标准库
net = require 'net'
http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'

#三方库
_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());

Inotify = require('inotify').Inotify
request = require 'request'

#组件
ygopro = require './ygopro.js'
Room = require './room.js'

#配置文件
settings = require './config.json'            #本机IP端口设置

#debug模式 端口号+1
debug = false
if process.argv[2] == '--debug'
  settings.port++
  settings.http_port++

#网络连接
net.createServer (client) ->
  server = new net.Socket()
  client.server = server

  #释放处理
  client.on 'close', (had_error) ->
    console.log "client closed #{had_error}"
    unless client.closed
      client.room.disconnect(client) if client.room
      client.closed = true
    server.end()

  client.on 'error', (error)->
    console.log "client error #{error}"
    unless client.closed
      client.room.disconnect(client, error) if client.room
      client.closed = error
    server.end()

  server.on 'close', (had_error) ->
    console.log "server closed #{had_error}"
    server.closed = true unless server.closed
    unless client.closed
      ygopro.stoc_send_chat(client, "服务器关闭了连接")
      client.closed = true
      client.end()

  server.on 'error', (error)->
    console.log "server error #{error}"
    server.closed = error
    unless client.closed
      ygopro.stoc_send_chat(client, "服务器错误: #{error}")
      client.closed = true
      client.end()

  #需要重构
  #客户端到服务端(ctos)协议分析
  ctos_buffer = new Buffer(0)
  ctos_message_length = 0
  ctos_proto = 0

  client.pre_establish_buffers = new Array()

  client.on 'data', (data) ->
    ctos_buffer = Buffer.concat([ctos_buffer, data], ctos_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学
    #console.log data
    while true
      if ctos_message_length == 0
        if ctos_buffer.length >= 2
          ctos_message_length = ctos_buffer.readUInt16LE(0)
        else
          break
      else if ctos_proto == 0
        if ctos_buffer.length >= 3
          ctos_proto = ctos_buffer.readUInt8(2)
        else
          break
      else
        if ctos_buffer.length >= 2 + ctos_message_length
          if ygopro.ctos_follows[ctos_proto]
            b = ctos_buffer.slice(3, ctos_message_length-1+3)
            if struct = ygopro.structs[ygopro.proto_structs.CTOS[ygopro.constants.CTOS[ctos_proto]]]
              struct._setBuff(b)
              setTimeout ygopro.ctos_follows[ctos_proto].callback, 0, b, _.clone(struct.fields), client, server
            else
              setTimeout ygopro.ctos_follows[ctos_proto].callback, 0, b, null, client, server

          ctos_buffer = ctos_buffer.slice(2 + ctos_message_length)
          ctos_message_length = 0
          ctos_proto = 0
        else
          break

    unless ygopro.ctos_follows[ctos_proto] and ygopro.ctos_follows[ctos_proto].synchronous
      if client.established
        server.write data
      else
        client.pre_establish_buffers.push data

  #服务端到客户端(stoc)
  stoc_buffer = new Buffer(0)
  stoc_message_length = 0
  stoc_proto = 0

  server.on 'data', (data)->
    stoc_buffer = Buffer.concat([stoc_buffer, data], stoc_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

    while true
      if stoc_message_length == 0
        if stoc_buffer.length >= 2
          stoc_message_length = stoc_buffer.readUInt16LE(0)
        else
          break
      else if stoc_proto == 0
        if stoc_buffer.length >= 3
          stoc_proto = stoc_buffer.readUInt8(2)
        else
          break
      else
        if stoc_buffer.length >= 2 + stoc_message_length
          if ygopro.stoc_follows[stoc_proto]
            b = stoc_buffer.slice(3, stoc_message_length - 1 + 3)
            if struct = ygopro.structs[ygopro.proto_structs.STOC[ygopro.constants.STOC[stoc_proto]]]
              struct._setBuff(b)
              setImmediate ygopro.stoc_follows[stoc_proto].callback, b, _.clone(struct.fields), client, server
            else
              setImmediate ygopro.stoc_follows[stoc_proto].callback, b, null, client, server

          stoc_buffer = stoc_buffer.slice(2 + stoc_message_length)
          stoc_message_length = 0
          stoc_proto = 0
        else
          break

    #unless ygopro.stoc_follows[stoc_proto] and ygopro.stoc_follows[stoc_proto].synchronous
    client.write data

.listen settings.port, ->
  console.log "server started on #{settings.ip}:#{settings.port}"

#功能模块

ygopro.ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server)->
  client.name = info.name #在创建room之前暂存

ygopro.ctos_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  if info.version != settings.version
    ygopro.stoc_send client, 'ERROR_MSG',{
      msg: 4
      code: settings.version
    }
    client.end()
  else if !info.pass.length
    ygopro.stoc_send_chat(client,"房间为空，请修改房间名")
    ygopro.stoc_send client, 'ERROR_MSG',{
      msg: 1
      code: 2
    }
    client.end()
  else if info.pass == '[INCORRECT]' #模拟房间密码验证
    ygopro.stoc_send client, 'ERROR_MSG',{
      msg: 1
      code: 1 #这返错有问题，直接双ygopro直连怎么都正常，在服务器上就经常弹不出提示
    }
    client.end()
  else if client.name == '[INCORRECT]' #模拟用户验证
    ygopro.stoc_send client, 'ERROR_MSG',{
      msg: 1
      code: 2
    }
    client.end()
  else
    client.room = Room.find_or_create_by_name(info.pass)
    client.room.connect(client)

######################################################################################################################

#欢迎信息
ygopro.stoc_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  ygopro.stoc_send client, 'CHAT', {
    player: 8
    msg: "Mycard Debugging Server"
  }
  ygopro.stoc_send client, 'CHAT', {
    player: 8
    msg: "这里是测试中的新服务器, 还不稳定, 随时可能崩溃, 遇到意外请淡定\n                           ˉˉˉˉˉ"
  }

#登场台词
dialogues = {}
request
  url: 'https://my-card.in/dialogues.json'
  json: true
  , (error, response, body)->
    if _.isString body
      console.log "[WARN]dialogues bad json #{body}"
    else
      console.log "loaded #{_.size body} dialogues"
      dialogues = body

ygopro.stoc_follow 'GAME_MSG', false, (buffer, info, client, server)->
  msg = buffer.readInt8(0)
  if ygopro.constants.MSG[msg] == 'SUMMONING' or ygopro.constants.MSG[msg] == 'SPSUMMONING'
    card = buffer.readUInt32LE(1)
    if dialogues[card]
      for line in _.lines dialogues[card][Math.floor(Math.random() * dialogues[card].length)]
        ygopro.stoc_send_chat client, line

#积分
###
  if ygopro.constants.MSG[msg] == 'WIN'
    room = Room.find_by_client(client)
    if !room
      console.log "[WARN]win: can't find room by player #{client.player}"
      return
    if _.startsWith(room.name, 'M#') and room.dueling
      room.dueling = false

      loser_name = room.pos_name[buffer.readUInt8(1)]
      winner_name = room.pos_name[1 - buffer.readUInt8(1)]
      #type = buffer.readUInt8(2)
      User.findOne { name: winner_name }, (err, winner)->
        if(err)
          console.log "#{err} when finding user #{winner_name}"
        else if(!winner)
          console.log "user #{winner_name} not exist"
        else
          User.findOne { name: loser_name }, (err, loser)->
            if(err)
              console.log "#{err} when finding user #{loser_name}"
            else if(!loser)
              console.log "user #{loser_name} not exist"
            else
              winner.points += 10
              loser.points -= 5
              winner.save()
              loser.save()
              console.log "#{winner} 增加10点积分，现在有#{winner.points}点"
              console.log "#{loser} 减少5点积分，现在有#{loser.points}点"


#mongoose = require 'mongoose'
#mongoose.connect('mongodb://localhost/mycard');
#User = mongoose.model 'User',
#  name: String
#  points: Number

#ygopro.stoc_follow 'HS_PLAYER_CHANGE', false, (buffer, info, client, server)->
#  console.log 'HS_PLAYER_CHANGE', info
###


#房间管理
ygopro.stoc_follow 'HS_PLAYER_ENTER', false, (buffer, info, client, server)->
  console.log "PLAYER_ENTER to #{client.name}: #{info.name}, #{info.pos}"
  #room = client.room
  #if !room
  #  console.log "[WARN]player_enter: can't find room by player #{client.player}"
  #  return
  #room.pos_name[info.pos] = info.name

ygopro.stoc_follow 'HS_PLAYER_CHANGE', false, (buffer, info, client, server)->
  #client.ready = info.status & 0xF != 0
  #client.pos = info.status >> 4
  console.log "PLAYER_CHANGE to #{client.name}: #{info.status & 0xF != 0}, #{info.status >> 4}"

ygopro.stoc_follow 'TYPE_CHANGE', false, (buffer, info, client, server)->
  selftype = info.type & 0xf;
  is_host = ((info.type >> 4) & 0xf) != 0;
  client.is_host = is_host
  client.pos = selftype
  console.log "TYPE_CHANGE to #{client.name}:", info, selftype, is_host

#房间数量
http.createServer (request, response)->
#http://122.0.65.70:7922/?operation=getroomjson
  url = url.parse(request.url)
  if url.pathname == '/count.json'
    response.writeHead(200);
    response.end(Room.all.length.toString())
  else if url.pathname == '/rooms.json'
    response.writeHead(404);
    response.end();
  if url.query == 'operation=getroomjson'
    response.writeHead(200);
    response.end JSON.stringify rooms: (for room in Room.all
      roomid: room.port.toString(),
      roomname: room.name,
      needpass: false.toString(),
      users: (for player in room.players
        id: (-1).toString(),
        name: player.name,
        pos: player.pos
      ),
      istart: "wait"
    )
  else
    response.writeHead(404);
    response.end();
.listen settings.http_port

#清理90s没活动的房间
inotify = new Inotify()
inotify.addWatch
  path: 'ygocore/replay',
  watch_for: Inotify.IN_CLOSE_WRITE | Inotify.IN_CREATE | Inotify.IN_MODIFY,
  callback: (event)->
    mask = event.mask
    if event.name
      port = parseInt path.basename(event.name, '.yrp')
      room = Room.find_by_port port
      if room
        if mask & Inotify.IN_CREATE
        else if mask & Inotify.IN_CLOSE_WRITE
          fs.unlink path.join('ygocore/replay'), (err)->
        else if mask & Inotify.IN_MODIFY
          room.alive = true
    else
      console.log '[warn] event without filename'

setInterval ()->
  for room in Room.all
    if room.alive
      room.alive = false
    else
      console.log "kill room #{room.port}"
      for player in room.players
        ygopro.stoc_send_chat(player, "由于长时间没有活动被关闭") unless player.closed
      room.process.kill()
, 900000

#tip
ygopro.stoc_send_tip = (client, tip)->
  lines = _.lines(tip)
  ygopro.stoc_send_chat(client, "Tip: #{lines[0]}")
  for line in lines.slice(1)
    ygopro.stoc_send_chat(client, line)

ygopro.stoc_send_random_tip = (client)->
  ygopro.stoc_send_tip client, tips[Math.floor(Math.random() * tips.length)] if tips

tips = null
request
  url: 'https://my-card.in/tips.json'
  json: true
  , (error, response, body)->
    tips = body
    console.log "loaded #{tips.length} tips"

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server)->
  ygopro.stoc_send_random_tip(client)

  ###
  room = Room.find_by_client(client)
  if !room
    console.log "[WARN]duel start: can't find room by player #{client.player}"
    return

  room.dueling = true
  if _.startsWith(room.name, 'M#')
    User.findOne { name: client.player }, (err, user)->
      if !user
        user = new User({name: client.player, points: 0})
        user.save()
      ygopro.stoc_send_chat(client, "积分系统测试中，你现在有#{user.points}点积分，这些积分以后可能会重置")
  ###
ygopro.ctos_follow 'CHAT', false, (buffer, info, client, server)->
  if _.trim(info.msg) == '/tip'
    ygopro.stoc_send_random_tip(client)

###
# 开包大战

packs_weighted_cards = {}
for pack, cards of require './packs.json'
  packs_weighted_cards[pack] = []
  for card in cards
    for i in [0..card.count]
      packs_weighted_cards[pack].push card.card

console.log packs_weighted_cards

ygopro.ctos_follow 'UPDATE_DECK', false, (buffer, info, client, server)->
  ygopro.ctos_send server, 'HS_NOTREADY'

  deck = []
  for pack in client.player
    for i in [0...5]
      deck.push packs_weighted_cards[pack][Math.floor(Math.random()*packs_weighted_cards[pack].length)]


  ygopro.ctos_send server, 'UPDATE_DECK', {
    mainc: deck.length,
    sidec: 0,
    deckbuf: deck
  }
  ygopro.ctos_send server, 'HS_READY'

###

