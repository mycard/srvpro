_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());

Struct = require('struct').Struct

#常量/类型声明
structs_declaration = require './structs.json'  #结构体声明
typedefs = require './typedefs.json'            #类型声明
@proto_structs = require './proto_structs.json' #消息与结构体的对应，未完成，对着duelclient.cpp加
@constants = require './constants.json'          #network.h里定义的常量

#结构体定义
@structs = {}
for name, declaration of structs_declaration
  result = Struct()
  for field in declaration
    if field.encoding
      switch field.encoding
        when "UTF-16LE" then result.chars field.name, field.length*2, field.encoding
        else throw "unsupported encoding: #{field.encoding}"
    else
      type = field.type
      type = typedefs[type] if typedefs[type]
      if field.length
        result.array field.name, field.length, type #不支持结构体
      else
        if @structs[type]
          result.struct field.name, @structs[type]
        else
          result[type] field.name
  @structs[name] = result


#消息跟踪函数 需要重构, 另暂时只支持异步, 同步没做.
@stoc_follows = {}
@ctos_follows = {}
@stoc_follow = (proto, synchronous, callback)->
  if typeof proto == 'string'
    for key, value of @constants.STOC
      if value == proto
        proto = key
        break
    throw "unknown proto" if !@constants.STOC[proto]
  @stoc_follows[proto] = {callback: callback, synchronous: synchronous}
  return
@ctos_follow = (proto, synchronous, callback)->
  if typeof proto == 'string'
    for key, value of @constants.CTOS
      if value == proto
        proto = key
        break
    throw "unknown proto" if !@constants.CTOS[proto]
  @ctos_follows[proto] = {callback: callback, synchronous: synchronous}
  return


#消息发送函数,至少要把俩合起来....
@stoc_send = (socket, proto, info)->
  #console.log proto, proto_structs.STOC[proto], structs[proto_structs.STOC[proto]]
  if typeof info == 'undefined'
    buffer = ""
  else if Buffer.isBuffer(info)
    buffer = info
  else
    struct = @structs[@proto_structs.STOC[proto]]
    struct.allocate()
    struct.set info
    buffer = struct.buffer()

  if typeof proto == 'string' #需要重构
    for key, value of @constants.STOC
      if value == proto
        proto = key
        break
    throw "unknown proto" if !@constants.STOC[proto]

  header = new Buffer(3)
  header.writeUInt16LE buffer.length + 1, 0
  header.writeUInt8 proto, 2
  socket.write header
  socket.write buffer if buffer.length
  return

@ctos_send = (socket, proto, info)->
  #console.log proto, proto_structs.CTOS[proto], structs[proto_structs.CTOS[proto]]
  if typeof info == 'undefined'
    buffer = ""
  else if Buffer.isBuffer(info)
    buffer = info
  else
    struct = @structs[@proto_structs.CTOS[proto]]
    struct.allocate()
    struct.set info
    buffer = struct.buffer()

  if typeof proto == 'string' #需要重构
    for key, value of @constants.CTOS
      if value == proto
        proto = key
        break
    throw "unknown proto" if !@constants.CTOS[proto]

  header = new Buffer(3)
  header.writeUInt16LE buffer.length + 1, 0
  header.writeUInt8 proto, 2
  socket.write header
  socket.write buffer if buffer.length
  return

#util
@stoc_send_chat = (client, msg, player = 8)->
  for line in _.lines(msg)
    @stoc_send client, 'CHAT', {
      player: player
      msg: line
    }
  return

@stoc_send_chat_to_room = (room, msg, player = 8)->
  for client in room.players
    @stoc_send_chat(client, msg, player) if client
  for client in room.watchers
    @stoc_send_chat(client, msg, player) if client
  return