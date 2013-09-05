#官方库
net = require 'net'
http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'
spawn = require('child_process').spawn

#三方库
freeport = require 'freeport'
Struct = require('struct').Struct
_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());
_.str.include('Underscore.string', 'string');
Inotify = require('inotify').Inotify
request = require 'request'

#常量/类型声明
structs_declaration = require './structs.json'  #结构体声明
typedefs = require './typedefs.json'            #类型声明
proto_structs = require './proto_structs.json' #消息与结构体的对应，未完成，对着duelclient.cpp加
constants = require './constants.json'          #network.h里定义的常量

#配置文件
settings = require './config.json'            #本机IP端口设置

class Room
  @all = []

  #name
  #port
  #players: [{client, server, name, pos}]
  #process
  #established
  #alive
  constructor: (name, port, client) ->
    @name = name
    @port = port
    @alive = true
    @players = []
    @add_client(client)
    Room.all.push this #这个故事告诉我们没事不要乱new Room

  delete: (room)->
    delete Room.all[_.indexOf(Room.all, room)]

  add_client: (client)->
    @players.push {client: client, name: client.player}


  #需要性能优化，建立个索引
  @find_by_name: (name)->
    _.find @all, (room)->
      room.name == name
  @find_by_port: (port)->
    _.find @all, (room)->
      room.name == port
  @find_by_client: (client)->
    _.find @all, (room)->
      _.some room.players, (player)->
        player.client == client




#debug模式 端口号+1
debug = false
if process.argv[2] == '--debug'
  settings.port++
  settings.http_port++
  debug = true

#结构体定义
structs = {}
for name, declaration of structs_declaration
  result = Struct()
  for field in declaration
    if field.encoding
      switch field.encoding
        when "UTF-16LE" then result.chars field.name, field.length*2, field.encoding
        else throw "unsupported encoding: #{file.encoding}"
    else
      type = field.type
      type = typedefs[type] if typedefs[type]
      if field.length
        result.array field.name, field.length, type #不支持结构体
      else
        if structs[type]
          result.struct field.name, structs[type]
        else
          result[type] field.name
  structs[name] = result


#消息跟踪函数 需要重构, 另暂时只支持异步, 同步没做.
stoc_follows = {}
ctos_follows = {}
stoc_follow = (proto, synchronous, callback)->
  if typeof proto == 'string'
    for key, value of constants.STOC
      if value == proto
        proto = key
        break
    throw "unknown proto" if !constants.STOC[proto]
  stoc_follows[proto] = {callback: callback, synchronous: synchronous}
ctos_follow = (proto, synchronous, callback)->
  if typeof proto == 'string'
    for key, value of constants.CTOS
      if value == proto
        proto = key
        break
    throw "unknown proto" if !constants.CTOS[proto]
  ctos_follows[proto] = {callback: callback, synchronous: synchronous}


#消息发送函数,至少要把俩合起来....
stoc_send = (socket, proto, info)->
  #console.log proto, proto_structs.STOC[proto], structs[proto_structs.STOC[proto]]

  if typeof info == 'undefined'
    buffer = ""
  else if Buffer.isBuffer(info)
    buffer = info
  else
    struct = structs[proto_structs.STOC[proto]]
    struct.allocate()
    struct.set info
    buffer = struct.buffer()

  if typeof proto == 'string' #需要重构
    for key, value of constants.STOC
      if value == proto
        proto = key
        break
    throw "unknown proto" if !constants.STOC[proto]

  header = new Buffer(3)
  header.writeUInt16LE buffer.length + 1, 0
  header.writeUInt8 proto, 2
  socket.write header
  socket.write buffer if buffer.length
  console.log 'stoc_sent:', buffer if debug

ctos_send = (socket, proto, info)->
  #console.log proto, proto_structs.CTOS[proto], structs[proto_structs.CTOS[proto]]

  if typeof info == 'undefined'
    buffer = ""
  else if Buffer.isBuffer(info)
    buffer = info
  else
    struct = structs[proto_structs.CTOS[proto]]
    struct.allocate()
    struct.set info
    buffer = struct.buffer()

  if typeof proto == 'string' #需要重构
    for key, value of constants.CTOS
      if value == proto
        proto = key
        break
    throw "unknown proto" if !constants.CTOS[proto]

  header = new Buffer(3)
  header.writeUInt16LE buffer.length + 1, 0
  header.writeUInt8 proto, 2
  socket.write header
  socket.write buffer if buffer.length
  console.log 'ctos_sent:', buffer if debug

#util
stoc_send_chat = (client, msg, player = 8)->
  stoc_send client, 'CHAT', {
    player: player
    msg:  msg
  }



#服务器端消息监听函数
server_listener = (port, client, server)->
  client.connected = true
  console.log "connected #{port}"

  stoc_buffer = new Buffer(0)
  stoc_message_length = 0
  stoc_proto = 0

  for buffer in client.pre_connecion_buffers
    server.write buffer

  server.on "data", (data) ->
    console.log 'server: ', data if debug
    stoc_buffer = Buffer.concat([stoc_buffer, data], stoc_buffer.length + data.length)
    #buffer的错误使用方式，好孩子不要学

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
          console.log constants.STOC[stoc_proto] if debug
          if stoc_follows[stoc_proto]
            b = stoc_buffer.slice(3, stoc_message_length - 1 + 3)
            if struct = structs[proto_structs.STOC[constants.STOC[stoc_proto]]]
              struct._setBuff(b)
              setTimeout stoc_follows[stoc_proto].callback, 0, b, struct.fields, client, server
            else
              setTimeout stoc_follows[stoc_proto].callback, 0, b, null, client, server

          stoc_buffer = stoc_buffer.slice(2 + stoc_message_length)
          stoc_message_length = 0
          stoc_proto = 0
        else
          break

    unless stoc_follows[stoc_proto] and stoc_follows[stoc_proto].synchronous
      client.write data

  server.on "error", (e) ->
    console.log "server error #{e}"
    client.end()

  server.on "close", (had_error) ->
    console.log "server closed #{had_error}"
    client.end()


#main
listener = net.createServer (client) ->
  client.connected = false

  ctos_buffer = new Buffer(0)
  ctos_message_length = 0
  ctos_proto = 0

  client.pre_connecion_buffers = new Array()

  server = new net.Socket()
  server.on "error", (e) ->
    console.log "server error #{e}"

  client.on "data", (data) ->
    console.log 'client: ', data if debug
    ctos_buffer = Buffer.concat([ctos_buffer, data], ctos_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

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
          console.log constants.CTOS[ctos_proto] if debug
          if ctos_follows[ctos_proto]
            b = ctos_buffer.slice(3, ctos_message_length-1+3)
            if struct = structs[proto_structs.CTOS[constants.CTOS[ctos_proto]]]
              struct._setBuff(b)
              setTimeout ctos_follows[ctos_proto].callback, 0, b, struct.fields, client, server
            else
              setTimeout ctos_follows[ctos_proto].callback, 0, b, null, client, server

          ctos_buffer = ctos_buffer.slice(2 + ctos_message_length)
          ctos_message_length = 0
          ctos_proto = 0
        else
          break

    unless ctos_follows[ctos_proto] and ctos_follows[ctos_proto].synchronous
      if client.connected
        server.write data
      else
        client.pre_connecion_buffers.push data

  client.on "error", (e) ->
    console.log "client error #{e}"
    server.end()

  client.on "close", (had_error) ->
    console.log "client closed #{had_error}"
    server.end()
.listen settings.port, null, null, ->
  console.log "server started on #{settings.ip}:#{settings.port}"

ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server)->
  client.player = info.name

ctos_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  room_name = info.pass
  if info.version != settings.version
    stoc_send client, 'ERROR_MSG',{
      msg: 4
      code: settings.version
    }
    client.end()
  else if !room_name.length
    stoc_send client, 'JOIN_GAME', {}
    stoc_send client, 'HS_PLAYER_ENTER', {
      name: '提示: 房间为空，请修改房间名'
      pos: 0
    }
  else if room_name == '[INCORRECT]' #房间密码验证
    stoc_send client, 'ERROR_MSG',{
      msg: 1
      code: 1 #这返错有问题，直接双ygopro直连怎么都正常，在服务器上就经常弹不出提示
    }
    client.end()
  else
    if client.player != '[INCORRECT]' #用户验证
      room = Room.find_by_name(room_name)
      if room
        room.add_client client
        if room.established
          server.connect room.port, '127.0.0.1', ->
            server_listener(room.port, client, server)
      else
        freeport (err, port)->
          room = Room.find_by_name(room_name)
          if room #如果等freeport的时间差又来了个.....
            room.add_client client
            if room.established
              server.connect room.port, '127.0.0.1', ->
                server_listener(room.port, client, server)
          else
            if(err)
              stoc_send client, 'ERROR_MSG',{
                msg: 1
                code: 2
              }
              client.end()
            else
              room = new Room(room_name, port, client)
              if room_name[0...2] == 'M#'
                param = [0, 0, 1, 'F', 'F', 'F', 8000, 5, 1]
              else if room_name[0...2] == 'T#'
                param = [0, 0, 2, 'F', 'F', 'F', 8000, 5, 1]
              else if (param = room_name.match /^(\d)?(\d)(\d)(T|F)(T|F)(T|F)(\d+),(\d+),(\d+)/i)
                param.shift()
                param[0] == parseInt(param[0])
              else
                param = [0, 0, 0, 'F', 'F', 'F', 8000, 5, 1]

              param.unshift port
              process = spawn './ygopro', param, cwd: 'ygocore'
              room.process = process
              process.on 'exit', (code)->
                room.delete()
              process.stdout.once 'data', (data)->
                room.established = true
                _.each room.players, (player)->
                  server.connect port, '127.0.0.1', ->
                    server_listener(port, player.client, server)
    else
      stoc_send client, 'ERROR_MSG',{
        msg: 1
        code: 2
      }
      client.end()

######################################################################################################################

#欢迎信息
stoc_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  stoc_send client, 'CHAT', {
    player: 8
    msg: "Mycard Debugging Server"
  }
  stoc_send client, 'CHAT', {
    player: 8
    msg: "这里是测试中的新服务器, 还不稳定, 随时可能崩溃, 遇到意外请淡定\n                           ˉˉˉˉˉ"
  }

#登场台词
dialogues = {}
request
  url: 'https://my-card.in/dialogues.json'
  json: true
  , (error, response, body)->
    dialogues = body
    console.log "loaded #{_.size body} dialogues"

stoc_follow 'GAME_MSG', false, (buffer, info, client, server)->
  msg = buffer.readInt8(0)
  if constants.MSG[msg] == 'SUMMONING' or constants.MSG[msg] == 'SPSUMMONING'
    card = buffer.readUInt32LE(1)
    if dialogues[card]
      for line in _.lines dialogues[card][Math.floor(Math.random() * dialogues[card].length)]
        stoc_send_chat client, line
#积分
  if constants.MSG[msg] == 'WIN'
    player = buffer.readUInt8(1)
    type = buffer.readUInt8(2)
    console.log player, type



#stoc_follow 'HS_PLAYER_CHANGE', false, (buffer, info, client, server)->
#  console.log 'HS_PLAYER_CHANGE', info


#房间数量
http.createServer (request, response)->
  if url.parse(request.url).pathname == '/count.json'
    response.writeHead(200);
    response.end(rooms.length.toString())
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
  for room in rooms
    if room.alive
      room.alive = false
    else
      console.log "kill #{port} #{room}"
      room.process.kill()
, 900000

#tip
stoc_send_tip = (client, tip)->
  lines = _.lines(tip)
  stoc_send_chat(client, "Tip: #{lines[0]}")
  for line in lines.slice(1)
    stoc_send_chat(client, line)

stoc_send_random_tip = (client)->
  stoc_send_tip client, tips[Math.floor(Math.random() * tips.length)] if tips

tips = null
request
  url: 'https://my-card.in/tips.json'
  json: true
  , (error, response, body)->
    tips = body
    console.log "loaded #{tips.length} tips"

stoc_follow 'DUEL_START', false, (buffer, info, client, server)->
  stoc_send_random_tip(client)

ctos_follow 'CHAT', false, (buffer, info, client, server)->
  if _.trim(info.msg) == '/tip'
    stoc_send_random_tip(client)

###
# 开包大战

packs_weighted_cards = {}
for pack, cards of require './packs.json'
  packs_weighted_cards[pack] = []
  for card in cards
    for i in [0..card.count]
      packs_weighted_cards[pack].push card.card

console.log packs_weighted_cards

ctos_follow 'UPDATE_DECK', false, (buffer, info, client, server)->
  ctos_send server, 'HS_NOTREADY'

  deck = []
  for pack in client.player
    for i in [0...5]
      deck.push packs_weighted_cards[pack][Math.floor(Math.random()*packs_weighted_cards[pack].length)]


  ctos_send server, 'UPDATE_DECK', {
    mainc: deck.length,
    sidec: 0,
    deckbuf: deck
  }
  ctos_send server, 'HS_READY'

###

