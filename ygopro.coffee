_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports())

Struct = require('./struct.js').Struct
loadJSON = require('load-json-file').sync

@i18ns = loadJSON './data/i18n.json'

YGOProMessageHelper = require("./YGOProMessages.js") # 为 SRVPro2 准备的库，这里拿这个库只用来测试，SRVPro1 对异步支持不是特别完善，因此不会有很多异步优化
@helper = new YGOProMessageHelper()

@structs = @helper.structs
@structs_declaration = @helper.structs_declaration
@typedefs = @helper.typedefs
@proto_structs = @helper.proto_structs
@constants = @helper.constants

translateHandler = (handler) ->
  return (buffer, info, datas, params)->
    await return handler(buffer, info, params.client, params.server, datas)

@stoc_follow = (proto, synchronous, callback)->
  @helper.addHandler("STOC_#{proto}", translateHandler(callback), synchronous, 1)
  return
@stoc_follow_before = (proto, synchronous, callback)->
  @helper.addHandler("STOC_#{proto}", translateHandler(callback), synchronous, 0)
  return
@stoc_follow_after = (proto, synchronous, callback)->
  @helper.addHandler("STOC_#{proto}", translateHandler(callback), synchronous, 2)
  return
@ctos_follow = (proto, synchronous, callback)->
  @helper.addHandler("CTOS_#{proto}", translateHandler(callback), synchronous, 1)
  return
@ctos_follow_before = (proto, synchronous, callback)->
  @helper.addHandler("CTOS_#{proto}", translateHandler(callback), synchronous, 0)
  return
@ctos_follow_after = (proto, synchronous, callback)->
  @helper.addHandler("CTOS_#{proto}", translateHandler(callback), synchronous, 2)
  return

#消息发送函数,至少要把俩合起来....
@stoc_send = (socket, proto, info)->
  return @helper.sendMessage(socket, "STOC_#{proto}", info)

@ctos_send = (socket, proto, info)->
  return @helper.sendMessage(socket, "CTOS_#{proto}", info)

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
