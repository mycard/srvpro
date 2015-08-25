_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());
spawn = require('child_process').spawn
ygopro = require './ygopro.js'
bunyan = require 'bunyan'
settings = require './config.json'

log = bunyan.createLogger name: "mycard-room"

class Room
  #name
  #port
  #players: [client]
  #process
  #established
  #alive

  @all = []

  @find_or_create_by_name: (name)->
    @find_by_name(name) ? new Room(name)

  @find_by_name: (name)->
    result = _.find @all, (room)->
      room.name == name
    #log.info 'find_by_name', name, result
    result

  @find_by_port: (port)->
    _.find @all, (room)->
      room.port == port

  @validate: (name)->
    client_name_and_pass = name.split('$',2)
    client_name = client_name_and_pass[0]
    client_pass = client_name_and_pass[1]
    !_.find Room.all, (room)->
      room_name_and_pass = room.name.split('$',2)
      room_name = room_name_and_pass[0]
      room_pass = room_name_and_pass[1]
      client_name == room_name and client_pass != room_pass

  constructor: (name) ->
    @name = name
    @alive = true
    @players = []
    @status = 'starting'
    @established = false
    @watcher_buffers = []
    @watchers = []
    Room.all.push this

    @hostinfo =
      lflist: 0
      rule: 0
      mode: 0
      enable_priority: false
      no_check_deck: false
      no_shuffle_deck: false
      start_lp: 8000
      start_hand: 5
      draw_count: 1
      time_limit: 180

    if name[0...2] == 'M#'
      @hostinfo.mode = 1
    else if name[0...2] == 'T#'
      @hostinfo.mode = 2
      @hostinfo.start_lp = 16000
    else if (param = name.match /^(\d)(\d)(T|F)(T|F)(T|F)(\d+),(\d+),(\d+)/i)
      @hostinfo.rule = parseInt(param[1])
      @hostinfo.mode = parseInt(param[2])
      @hostinfo.enable_priority = param[3] == 'T'
      @hostinfo.no_check_deck = param[4] == 'T'
      @hostinfo.no_shuffle_deck = param[5] == 'T'
      @hostinfo.start_lp = parseInt(param[6])
      @hostinfo.start_hand = parseInt(param[7])
      @hostinfo.draw_count = parseInt(param[8])

    param = [0, @hostinfo.lflist, @hostinfo.rule, @hostinfo.mode, (if @hostinfo.enable_priority then 'T' else 'F'), (if @hostinfo.no_check_deck then 'T' else 'F'), (if @hostinfo.no_shuffle_deck then 'T' else 'F'), @hostinfo.start_lp, @hostinfo.start_hand, @hostinfo.draw_count]

    @process = spawn './ygopro', param, cwd: 'ygocore'
    @process.on 'exit', (code)=>
      #log.info 'room-exit', this.name, this.port, code
      @disconnector = 'server' unless @disconnector
      this.delete()
    @process.stdout.setEncoding('utf8')
    @process.stdout.once 'data', (data)=>
      @established = true
      @port = parseInt data
      _.each @players, (player)=>
        player.server.connect @port, '127.0.0.1',=>
          player.server.write buffer for buffer in player.pre_establish_buffers
          player.established = true
          player.pre_establish_buffers = null

  delete: ->
    #积分
    return if @deleted
    #log.info 'room-delete', this.name, Room.all.length
    index = _.indexOf(Room.all, this)
    #Room.all[index] = null unless index == -1
    Room.all.splice(index, 1) unless index == -1
    @deleted = true

  connect: (client)->
    @players.push client

    if @established
      client.server.connect @port, '127.0.0.1', ->
        client.server.write buffer for buffer in client.pre_establish_buffers
        client.established = true
        client.pre_establish_buffers = null

  disconnect: (client, error)->
    if client.is_post_watcher
      ygopro.stoc_send_chat_to_room this, "#{client.name} #{'退出了观战'}#{if error then ": #{error}" else ''}"
      index = _.indexOf(@watchers, client)
      @watchers.splice(index, 1) unless index == -1
    else
      index = _.indexOf(@players, client)
      @players.splice(index, 1) unless index == -1
      if @players.length
        ygopro.stoc_send_chat_to_room this, "#{client.name} #{'离开了游戏'}#{if error then ": #{error}" else ''}"
      else
        @process.kill()
        this.delete()

module.exports = Room