#标准库
net = require 'net'
http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'
os = require 'os'
crypto = require 'crypto'
execFile = require('child_process').execFile

#三方库
_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());

request = require 'request'

bunyan = require 'bunyan'

moment = require 'moment'

#redis = require 'redis'
#redisdb = redis.createClient host: "127.0.0.1", port: settings.modules.redis_port

#heapdump = require 'heapdump'

#配置文件
settings = require './config.json'
settings.BANNED_user = []
settings.BANNED_IP = []
settings.modules.hang_timeout = 90
settings.version = parseInt(fs.readFileSync('ygopro/gframe/game.cpp', 'utf8').match(/PRO_VERSION = ([x\d]+)/)[1], '16')
settings.lflist = (for list in fs.readFileSync('ygopro/lflist.conf', 'utf8').match(/!.*/g)
  {date: moment(list.match(/!([\d\.]+)/)[1], 'YYYY.MM.DD'), tcg: list.indexOf('TCG') != -1})

#组件
ygopro = require './ygopro.js'
Room = require './room.js'
roomlist = require './roomlist.js' if settings.modules.enable_websocket_roomlist

users_cache = {}

#debug模式 端口号+1
debug = false
log = null
if process.argv[2] == '--debug'
  settings.port++
  settings.modules.http.port++ if settings.modules.http
  log = bunyan.createLogger name: "mycard-debug"
else
  log = bunyan.createLogger name: "mycard"

#定时清理关闭的连接
Graveyard = []

tribute = (socket) ->
  setTimeout ((socket)-> Graveyard.push(socket);return)(socket), 3000
  return

setInterval ()->
  for fuck,i in Graveyard
    Graveyard[i].destroy() if Graveyard[i]
    for you,j in Graveyard[i]
      Graveyard[i][j] = null
    Graveyard[i] = null
  Graveyard = []
  return
, 3000

#网络连接
net.createServer (client) ->
  server = new net.Socket()
  client.server = server

  client.setTimeout(300000) #5分钟

  #释放处理
  client.on 'close', (had_error) ->
#log.info "client closed", client.name, had_error
    tribute(client)
    unless client.closed
      client.closed = true
      client.room.disconnect(client) if client.room
    server.end()
    return

  client.on 'error', (error)->
#log.info "client error", client.name, error
    tribute(client)
    unless client.closed
      client.closed = error
      client.room.disconnect(client, error) if client.room
    server.end()
    return

  client.on 'timeout', ()->
    server.end()
    return

  server.on 'close', (had_error) ->
#log.info "server closed", client.name, had_error
    tribute(server)
    client.room.disconnector = 'server'
    server.closed = true unless server.closed
    unless client.closed
      ygopro.stoc_send_chat(client, "服务器关闭了连接", 11)
      client.end()
    return

  server.on 'error', (error)->
#log.info "server error", client.name, error
    tribute(server)
    client.room.disconnector = 'server'
    server.closed = error
    unless client.closed
      ygopro.stoc_send_chat(client, "服务器错误: #{error}", 11)
      client.end()
    return
  ###
  client.open_cloud_replay= (err, replay)->
    if err or !replay
      ygopro.stoc_send_chat(client,"没有找到录像", 11)
      ygopro.stoc_send client, 'ERROR_MSG',{
        msg: 1
        code: 2
      }
      client.end()
      return
    replay_buffer=new Buffer(replay.replay_buffer,'binary')
    ygopro.stoc_send_chat(client,"正在观看云录像：R##{replay.replay_id} #{replay.player_names} #{replay.date_time}", 14)
    client.write replay_buffer
    client.end()
    return
  ###
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

      datas = []

      looplimit = 0

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
            cancel = false
            if ygopro.ctos_follows[ctos_proto]
              b = ctos_buffer.slice(3, ctos_message_length - 1 + 3)
              if struct = ygopro.structs[ygopro.proto_structs.CTOS[ygopro.constants.CTOS[ctos_proto]]]
                struct._setBuff(b)
                if ygopro.ctos_follows[ctos_proto].synchronous
                  cancel = ygopro.ctos_follows[ctos_proto].callback b, _.clone(struct.fields), client, server
                else
                  ygopro.ctos_follows[ctos_proto].callback b, _.clone(struct.fields), client, server
              else
                ygopro.ctos_follows[ctos_proto].callback b, null, client, server
            datas.push ctos_buffer.slice(0, 2 + ctos_message_length) unless cancel
            ctos_buffer = ctos_buffer.slice(2 + ctos_message_length)
            ctos_message_length = 0
            ctos_proto = 0
          else
            break

        looplimit++
        #log.info(looplimit)
        if looplimit > 800
          log.info("error ctos", client.name)
          server.end()
          break

      if client.established
        server.write buffer for buffer in datas
      else
        client.pre_establish_buffers.push buffer for buffer in datas

    return

  #服务端到客户端(stoc)
  stoc_buffer = new Buffer(0)
  stoc_message_length = 0
  stoc_proto = 0

  server.on 'data', (data)->
    stoc_buffer = Buffer.concat([stoc_buffer, data], stoc_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

    #unless ygopro.stoc_follows[stoc_proto] and ygopro.stoc_follows[stoc_proto].synchronous
    client.write data

    looplimit = 0

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

      looplimit++
      #log.info(looplimit)
      if looplimit > 800
        log.info("error stoc", client.name)
        server.end()
        break
    return
  return
.listen settings.port, ->
  log.info "server started", settings.port
  return

#功能模块

ygopro.ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server)->
  name = info.name.split("$")[0];
  struct = ygopro.structs["CTOS_PlayerInfo"]
  struct._setBuff(buffer)
  struct.set("name", name)
  buffer = struct.buffer
  client.name = name
  return false

ygopro.ctos_follow 'JOIN_GAME', false, (buffer, info, client, server)->
#log.info info
  if settings.modules.stop
    ygopro.stoc_send_chat(client, settings.modules.stop, 11)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 1
      code: 2
    }
    client.end()

    ###
  else if info.pass.toUpperCase()=="R"
    ygopro.stoc_send_chat(client,"以下是您近期的云录像，密码处输入 R#录像编号 即可观看", 14)
    redisdb.lrange client.remoteAddress+":replays", 0, 2, (err, result)=>
      _.each result, (replay_id,id)=>
        redisdb.hgetall "replay:"+replay_id, (err, replay)=>
          ygopro.stoc_send_chat(client,"<#{id-0+1}> R##{replay_id} #{replay.player_names} #{replay.date_time}", 14)
          return
        return
      return
    #强行等待异步执行完毕_(:з」∠)_
    setTimeout (()=> 
      ygopro.stoc_send client, 'ERROR_MSG',{
        msg: 1
        code: 2
      }
      client.end()), 500
      
  else if info.pass[0...2].toUpperCase()=="R#"
    replay_id=info.pass.split("#")[1]
    if (replay_id>0 and replay_id<=3)
      redisdb.lindex client.remoteAddress+":replays", replay_id-1, (err, replay_id)=>
        redisdb.hgetall "replay:"+replay_id, client.open_cloud_replay
        return
    else if replay_id
      redisdb.hgetall "replay:"+replay_id, client.open_cloud_replay
    else
      ygopro.stoc_send_chat(client,"没有找到录像", 11)
      ygopro.stoc_send client, 'ERROR_MSG',{
        msg: 1
        code: 2
      }
      client.end()
    ###

  else if info.version != settings.version
    ygopro.stoc_send_chat(client, settings.modules.update, 11)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 4
      code: settings.version
    }
    client.end()

  else if !info.pass.length and !settings.modules.enable_random_duel
    ygopro.stoc_send_chat(client, "房间名为空，请填写主机密码", 11)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 1
      code: 2
    }
    client.end()

  else if settings.modules.windbot and info.pass[0...2] == 'AI'

    if info.pass.length > 3 and info.pass[0...3] == 'AI#' or info.pass[0...3] == 'AI_'
      name = info.pass.slice(3)
      windbot = _.sample _.filter settings.modules.windbot, (w)->
        w.name == name or w.deck == name
      if !windbot
        ygopro.stoc_send_chat(client, '主机密码不正确 (Invalid Windbot Name)', 11)
        ygopro.stoc_send client, 'ERROR_MSG', {
          msg: 1
          code: 2
        }
        client.end()
        return
    else
      windbot = _.sample settings.modules.windbot

    room = Room.find_or_create_by_name('AI#' + Math.random().toString()) # 这个 AI# 没有特殊作用, 仅作为标记
    room.windbot = windbot
    room.private = true
    client.room = room
    client.room.connect(client)

  else if info.pass.length and settings.modules.mycard_auth
    ygopro.stoc_send_chat(client, '正在读取用户信息...', 11)
    if info.pass.length <= 8
      ygopro.stoc_send_chat(client, '主机密码不正确 (Invalid Length)', 11)
      ygopro.stoc_send client, 'ERROR_MSG', {
        msg: 1
        code: 2
      }
      client.end()
      return

    buffer = new Buffer(info.pass[0...8], 'base64')

    if buffer.length != 6
      ygopro.stoc_send_chat(client, '主机密码不正确 (Invalid Payload Length)', 11)
      ygopro.stoc_send client, 'ERROR_MSG', {
        msg: 1
        code: 2
      }
      client.end()
      return

    check = (buf)->
      checksum = 0
      for i in [0...buf.length]
        checksum += buf.readUInt8(i)
      (checksum & 0xFF) == 0

    finish = (buffer)->
      action = buffer.readUInt8(1) >> 4
      if buffer != decrypted_buffer and action in [1, 2, 4]
        ygopro.stoc_send_chat(client, '主机密码不正确 (Unauthorized)', 11)
        ygopro.stoc_send client, 'ERROR_MSG', {
          msg: 1
          code: 2
        }
        client.end()
        return

      # 1 create public room
      # 2 create private room
      # 3 join room
      # 4 join match
      switch action
        when 1,2
          name = crypto.createHash('md5').update(info.pass + client.name).digest('base64')[0...10].replace('+', '-').replace('/', '_');
          if Room.find_by_name(name)
            ygopro.stoc_send_chat(client, '主机密码不正确 (Already Existed)', 11)
            ygopro.stoc_send client, 'ERROR_MSG', {
              msg: 1
              code: 2
            }
            client.end()
            return

          opt1 = buffer.readUInt8(2)
          opt2 = buffer.readUInt16LE(3)
          opt3 = buffer.readUInt8(5)
          options = {
            lflist: 0
            time_limit: 180
            rule: (opt1 >> 5) & 3
            mode: (opt1 >> 3) & 3
            enable_priority: !!((opt1 >> 2) & 1)
            no_check_deck: !!((opt1 >> 1) & 1)
            no_shuffle_deck: !!(opt1 & 1)
            start_lp: opt2
            start_hand: opt3 >> 4
            draw_count: opt3 & 0xF
          }
          options.lflist = _.findIndex settings.lflist, (list)-> ((options.rule == 1) == list.tcg) and list.date.isBefore()
          room = new Room(name, options)
          room.title = info.pass.slice(8).replace(String.fromCharCode(0xFEFF), ' ')
          room.private = action == 2
        when 3
          name = info.pass.slice(8)
          room = Room.find_by_name(name)
          if(!room)
            ygopro.stoc_send_chat(client, '主机密码不正确 (Not Found)', 11)
            ygopro.stoc_send client, 'ERROR_MSG', {
              msg: 1
              code: 2
            }
            client.end()
            return
        when 4
          room = Room.find_or_create_by_name('M#' + info.pass.slice(8))
          room.private = true
        else
          ygopro.stoc_send_chat(client, '主机密码不正确 (Invalid Action)', 11)
          ygopro.stoc_send client, 'ERROR_MSG', {
            msg: 1
            code: 2
          }
          client.end()
          return
      client.room = room
      client.room.connect(client)

    if id = users_cache[client.name]
      secret = id % 65535 + 1;
      decrypted_buffer = new Buffer(6)
      for i in [0, 2, 4]
        decrypted_buffer.writeUInt16LE(buffer.readUInt16LE(i) ^ secret, i)
      if check(decrypted_buffer)
        return finish(decrypted_buffer)

    #TODO: query database directly, like preload.
    request
      baseUrl: settings.modules.mycard_auth,
      url: '/users/' + encodeURIComponent(client.name) + '.json',
      qs:
        api_key: 'dc7298a754828b3d26b709f035a0eeceb43e73cbd8c4fa8dec18951f8a95d2bc',
        api_username: client.name,
        skip_track_visit: true
      json: true
    , (error, response, body)->
      if body and body.user
        secret = body.user.id % 65535 + 1;
        decrypted_buffer = new Buffer(6)
        for i in [0, 2, 4]
          decrypted_buffer.writeUInt16LE(buffer.readUInt16LE(i) ^ secret, i)
        if check(decrypted_buffer)
          buffer = decrypted_buffer

      # buffer != decrypted_buffer  ==> auth failed

      if !check(buffer)
        ygopro.stoc_send_chat(client, '主机密码不正确 (Checksum Failed)', 11)
        ygopro.stoc_send client, 'ERROR_MSG', {
          msg: 1
          code: 2
        }
        client.end()
        return
      users_cache[client.name] = body.user.id
      finish(buffer)

  else if info.pass.length && !Room.validate(info.pass)
#ygopro.stoc_send client, 'ERROR_MSG',{
#  msg: 1
#  code: 1 #这返错有问题，直接双ygopro直连怎么都正常，在这里就经常弹不出提示
#}
    ygopro.stoc_send_chat(client, "房间密码不正确", 11)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 1
      code: 2
    }
    client.end()

  else if client.name == '[INCORRECT]' #模拟用户验证
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 1
      code: 2
    }
    client.end()

  else if _.indexOf(settings.BANNED_user, client.name) > -1 #账号被封
    settings.BANNED_IP.push(client.remoteAddress)
    log.info("BANNED USER LOGIN", client.name, client.remoteAddress)
    ygopro.stoc_send_chat(client, "您的账号已被封禁", 11)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 1
      code: 2
    }
    client.end()

  else if _.indexOf(settings.BANNED_IP, client.remoteAddress) > -1 #IP被封
    log.info("BANNED IP LOGIN", client.name, client.remoteAddress)
    ygopro.stoc_send_chat(client, "您的账号已被封禁", 11)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 1
      code: 2
    }
    client.end()

  else
#log.info 'join_game',info.pass, client.name
    room = Room.find_or_create_by_name(info.pass, client.remoteAddress)
    if !room
      ygopro.stoc_send_chat(client, "服务器已经爆满，请稍候再试", 11)
      ygopro.stoc_send client, 'ERROR_MSG', {
        msg: 1
        code: 2
      }
      client.end()
    else if room.error
      ygopro.stoc_send_chat(client, room.error, 11)
      ygopro.stoc_send client, 'ERROR_MSG', {
        msg: 1
        code: 2
      }
      client.end()
    else if room.started
      if settings.modules.post_start_watching
        client.room = room
        client.is_post_watcher = true
        ygopro.stoc_send_chat_to_room client.room, "#{client.name} 加入了观战"
        client.room.watchers.push client
        ygopro.stoc_send_chat client, "观战中", 14
        for buffer in client.room.watcher_buffers
          client.write buffer
      else
        ygopro.stoc_send_chat(client, "决斗已开始，不允许观战", 11)
        ygopro.stoc_send client, 'ERROR_MSG', {
          msg: 1
          code: 2
        }
        client.end()
    else
      client.room = room
      client.room.connect(client)
  return

ygopro.stoc_follow 'JOIN_GAME', false, (buffer, info, client, server)->
#欢迎信息
  return unless client.room
  if settings.modules.welcome
    ygopro.stoc_send_chat client, settings.modules.welcome
  if client.room.welcome
    ygopro.stoc_send_chat client, client.room.welcome, 14

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

    watcher.on 'data', (data)->
      return unless client.room
      client.room.watcher_buffers.push data
      for w in client.room.watchers
        w.write data if w #a WTF fix
      return

    watcher.on 'error', (error)->
#log.error "watcher error", error
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
#log.info "dialogues loaded", _.size body
      dialogues = body
    return

ygopro.stoc_follow 'GAME_MSG', false, (buffer, info, client, server)->
  msg = buffer.readInt8(0)

  if msg >= 10 and msg < 30 #SELECT开头的消息
    client.room.waiting_for_player = client
    client.room.last_active_time = moment()
  #log.info("#{ygopro.constants.MSG[msg]}等待#{client.room.waiting_for_player.name}")

  #log.info 'MSG', ygopro.constants.MSG[msg]
  if ygopro.constants.MSG[msg] == 'START'
    playertype = buffer.readUInt8(1)
    client.is_first = !(playertype & 0xf);
    client.lp = client.room.hostinfo.start_lp

  #ygopro.stoc_send_chat_to_room(client.room, "LP跟踪调试信息: #{client.name} 初始LP #{client.lp}")
  ###
  if ygopro.constants.MSG[msg] == 'WIN' and _.startsWith(client.room.name, 'M#') and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first or pos == 2
    reason = buffer.readUInt8(2)
    #log.info {winner: pos, reason: reason}
    client.room.duels.push {winner: pos, reason: reason}
  ###

  #lp跟踪
  if ygopro.constants.MSG[msg] == 'DAMAGE' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    client.room.dueling_players[pos].lp -= val
    if 0 < client.room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(client.room, "你的生命已经如风中残烛了！", 15)

  if ygopro.constants.MSG[msg] == 'RECOVER' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    client.room.dueling_players[pos].lp += val

  if ygopro.constants.MSG[msg] == 'LPUPDATE' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    client.room.dueling_players[pos].lp = val

  if ygopro.constants.MSG[msg] == 'PAY_LPCOST' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    client.room.dueling_players[pos].lp -= val
    if 0 < client.room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(client.room, "背水一战！", 15)

  #登场台词
  if settings.modules.dialogues
    if ygopro.constants.MSG[msg] == 'SUMMONING' or ygopro.constants.MSG[msg] == 'SPSUMMONING'
      card = buffer.readUInt32LE(1)
      if dialogues[card]
        for line in _.lines dialogues[card][Math.floor(Math.random() * dialogues[card].length)]
          ygopro.stoc_send_chat client, line, 15
  return

#房间管理
ygopro.ctos_follow 'HS_KICK', true, (buffer, info, client, server)->
  return unless client.room
  for player in client.room.players
    if player and player.pos == info.pos and player != client
      ygopro.stoc_send_chat_to_room client.room, "#{player.name} 被请出了房间", 11
  return false

ygopro.stoc_follow 'TYPE_CHANGE', false, (buffer, info, client, server)->
  selftype = info.type & 0xf;
  is_host = ((info.type >> 4) & 0xf) != 0;
  client.is_host = is_host
  client.pos = selftype
  #console.log "TYPE_CHANGE to #{client.name}:", info, selftype, is_host
  return

ygopro.stoc_follow 'HS_PLAYER_CHANGE', false, (buffer, info, client, server)->
  return unless client.room and client.room.max_player and client.is_host
  pos = info.status >> 4;
  is_ready = (info.status & 0xf) == 9;
  if pos < client.room.max_player
    client.room.ready_player_count_without_host = 0
    for player in client.room.players
      if player.pos == pos
        player.is_ready = is_ready
      unless player.is_host
        client.room.ready_player_count_without_host += player.is_ready
    if client.room.ready_player_count_without_host >= client.room.max_player - 1
#log.info "all ready"
      setTimeout (()-> wait_room_start(client.room, 20);return), 1000
  return

wait_room_start = (room, time)->
  unless !room or room.started or room.ready_player_count_without_host < room.max_player - 1
    time -= 1
    if time
      unless time % 5
        ygopro.stoc_send_chat_to_room room, "#{if time <= 9 then ' ' else ''}#{time}秒后房主若不开始游戏将被请出房间", if time <= 9 then 11 else 8
      setTimeout (()-> wait_room_start(room, time);return), 1000
    else
      for player in room.players
        if player and player.is_host
          Room.ban_player(player.name, player.ip, "挂房间")
          ygopro.stoc_send_chat_to_room room, "#{player.name} 被系统请出了房间", 11
          player.end()
  return

#tip
ygopro.stoc_send_random_tip = (client)->
  ygopro.stoc_send_chat client, "Tip: " + tips[Math.floor(Math.random() * tips.length)] if tips
  return
ygopro.stoc_send_random_tip_to_room = (room)->
  ygopro.stoc_send_chat_to_room room, "Tip: " + tips[Math.floor(Math.random() * tips.length)] if tips
  return

setInterval ()->
  for room in Room.all
    ygopro.stoc_send_random_tip_to_room(room) unless room and room.started
  return
, 30000

tips = null
if settings.modules.tips
  request
    url: settings.modules.tips
    json: true
  , (error, response, body)->
    tips = body
    #log.info "tips loaded", tips.length
    return

if settings.modules.mycard_auth and process.env.MYCARD_AUTH_DATABASE
  pg = require('pg');
  pg.connect process.env.MYCARD_AUTH_DATABASE, (error, client, done)->
    throw error if error
    client.query 'SELECT username, id from users', (error, result)->
      throw error if error
      done();
      for row in result.rows
        users_cache[row.username] = row.id
      console.log("users loaded", _.keys(users_cache).length)

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server)->
  return unless client.room
  unless client.room.started #first start
    client.room.started = true
    roomlist.delete client.room.name if settings.modules.enable_websocket_roomlist and not client.room.private
    #client.room.duels = []
    client.room.dueling_players = []
    for player in client.room.players when player.pos != 7
      client.room.dueling_players[player.pos] = player
      client.room.player_datas.push ip: player.remoteAddress, name: player.name
      if client.room.windbot
        client.room.dueling_players[1 - player.pos] = {}
  if settings.modules.tips
    ygopro.stoc_send_random_tip(client)
  return

ygopro.ctos_follow 'CHAT', true, (buffer, info, client, server)->
  cancel = _.startsWith(_.trim(info.msg), "/")
  client.room.last_active_time = moment() unless cancel or not client.room.random_type
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
#log.warn 'ping', stdout
            ygopro.stoc_send_chat_to_room client.room, stdout
        return

    when '/help'
      ygopro.stoc_send_chat(client, "YGOSrv233 指令帮助")
      ygopro.stoc_send_chat(client, "/help 显示这个帮助信息")
      ygopro.stoc_send_chat(client, "/roomname 显示当前房间的名字")
      ygopro.stoc_send_chat(client, "/tip 显示一条提示") if settings.modules.tips

    when '/tip'
      ygopro.stoc_send_random_tip(client) if settings.modules.tips

    when '/roomname'
      ygopro.stoc_send_chat(client, "您当前的房间名是 " + client.room.name) if client.room

    when '/test'
      ygopro.stoc_send_hint_card_to_room(client.room, 2333365)

  return cancel

ygopro.ctos_follow 'UPDATE_DECK', false, (buffer, info, client, server)->
#log.info info
  main = (info.deckbuf[i] for i in [0...info.mainc])
  side = (info.deckbuf[i] for i in [info.mainc...info.mainc + info.sidec])
  client.main = main
  client.side = side
  return

ygopro.ctos_follow 'RESPONSE', false, (buffer, info, client, server)->
  return unless client.room and client.room.random_type
  client.room.last_active_time = moment()
  return

ygopro.ctos_follow 'HAND_RESULT', false, (buffer, info, client, server)->
  return unless client.room and client.room.random_type
  if client.is_host
    client.room.waiting_for_player = client.room.waiting_for_player2
  client.room.last_active_time = moment().subtract(settings.modules.hang_timeout - 19, 's')
  return

ygopro.ctos_follow 'TP_RESULT', false, (buffer, info, client, server)->
  return unless client.room and client.room.random_type
  client.room.last_active_time = moment()
  return

ygopro.stoc_follow 'SELECT_HAND', false, (buffer, info, client, server)->
  return unless client.room and client.room.random_type
  if client.is_host
    client.room.waiting_for_player = client
  else
    client.room.waiting_for_player2 = client
  client.room.last_active_time = moment().subtract(settings.modules.hang_timeout - 19, 's')
  return

ygopro.stoc_follow 'SELECT_TP', false, (buffer, info, client, server)->
  return unless client.room and client.room.random_type
  client.room.waiting_for_player = client
  client.room.last_active_time = moment()
  return

setInterval ()->
  for room in Room.all when room and room.started and room.random_type and room.last_active_time and room.waiting_for_player
    time_passed = Math.floor((moment() - room.last_active_time) / 1000)
    #log.info time_passed
    if time_passed >= settings.modules.hang_timeout
      room.last_active_time = moment()
      Room.ban_player(room.waiting_for_player.name, room.waiting_for_player.ip, "挂机")
      ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} 被系统请出了房间", 11)
      room.waiting_for_player.server.end()
    else if time_passed >= (settings.modules.hang_timeout - 20) and not (time_passed % 10)
      ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} 已经很久没有操作了，若继续挂机，将于#{settings.modules.hang_timeout - time_passed}秒后被请出房间", 11)
  return
, 1000

#http
if settings.modules.http

  requestListener = (request, response)->
    parseQueryString = true
    u = url.parse(request.url, parseQueryString)
    pass_validated = u.query.pass == settings.modules.http.password

    if u.pathname == '/api/getrooms'
      if u.query.pass and !pass_validated
        response.writeHead(200);
        response.end(u.query.callback + '( {"rooms":[{"roomid":"0","roomname":"密码错误","needpass":"true"}]} );')
      else
        response.writeHead(200);
        roomsjson = JSON.stringify rooms: (for room in Room.all when room.established
          pid: room.process.pid.toString(),
          roomid: room.port.toString(),
          roomname: if pass_validated then room.name else room.name.split('$', 2)[0],
          needpass: (room.name.indexOf('$') != -1).toString(),
          users: (for player in room.players when player.pos?
            id: (-1).toString(),
            name: player.name,
            pos: player.pos
          ),
          istart: if room.started then 'start' else 'wait'
        )
        response.end(u.query.callback + "( " + roomsjson + " );")

    else if u.pathname == '/api/message'
      if !pass_validated
        response.writeHead(200);
        response.end(u.query.callback + "( '密码错误', 0 );");
        return

      if u.query.shout
        for room in Room.all
          ygopro.stoc_send_chat_to_room(room, u.query.shout, 16)
        response.writeHead(200)
        response.end(u.query.callback + "( 'shout ok', '" + u.query.shout + "' );")

      else if u.query.stop
        if u.query.stop == 'false'
          u.query.stop = false
        settings.modules.stop = u.query.stop
        response.writeHead(200)
        response.end(u.query.callback + "( 'stop ok', '" + u.query.stop + "' );")

      else if u.query.welcome
        settings.modules.welcome = u.query.welcome
        response.writeHead(200)
        response.end(u.query.callback + "( 'welcome ok', '" + u.query.welcome + "' );")

      else if u.query.ban
        settings.BANNED_user.push(u.query.ban)
        response.writeHead(200)
        response.end(u.query.callback + "( 'ban ok', '" + u.query.ban + "' );")

      else
        response.writeHead(404);
        response.end();

    else
      response.writeHead(404);
      response.end();
    return

  http_server = http.createServer(requestListener)
  http_server.listen settings.modules.http.port

  if settings.modules.http.ssl.enabled
    https = require 'https'
    options =
      cert: fs.readFileSync(settings.modules.http.ssl.cert)
      key: fs.readFileSync(settings.modules.http.ssl.key)
    https_server = https.createServer(options, requestListener)
    roomlist.init https_server, Room
    https_server.listen settings.modules.http.ssl.port