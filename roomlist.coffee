WebSocketServer = require('ws').Server
url = require('url')
settings = global.settings

server = null

room_data = (room)->
  id: room.name,
  title: room.title,
  user: {username: room.username}
  users: ({username: client.name, position: client.pos} for client in room.players),
  options: room.hostinfo,
  arena: settings.modules.arena_mode.enabled && room.arena && settings.modules.arena_mode.mode

init = (http_server, ROOM_all)->
  server = new WebSocketServer
    server: http_server

  server.on 'connection', (connection) ->
    connection.filter = url.parse(connection.upgradeReq.url, true).query.filter || 'waiting'
    connection.send JSON.stringify
      event: 'init'
      data: room_data(room) for room in ROOM_all when room and room.established and !room.private and (room.started == (connection.filter == 'started'))

create = (room)->
  broadcast('create', room_data(room), 'waiting')

update = (room)->
  broadcast('update', room_data(room), 'waiting')

start = (room)->
  broadcast('delete', room_data(room), 'waiting')
  broadcast('create', room_data(room), 'started')

_delete = (room)->
  if(room.started)
    broadcast('delete', room.name, 'started')
  else
    broadcast('delete', room.name, 'waiting')

broadcast = (event, data, filter)->
  return if !server
  message = JSON.stringify
    event: event
    data: data
  for connection in server.clients when connection.filter == filter
    try
      connection.send message

module.exports =
  init: init
  create: create
  update: update
  start: start
  delete: _delete

