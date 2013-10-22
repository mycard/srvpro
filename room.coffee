_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());
spawn = require('child_process').spawn
ygopro = require './ygopro.js'
class Room
  #name
  #port
  #players: [client]
  #process
  #established
  #alive

  @all = []

  @find_or_create_by_name: (name)->
    result = @find_by_name(name) ? new Room(name)

  @find_by_name: (name)->
    _.find @all, (room)->
      room.name == name

  @find_by_port: (port)->
    _.find @all, (room)->
      room.port == port

  constructor: (name) ->
    @name = name
    @alive = true
    @players = []
    @status = 'starting'
    Room.all.push this

    if name[0...2] == 'M#'
      param = [0, 0, 0, 1, 'F', 'F', 'F', 8000, 5, 1]
    else if name[0...2] == 'T#'
      param = [0, 0, 0, 2, 'F', 'F', 'F', 8000, 5, 1]
    else if (param = name.match /^(\d)(\d)(T|F)(T|F)(T|F)(\d+),(\d+),(\d+)/i)
      param.shift()
      param.unshift(0, 0)
    else
      param = [0, 0, 0, 0, 'F', 'F', 'F', 8000, 5, 1]

    @process = spawn './ygopro', param, cwd: 'ygocore'
    @process.on 'exit', (code)=>
      console.log "room process #{@port} exited with code #{code}"
      this.delete()
    @process.stdout.setEncoding('utf8')
    @process.stdout.once 'data', (data)=>
      @established = true
      @port = parseInt data
      #setTimeout =>
      _.each @players, (player)=>
        player.server.connect @port, '127.0.0.1',=>
          player.server.write buffer for buffer in player.pre_establish_buffers
          player.established = true

  delete: (room)->
    Room.all.splice(_.indexOf(Room.all, room), 1)


  toString: ->
    "room: #{@name} #{@port} #{@alive ? 'alive' : 'not-alive'} #{@dueling ? 'dueling' : 'not-dueling'} [#{("client #{typeof player.client} server #{typeof player.server} #{player.name} #{player.pos}. " for player in @players)}] #{JSON.stringify @pos_name}"

  connect: (client)->
    @players.push client

    if @established
      client.server.connect @port, '127.0.0.1', ->
        client.server.write buffer for buffer in client.pre_establish_buffers
        client.established = true

  disconnect: (client, error)->
    @players = _.reject @players, (player)->
      player is client

    for player in @players
      ygopro.stoc_send_chat(player, "#{client.name} 离开了游戏#{if error then ": #{error}" else ''}")

module.exports = Room