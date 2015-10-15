#标准库
net = require 'net'
http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'
execFile = require('child_process').execFile

#三方库
_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());

Inotify = require('inotify').Inotify
WebSocketServer = require('websocket').server
request = require 'request'

bunyan = require 'bunyan'

#配置文件
settings = require './config.json'

#组件
ygopro = require './ygopro.js'
mycard = require './mycard.js'
Room = require './room.js'
User = require './user.js' if settings.modules.database
Deck = require './deck.js' if settings.modules.database

victories = require './victories.json'



#debug模式 端口号+1
debug = false
log = null
if process.argv[2] == '--debug'
  settings.port++
  settings.modules.http.port++ if settings.modules.http
  log = bunyan.createLogger name: "mycard-debug"
else
  log = bunyan.createLogger name: "mycard"

#网络连接
net.createServer (client) ->
  server = new net.Socket()
  client.server = server

  #释放处理
  client.on 'close', (had_error) ->
    log.info "client closed", client.name, had_error
    client.room.disconnector = client if client.room and client.room.started and client in client.room.dueling_players and !client.room.disconnector
    unless client.closed
      client.closed = true
      client.room.disconnect(client) if client.room
    server.end()
    return

  client.on 'error', (error)->
    log.info "client error", client.name, error
    client.room.disconnector = client if client.room and client.room.started and client in client.room.dueling_players and !client.room.disconnector
    unless client.closed
      client.closed = error
      client.room.disconnect(client, error) if client.room
    server.end()
    return

  server.on 'close', (had_error) ->
    log.info "server closed", client.name, had_error
    server.closed = true unless server.closed
    client.room.disconnector = 'server' if client.room and client.room.started and client in client.room.dueling_players and !client.room.disconnector
    unless client.closed
      ygopro.stoc_send_chat(client, "服务器关闭了连接")
      client.end()
    return

  server.on 'error', (error)->
    log.info "server error", client.name, error
    server.closed = error
    client.room.disconnector = 'server' if client.room and client.room.started and client in client.room.dueling_players and !client.room.disconnector
    unless client.closed
      ygopro.stoc_send_chat(client, "服务器错误: #{error}")
      client.end()
    return

  #需要重构
  #客户端到服务端(ctos)协议分析
  ctos_buffer = new Buffer(0)
  ctos_message_length = 0
  ctos_proto = 0

  client.pre_establish_buffers = new Array()

  client.on 'data', (data) ->
    if client.is_post_watcher
      client.room.watcher.write data
    else
      ctos_buffer = Buffer.concat([ctos_buffer, data], ctos_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

      if client.established
        server.write data
      else
        client.pre_establish_buffers.push data

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
            #console.log "CTOS", ygopro.constants.CTOS[ctos_proto]
            if ygopro.ctos_follows[ctos_proto]
              b = ctos_buffer.slice(3, ctos_message_length-1+3)
              if struct = ygopro.structs[ygopro.proto_structs.CTOS[ygopro.constants.CTOS[ctos_proto]]]
                struct._setBuff(b)
                ygopro.ctos_follows[ctos_proto].callback b, _.clone(struct.fields), client, server
              else
                ygopro.ctos_follows[ctos_proto].callback b, null, client, server

            ctos_buffer = ctos_buffer.slice(2 + ctos_message_length)
            ctos_message_length = 0
            ctos_proto = 0
          else
            break
    return

  #服务端到客户端(stoc)
  stoc_buffer = new Buffer(0)
  stoc_message_length = 0
  stoc_proto = 0

  server.on 'data', (data)->
    stoc_buffer = Buffer.concat([stoc_buffer, data], stoc_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

    #unless ygopro.stoc_follows[stoc_proto] and ygopro.stoc_follows[stoc_proto].synchronous
    client.write data

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
          #console.log "STOC", ygopro.constants.STOC[stoc_proto]
          stanzas = stoc_proto
          if ygopro.stoc_follows[stoc_proto]
            b = stoc_buffer.slice(3, stoc_message_length - 1 + 3)
            if struct = ygopro.structs[ygopro.proto_structs.STOC[ygopro.constants.STOC[stoc_proto]]]
              struct._setBuff(b)
              ygopro.stoc_follows[stoc_proto].callback b, _.clone(struct.fields), client, server
            else
              ygopro.stoc_follows[stoc_proto].callback b, null, client, server

          stoc_buffer = stoc_buffer.slice(2 + stoc_message_length)
          stoc_message_length = 0
          stoc_proto = 0
        else
          break
    return
  return

.listen settings.port, ->
  log.info "server started", settings.ip, settings.port
  return

#功能模块

ygopro.ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server)->
  client.name = info.name #在创建room之前暂存
  return

ygopro.ctos_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  #log.info info
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
  else if !Room.validate(info.pass)
    #ygopro.stoc_send client, 'ERROR_MSG',{
    #  msg: 1
    #  code: 1 #这返错有问题，直接双ygopro直连怎么都正常，在这里就经常弹不出提示
    #}
    ygopro.stoc_send_chat(client,"房间密码不正确")
    ygopro.stoc_send client, 'ERROR_MSG',{
      msg: 1
      code: 2
    }
    client.end()

  else if client.name == '[INCORRECT]' #模拟用户验证
    ygopro.stoc_send client, 'ERROR_MSG',{
      msg: 1
      code: 2
    }
    client.end()
  else
    log.info 'join_game',info.pass, client.name
    client.room = Room.find_or_create_by_name(info.pass)
    if client.room.started
      if settings.modules.post_start_watching
        client.is_post_watcher = true
        ygopro.stoc_send_chat_to_room client.room, "#{client.name} 加入了观战"
        client.room.watchers.push client
        for buffer in client.room.watcher_buffers
          client.write buffer
        ygopro.stoc_send_chat client, "观战中."
      else
        ygopro.stoc_send_chat(client,"决斗已开始")
        ygopro.stoc_send client, 'ERROR_MSG',{
          msg: 1
          code: 2
        }
        client.end()
    else
      client.room.connect(client)
  return

ygopro.stoc_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  #欢迎信息
  if settings.modules.welcome
    ygopro.stoc_send_chat client, settings.modules.welcome
  if settings.modules.database
    if _.startsWith(client.room.name, 'M#')
      User.findOne { name: client.name }, (err, user)->
        if !user
          user = new User({name: client.name, points: 0})
          user.save()
        User.count {points:{$gt:user.points}}, (err, count)->
          rank = count + 1
          ygopro.stoc_send_chat(client, "积分系统测试中，你现在有#{user.points}点积分，排名#{rank}，这些积分以后正式使用时会重置")
          return
        return

  if settings.modules.post_start_watching and !client.room.watcher
    client.room.watcher = watcher = net.connect client.room.port, ->
      ygopro.ctos_send watcher, 'PLAYER_INFO', {
        name: "the Big Brother"
      }
      ygopro.ctos_send watcher, 'JOIN_GAME', {
        version: settings.version,
        gameid: 2577,
        some_unknown_mysterious_fucking_thing: 0
        pass: ""
      }
      ygopro.ctos_send watcher, 'HS_TOOBSERVER'
      return

    watcher.ws_buffer = new Buffer(0)
    watcher.ws_message_length = 0
    client.room.watcher_stanzas = []

    watcher.on 'data', (data)->
      client.room.watcher_buffers.push data
      for w in client.room.watchers
        w.write data if w #a WTF fix

      watcher.ws_buffer = Buffer.concat([watcher.ws_buffer, data], watcher.ws_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

      while true
        if watcher.ws_message_length == 0
          if watcher.ws_buffer.length >= 2
            watcher.ws_message_length = watcher.ws_buffer.readUInt16LE(0)
          else
            break
        else
          if watcher.ws_buffer.length >= 2 + watcher.ws_message_length
            stanza = watcher.ws_buffer.slice(2, watcher.ws_message_length + 2)
            for w in client.room.ws_watchers
              w.sendBytes stanza if w #a WTF fix
            client.room.watcher_stanzas.push stanza

            watcher.ws_buffer = watcher.ws_buffer.slice(2 + watcher.ws_message_length)
            watcher.ws_message_length = 0
          else
            break
      return

    watcher.on 'error', (error)->
      log.error "watcher error", error
      return

    watcher.on 'close', (had_error)->
      for w in client.room.ws_watchers
        w.close()
      return
  return
#登场台词
if settings.modules.dialogues
  dialogues = {}
  request
    url: settings.modules.dialogues
    json: true
    , (error, response, body)->
      if _.isString body
        log.warn "dialogues bad json", body
      else if error or !body
        log.warn 'dialogues error', error, response
      else
        log.info "dialogues loaded", _.size body
        dialogues = body
      return

ygopro.stoc_follow 'GAME_MSG', false, (buffer, info, client, server)->
  msg = buffer.readInt8(0)
  #log.info 'MSG', ygopro.constants.MSG[msg]
  if ygopro.constants.MSG[msg] == 'START'
    playertype = buffer.readUInt8(1)
    client.is_first = !(playertype & 0xf);
    client.lp = client.room.hostinfo.start_lp

    #ygopro.stoc_send_chat_to_room(client.room, "LP跟踪调试信息: #{client.name} 初始LP #{client.lp}")
  if ygopro.constants.MSG[msg] == 'WIN' and _.startsWith(client.room.name, 'M#') and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first or pos == 2
    reason = buffer.readUInt8(2)
    log.info {winner: pos, reason: reason}
    client.room.duels.push {winner: pos, reason: reason}
  #lp跟踪
  if ygopro.constants.MSG[msg] == 'DAMAGE' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    client.room.dueling_players[pos].lp -= val

    #ygopro.stoc_send_chat_to_room(client.room, "LP跟踪调试信息: #{client.room.dueling_players[pos].name} 受到伤害 #{val}，现在的LP为 #{client.room.dueling_players[pos].lp}")
    if 0 < client.room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(client.room, "你的生命已经如风中残烛了！")

  if ygopro.constants.MSG[msg] == 'RECOVER' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    client.room.dueling_players[pos].lp += val

    #ygopro.stoc_send_chat_to_room(client.room, "LP跟踪调试信息: #{client.room.dueling_players[pos].name} 回复 #{val}，现在的LP为 #{client.room.dueling_players[pos].lp}")

  if ygopro.constants.MSG[msg] == 'LPUPDATE' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    client.room.dueling_players[pos].lp = val

    #ygopro.stoc_send_chat_to_room(client.room, "LP跟踪调试信息: #{client.room.dueling_players[pos].name} 的LP变成 #{client.room.dueling_players[pos].lp}")

  if ygopro.constants.MSG[msg] == 'PAY_LPCOST' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    client.room.dueling_players[pos].lp -= val

    #ygopro.stoc_send_chat_to_room(client.room, "LP跟踪调试信息: #{client.room.dueling_players[pos].name} 支付 #{val}，现在的LP为 #{client.room.dueling_players[pos].lp}")

    if 0 < client.room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(client.room, "背水一战！")



  #登场台词
  if settings.modules.dialogues
    if ygopro.constants.MSG[msg] == 'SUMMONING' or ygopro.constants.MSG[msg] == 'SPSUMMONING'
      card = buffer.readUInt32LE(1)
      if dialogues[card]
        for line in _.lines dialogues[card][Math.floor(Math.random() * dialogues[card].length)]
          ygopro.stoc_send_chat client, line
  return






###
#房间管理
ygopro.stoc_follow 'HS_PLAYER_ENTER', false, (buffer, info, client, server)->
  #console.log "PLAYER_ENTER to #{client.name}: #{info.name}, #{info.pos}"
  #room = client.room
  #if !room
  #  console.log "[WARN]player_enter: can't find room by player #{client.player}"
  #  return
  #room.pos_name[info.pos] = info.name

ygopro.stoc_follow 'HS_PLAYER_CHANGE', false, (buffer, info, client, server)->
  #client.ready = info.status & 0xF != 0
  #client.pos = info.status >> 4
  #console.log "PLAYER_CHANGE to #{client.name}: #{info.status & 0xF != 0}, #{info.status >> 4}"
###

ygopro.stoc_follow 'TYPE_CHANGE', false, (buffer, info, client, server)->
  selftype = info.type & 0xf;
  is_host = ((info.type >> 4) & 0xf) != 0;
  client.is_host = is_host
  client.pos = selftype
  #console.log "TYPE_CHANGE to #{client.name}:", info, selftype, is_host
  return

#tip
ygopro.stoc_send_random_tip = (client)->
  ygopro.stoc_send_chat client, "Tip: " + tips[Math.floor(Math.random() * tips.length)] if tips
  return

tips = null
if settings.modules.tips
  request
    url: settings.modules.tips
    json: true
    , (error, response, body)->
      tips = body
      log.info "tips loaded", tips.length
      return

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server)->
  unless client.room.started #first start
    client.room.started = true
    client.room.duels = []
    client.room.dueling_players = []
    for player in client.room.players when player.pos != 7
      client.room.dueling_players[player.pos] = player
      if !player.main
        log.error 'WTF', client
      else
        player.deck = mycard.load_card_usages_from_cards(player.main, player.side)

    if !client.room.dueling_players[0] or !client.room.dueling_players[1]
      log.error 'incomplete room', client.room.dueling_players, client.room.players

  if settings.modules.tips
    ygopro.stoc_send_random_tip(client)
  return

ygopro.ctos_follow 'CHAT', false, (buffer, info, client, server)->
  switch _.trim(info.msg)
    when '/ping'
      execFile 'ss', ['-it', "dst #{client.remoteAddress}:#{client.remotePort}"], (error, stdout, stderr)->
        if error
          ygopro.stoc_send_chat_to_room client.room, error
        else
          line = _.lines(stdout)[2]
          if line.indexOf('rtt') != -1
            ygopro.stoc_send_chat_to_room client.room, line
          else
            log.warn 'ping', stdout
            ygopro.stoc_send_chat_to_room client.room, stdout
        return
    when '/ranktop'
      if settings.modules.database
        User.find null, null, { sort: { points : -1 }, limit: 8 }, (err, users)->
          if err
            return log.error 'ranktop', err
          for index, user of users
            ygopro.stoc_send_chat client, [parseInt(index)+1, user.points, user.name].join(' ')
          return

    when '/help'
      ygopro.stoc_send_chat(client,"Mycard MatchServer 指令帮助")
      ygopro.stoc_send_chat(client,"/help 显示这个帮助信息")
      ygopro.stoc_send_chat(client,"/tip 显示一条提示") if settings.modules.tips
      ygopro.stoc_send_chat(client,"/senddeck 发送自己的卡组")
    when '/tip'
      ygopro.stoc_send_random_tip(client) if settings.modules.tips
#发送卡组
    when '/senddeck'
      if client.deck?
        ygopro.stoc_send_chat(client, "正在读取卡组信息... ")
        mycard.deck_url_short client.name, client.deck, (url)->
          ygopro.stoc_send_chat_to_room(client.room, "卡组链接: " + url)
      else
        ygopro.stoc_send_chat_to_room(client.room, "读取卡组信息失败")
    when '/admin showroom'
      log.info client.room
  return
ygopro.ctos_follow 'UPDATE_DECK', false, (buffer, info, client, server)->
  log.info info
  main = (info.deckbuf[i] for i in [0...info.mainc])
  side = (info.deckbuf[i] for i in [info.mainc...info.mainc+info.sidec])
  client.main = main
  client.side = side
  return

if settings.modules.skip_empty_side
  ygopro.stoc_follow 'CHANGE_SIDE', false, (buffer, info, client, server)->
    if not _.any(client.deck, (card_usage)->card_usage.side)
      ygopro.ctos_send server, 'UPDATE_DECK', {
        mainc: client.main.length,
        sidec: 0,
        deckbuf: client.main
      }
      ygopro.stoc_send_chat client, '等待更换副卡组中...'
    return

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

#http
if settings.modules.http
  level_points = require './level_points.json'
  waiting = [[]]
  for i of level_points
    waiting.push []

  log.info 'level_points loaded', level_points
  http_server = http.createServer (request, response)->
    #http://122.0.65.70:7922/?operation=getroomjson
      u = url.parse(request.url)
      #log.info u
      if u.pathname == '/count.json'
        response.writeHead(200);
        response.end(Room.all.length.toString())
      else if u.pathname == '/match'
        if request.headers['authorization']
          [name, password] = new Buffer(request.headers['authorization'].split(/\s+/).pop() ? '','base64').toString().split(':')
          User.findOne { name: name }, (err, user)->
            if !user
              user = new User({name: name, points: 0, elo: 1400})
              user.save()
            level = level_points.length
            for index, points of level_points
              if user.points < points
                level = index
                break
            response.allowance = 0
            waiting[level].push response
            request.on 'close', ()->
              index = waiting[level].indexOf(response)
              waiting[level].splice(index, 1) unless index == -1
              return
            return
        else
          #log.info 'unauth match'
          #response.writeHead(401);
          #response.end("请更新mycard到1.2.8版本");
          level = 1
          response.allowance = 0
          waiting[level].push response
          request.on 'close', ()->
            index = waiting[level].indexOf(response)
            waiting[level].splice(index, 1) unless index == -1
            return

      else if u.pathname == '/rooms.json'
        response.writeHead(404);
        response.end();
      else if u.query == 'operation=getroomjson'
        response.writeHead(200);
        response.end JSON.stringify rooms: (for room in Room.all when room.established
          roomid: room.port.toString(),
          roomname: room.name.split('$',2)[0],
          needpass: (room.name.indexOf('$') != -1).toString(),
          users: (for player in room.players when player.pos?
            id: (-1).toString(),
            name: player.name,
            pos: player.pos
          ),
          istart: if room.started then "start" else "wait"
        )
      else
        response.writeHead(404);
        response.end();
      return
  http_server.listen settings.modules.http.port

  setInterval ()->
    for level in [level_points.length..0]
      for index, player of waiting[level]
        opponent_level = null
        opponent = _.find waiting[level], (opponent)->
          log.info opponent,player
          opponent isnt player
        log.info '--------1--------', waiting, opponent

        if opponent
          opponent_level = level
        else if player.allowance > 0
          for displacement in [1..player.allowance]
            if level+displacement <= level_points.length
              opponent = waiting[level+displacement][0]
              if opponent
                opponent_level = level+displacement
                break
            if level-displacement >= 0
              opponent = waiting[level-displacement][0]
              if opponent
                opponent_level = level-displacement
                break

        if opponent
          if waiting[level].indexOf(player) == -1 or waiting[opponent_level].indexOf(opponent) == -1
            log.info waiting, player, level, opponent, opponent_level
            throw 'WTF'
          waiting[level].splice(waiting[level].indexOf(player), 1)
          waiting[opponent_level].splice(waiting[opponent_level].indexOf(opponent), 1)
          index--

          room = "mycard://#{settings.ip}:#{settings.port}/M##{_.uniqueId()}$#{_.random(999)}"
          log.info 'matched', room
          headers = {"Access-Control-Allow-Origin":"*","Content-Type": "text/plain"}
          player.writeHead(200, headers)
          player.end room
          opponent.writeHead(200, headers)
          opponent.end room

        else
          player.allowance++
    return
  , 2000

  originIsAllowed = (origin) ->
    # allow all origin, for debug
    true
  wsServer = new WebSocketServer(
    httpServer: http_server
    autoAcceptConnections: false
  )
  wsServer.on "request", (request) ->
    unless originIsAllowed(request.origin)
      # Make sure we only accept requests from an allowed origin
      request.reject()
      console.log (new Date()) + " Connection from origin " + request.origin + " rejected."
      return

    room_name = decodeURIComponent(request.resource.slice(1))
    if room_name == 'started'
      room = _.find Room.all, (room)->
        room.started
    else
      room = Room.find_by_name room_name
    unless room
      request.reject()
      console.log (new Date()) + " Connection from origin " + request.origin + " rejected. #{room_name}"
      return

    connection = request.accept(null, request.origin)
    console.log (new Date()) + " Connection accepted. #{room.name}"
    room.ws_watchers.push connection

    for stanza in room.watcher_stanzas
      connection.sendBytes stanza

    ###
    connection.on "message", (message) ->
      if message.type is "utf8"
        console.log "Received Message: " + message.utf8Data
        connection.sendUTF message.utf8Data
      else if message.type is "binary"
        console.log "Received Binary Message of " + message.binaryData.length + " bytes"
        connection.sendBytes message.binaryData
    ###
    connection.on "close", (reasonCode, description) ->
      index = _.indexOf(room.ws_watchers, connection)
      room.ws_watchers.splice(index, 1) unless index == -1
      console.log (new Date()) + " Peer " + connection.remoteAddress + " disconnected."
      return
    return

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
      log.error "event without filename"
    return
###
setInterval ()->
  for room in Room.all
    if room.alive
      room.alive = false
    else
      log.info "kill room", room.port

      for player in room.players
        ygopro.stoc_send_chat(player, "由于长时间没有活动被关闭") unless player.closed
      room.process.kill()
, 900000
###