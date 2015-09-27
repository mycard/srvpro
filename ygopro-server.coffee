#标准库
net = require 'net'
http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'
os = require 'os'
execFile = require('child_process').execFile

#三方库
_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());

request = require 'request'

bunyan = require 'bunyan'

#heapdump = require 'heapdump'

#配置文件
settings = require './config.json'

#组件
ygopro = require './ygopro.js'
Room = require './room.js'


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
    server.closed = true unless server.closed
    unless client.closed
      ygopro.stoc_send_chat(client, "服务器关闭了连接")
      client.end()
    return

  server.on 'error', (error)->
    #log.info "server error", client.name, error
    tribute(server)
    server.closed = error
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
      
      datas = []

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
              b = ctos_buffer.slice(3, ctos_message_length-1+3)
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
  name=info.name.split("$")[0];
  struct = ygopro.structs["CTOS_PlayerInfo"]
  struct._setBuff(buffer)
  struct.set("name",name)
  buffer = struct.buffer
  client.name = name
  return false

ygopro.ctos_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  #log.info info
  if settings.modules.stop
    ygopro.stoc_send_chat(client,settings.modules.stop)
    ygopro.stoc_send client, 'ERROR_MSG',{
      msg: 1
      code: 2
    }
    client.end()  
  
  else if info.version != settings.version
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
    #log.info 'join_game',info.pass, client.name
    client.room = Room.find_or_create_by_name(info.pass)
    if !client.room
      ygopro.stoc_send_chat(client,"服务器已经爆满，请稍候再试")
      ygopro.stoc_send client, 'ERROR_MSG',{
        msg: 1
        code: 2
      }
      client.end()
    else if client.room.started
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
  return unless client.room
  if settings.modules.welcome
    ygopro.stoc_send_chat client, settings.modules.welcome
  ##if (os.freemem() / os.totalmem())<=0.1
  ##  ygopro.stoc_send_chat client, "服务器已经爆满，随时存在崩溃风险！"

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
      ygopro.stoc_send_chat_to_room(client.room, "你的生命已经如风中残烛了！")

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
      ygopro.stoc_send_chat_to_room(client.room, "背水一战！")

  #登场台词
  if settings.modules.dialogues
    if ygopro.constants.MSG[msg] == 'SUMMONING' or ygopro.constants.MSG[msg] == 'SPSUMMONING'
      card = buffer.readUInt32LE(1)
      if dialogues[card]
        for line in _.lines dialogues[card][Math.floor(Math.random() * dialogues[card].length)]
          ygopro.stoc_send_chat client, line
  return

#房间管理
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
      #log.info "tips loaded", tips.length
      return

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server)->
  return unless client.room
  unless client.room.started #first start
    client.room.started = true
    #client.room.duels = []
    client.room.dueling_players = []
    for player in client.room.players when player.pos != 7
      client.room.dueling_players[player.pos] = player
  if settings.modules.tips
    ygopro.stoc_send_random_tip(client)
  return

ygopro.ctos_follow 'CHAT', true, (buffer, info, client, server)->
  cancel = _.startsWith(_.trim(info.msg),"/")
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
      ygopro.stoc_send_chat(client,"YGOSrv233 指令帮助")
      ygopro.stoc_send_chat(client,"/help 显示这个帮助信息")
      ygopro.stoc_send_chat(client,"/tip 显示一条提示") if settings.modules.tips
    
    when '/tip'
      ygopro.stoc_send_random_tip(client) if settings.modules.tips
  return cancel

ygopro.ctos_follow 'UPDATE_DECK', false, (buffer, info, client, server)->
  #log.info info
  main = (info.deckbuf[i] for i in [0...info.mainc])
  side = (info.deckbuf[i] for i in [info.mainc...info.mainc+info.sidec])
  client.main = main
  client.side = side
  return

#http
if settings.modules.http
  http_server = http.createServer (request, response)->
      u = url.parse(request.url,1)
      #log.info u
      if u.pathname == '/count.json'
        response.writeHead(200);
        response.end(Room.all.length.toString())

      else if u.pathname == '/rooms.js'
        response.writeHead(200);
        roomsjson = JSON.stringify rooms: (for room in Room.all when room.established
          roomid: room.port.toString(),
          roomname: room.name.split('$',2)[0],
          needpass: (room.name.indexOf('$') != -1).toString(),
          users: (for player in room.players when player.pos?
            id: (-1).toString(),
            name: player.name,
            pos: player.pos
          ),
          istart: if room.started then 'start' else 'wait'
        )
        response.end("loadroom( " + roomsjson + " );");
        # todo: 增加JSONP支持

      else if u.query.operation == 'getroomjson'
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

      else if u.query.pass == settings.modules.http.password && u.query.shout
        for room in Room.all
          ygopro.stoc_send_chat_to_room(room, u.query.shout)
        response.writeHead(200)
        response.end("shout " + u.query.shout + " ok")

      else if u.query.pass == settings.modules.http.password && u.query.stop
        settings.modules.stop = u.query.stop
        response.writeHead(200)
        response.end("stop " + u.query.stop + " ok")

      else if u.query.pass == settings.modules.http.password && u.query.welcome
        settings.modules.welcome = u.query.welcome
        response.writeHead(200)
        response.end("welcome " + u.query.welcome + " ok")

      else
        response.writeHead(404);
        response.end();
      return
  http_server.listen settings.modules.http.port
