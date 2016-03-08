WebSocketServer = require('ws').Server;


server = null

room_data = (room)->
  id: room.name,
  title: room.title,
  user: {username: room.username}
  users: ({username: client.name, position: client.pos} for client in room.players),
  options: room.hostinfo

init = (http_server, Room)->
  server = new WebSocketServer
    server: http_server

  server.on 'connection', (connection) ->
    connection.send JSON.stringify
      event: 'init'
      data: room_data(room) for room in Room.all when room.established and !room.private and !room.started

create = (room)->
  broadcast('create', room_data(room))

update = (room)->
  broadcast('update', room_data(room))

_delete = (room_id)->
  broadcast('delete', room_id)

broadcast = (event, data)->
  return if !server
  message = JSON.stringify
    event: event
    data: data
  for connection in server.clients
    try
      connection.send message

module.exports =
  init: init
  create: create
  update: update
  delete: _delete