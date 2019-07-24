_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports())

Struct = require('./struct.js').Struct
loadJSON = require('load-json-file').sync

@i18ns = loadJSON './data/i18n.json'

#常量/类型声明
structs_declaration = loadJSON './data/structs.json'  #结构体声明
typedefs = loadJSON './data/typedefs.json'            #类型声明
@proto_structs = loadJSON './data/proto_structs.json' #消息与结构体的对应，未完成，对着duelclient.cpp加
@constants = loadJSON './data/constants.json'          #network.h里定义的常量

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
@stoc_follows_before = {}
@stoc_follows_after = {}
@ctos_follows = {}
@ctos_follows_before = {}
@ctos_follows_after = {}

@replace_proto = (proto, tp) ->
  if typeof(proto) != "string"
    return proto
  changed_proto = proto
  for key, value of @constants[tp]
    if value == proto
      changed_proto = key
      break
  throw "unknown proto" if !@constants[tp][changed_proto]
  return changed_proto

@stoc_follow = (proto, synchronous, callback)->
  changed_proto = @replace_proto(proto, "STOC")
  @stoc_follows[changed_proto] = {callback: callback, synchronous: synchronous}
  return
@stoc_follow_before = (proto, synchronous, callback)->
  changed_proto = @replace_proto(proto, "STOC")
  if !@stoc_follows_before[changed_proto]
    @stoc_follows_before[changed_proto] = []
  @stoc_follows_before[changed_proto].push({callback: callback, synchronous: synchronous})
  return
@stoc_follow_after = (proto, synchronous, callback)->
  changed_proto = @replace_proto(proto, "STOC")
  if !@stoc_follows_after[changed_proto]
    @stoc_follows_after[changed_proto] = []
  @stoc_follows_after[changed_proto].push({callback: callback, synchronous: synchronous})
  return
@ctos_follow = (proto, synchronous, callback)->
  changed_proto = @replace_proto(proto, "CTOS")
  @ctos_follows[changed_proto] = {callback: callback, synchronous: synchronous}
  return
@ctos_follow_before = (proto, synchronous, callback)->
  changed_proto = @replace_proto(proto, "CTOS")
  if !@ctos_follows_before[changed_proto]
    @ctos_follows_before[changed_proto] = []
  @ctos_follows_before[changed_proto].push({callback: callback, synchronous: synchronous})
  return
@ctos_follow_after = (proto, synchronous, callback)->
  changed_proto = @replace_proto(proto, "CTOS")
  if !@ctos_follows_after[changed_proto]
    @ctos_follows_after[changed_proto] = []
  @ctos_follows_after[changed_proto].push({callback: callback, synchronous: synchronous})
  return

#消息发送函数,至少要把俩合起来....
@stoc_send = (socket, proto, info)->
  if socket.closed
    return
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

  header = Buffer.allocUnsafe(3)
  header.writeUInt16LE buffer.length + 1, 0
  header.writeUInt8 proto, 2
  socket.write header
  socket.write buffer if buffer.length
  return

@ctos_send = (socket, proto, info)->
  if socket.closed
    return
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

  header = Buffer.allocUnsafe(3)
  header.writeUInt16LE buffer.length + 1, 0
  header.writeUInt8 proto, 2
  socket.write header
  socket.write buffer if buffer.length
  return

#util
@stoc_send_chat = (client, msg, player = 8)->
  if !client
    console.log "err stoc_send_chat"
    return
  for line in _.lines(msg)
    if player>=10
      line="[Server]: "+line
    for o,r of @i18ns[client.lang]
      re=new RegExp("\\$\\{"+o+"\\}",'g')
      line=line.replace(re,r)
    @stoc_send client, 'CHAT', {
      player: player
      msg: line
    }
  return

@stoc_send_chat_to_room = (room, msg, player = 8)->
  if !room
    console.log "err stoc_send_chat_to_room"
    return
  for client in room.players
    @stoc_send_chat(client, msg, player) if client
  for client in room.watchers
    @stoc_send_chat(client, msg, player) if client
  return

@stoc_send_hint_card_to_room = (room, card)->
  if !room
    console.log "err stoc_send_hint_card_to_room"
    return
  for client in room.players
    @stoc_send client, 'GAME_MSG', {
      curmsg: 2,
      type: 10,
      player: 0,
      data: card
    } if client
  for client in room.watchers
    @stoc_send client, 'GAME_MSG', {
      curmsg: 2,
      type: 10,
      player: 0,
      data: card
    } if client
  return

@stoc_die = (client, msg)->
  @stoc_send_chat(client, msg, @constants.COLORS.RED)
  @stoc_send client, 'ERROR_MSG', {
    msg: 1
    code: 9
  } if client
  if client
    client.system_kicked = true
    client.destroy()
  return
