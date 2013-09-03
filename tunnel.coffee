util = require "util"
net = require "net"
spawn = require('child_process').spawn
freeport = require 'freeport'
Struct = require('struct').Struct

structs_declaration = require './structs.json'  #结构体声明
typedefs = require './typedefs.json'            #类型声明
proto_structs = require './proto_structs.json' #消息与结构体的对应，未完成，对着duelclient.cpp加
constants = require './constants.json'          #network.h里定义的常量

settings = require './config.json'            #本机IP端口设置

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
  console.log 'stoc_sent:', buffer

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
  console.log 'ctos_sent:', buffer

server_listener = (pass, port, client, server)->
  client.connected = true
  rooms[pass] = port
  console.log "connected #{port}"

  stoc_buffer = new Buffer(0)
  stoc_message_length = 0
  stoc_proto = 0

  for buffer in client.pre_connecion_buffers
    server.write buffer

  server.on "data", (data) ->
    console.log 'server: ', data
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
          console.log constants.STOC[stoc_proto]
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

rooms = {}
rooms_players = {}

net.createServer (client) ->
  client.connected = false

  ctos_buffer = new Buffer(0)
  ctos_message_length = 0
  ctos_proto = 0

  client.pre_connecion_buffers = new Array()

  server = new net.Socket()

  client.on "data", (data) ->
    console.log 'client: ', data
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
          console.log constants.CTOS[ctos_proto]
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
.listen settings.port

ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server)->
  client.player = info.name
  console.log 'PLAYER_INFO', info

ctos_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  console.log 'JOIN_GAME', info
  if info.version != settings.version
    stoc_send client, 'ERROR_MSG',{
      msg: 4
      code: settings.version
    }
    client.end()
  else if !info.pass.length
    stoc_send client, 'JOIN_GAME', {}
    stoc_send client, 'HS_PLAYER_ENTER', {
      name: '提示: 房间为空，请修改房间名'
      pos: 0
    }
  else if info.pass == '[INCORRECT]' #房间密码验证
    stoc_send client, 'ERROR_MSG',{
      msg: 1
      code: 1 #这返错有问题，直接双ygopro直连怎么都正常，在服务器上就经常弹不出提示
    }
    client.end()
  else
    if client.player != '[INCORRECT]' #用户验证

      if rooms[info.pass]
        if typeof rooms[info.pass] == 'number' #already connected
          server.connect rooms[info.pass], '127.0.0.1', ->
            server_listener(info.pass, rooms[info.pass], client, server)
        else
          rooms[info.pass].push client
      else
        freeport (err, port)->
          if(err)
            stoc_send client, 'ERROR_MSG',{
              msg: 1
              code: 2
            }
            client.end()
          else
            room = spawn './ygopro', [port, 0, 0, 0, 'F', 'T', 'F', 8000, 5, 1], cwd: 'ygocore'
            rooms[info.pass] = [client]
            room.on 'exit', (code)->
              delete rooms[info.pass]
            room.stdout.once 'data', (data)->
              rooms[info.pass].forEach (client)->
                server.connect port, '127.0.0.1', ->
                  server_listener(info.pass, port, client, server)

    else
      stoc_send client, 'ERROR_MSG',{
        msg: 1
        code: 2
      }
      client.end()

stoc_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  console.log 'JOIN_GAME', info

stoc_follow 'HS_PLAYER_CHANGE', false, (buffer, info, client, server)->
  console.log 'HS_PLAYER_CHANGE', info

stoc_follow 'HS_PLAYER_ENTER', false, (buffer, info, client, server)->
  stoc_send client, 'CHAT', {
    player: 8
    msg: "这里是测试用的新直连服\n               ˉˉˉˉˉˉˉˉˉˉˉˉˉˉˉˉ\0"
  }
  stoc_send client, 'CHAT', {
    player: 8
    msg: "现在这个还不稳定,随时可能崩溃或者关闭服务哦\0"
  }
  stoc_send client, 'CHAT', {
    player: 8
    msg: "喵喵喵喵\0"
  }
stoc_follow 'CHAT', false, (buffer, info, client, server)->
  console.log info, buffer


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