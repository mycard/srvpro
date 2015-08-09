_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());
spawn = require('child_process').spawn
ygopro = require './ygopro.js'
bunyan = require 'bunyan'
settings = require './config.json'
log = bunyan.createLogger name: "mycard-room"

if settings.modules.database
  mongoose = require 'mongoose'
  mongoose.connect(settings.modules.database);
  User = require './user.js'
  Deck = require './deck.js'
  Match = require './match.js'

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
    @watcher_stanzas = []
    @watchers = []
    @ws_watchers = []
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
      log.info 'room-exit', this.name, this.port, code
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

  delete: ->
    #积分
    return if @deleted
    @save_match() if _.startsWith(@name, 'M#') and @started and settings.modules.database

    index = _.indexOf(Room.all, this)
    Room.all.splice(index, 1) unless index == -1
    @deleted = true


  toString: ->
    "room: #{@name} #{@port} #{@alive ? 'alive' : 'not-alive'} #{@dueling ? 'dueling' : 'not-dueling'} [#{("client #{typeof player.client} server #{typeof player.server} #{player.name} #{player.pos}. " for player in @players)}] #{JSON.stringify @pos_name}"

  ensure_finish: ()->
    #判断match是否正常结束
    player_wins = [0,0,0]
    for duel in @duels
      player_wins[duel.winner] += 1
    normal_ended = player_wins[0] >= 2 or player_wins[1] >= 2

    if !normal_ended
      if @disconnector == 'server'
        return false
      if @duels.length == 0 or _.last(@duels).reason != 4
        @duels.push {winner: 1-@disconnector.pos, reason: 4}
    true

  save_match: ()->
    return unless @ensure_finish()
    match_winner = _.last(@duels).winner

    return unless @dueling_players[0] and @dueling_players[1] #a WTF fix
    User.findOne { name: @dueling_players[0].name }, (err, player0)=>
      if(err)
        log.error "error when find user", @dueling_players[0].name, err
      else if(!player0)
        log.error "can't find user ", @dueling_players[0].name
      else
        User.findOne { name: @dueling_players[1].name }, (err, player1)=>
          if(err)
            log.error "error when find user", @dueling_players[1].name, err
          else if(!player1)
            log.error "can't find user ", @dueling_players[1].name
          else
            #---------------------------------------------------------------------------
            #卡组
            log.info user: player0._id, card_usages: @dueling_players[0].deck
            Deck.findOne user: player0._id, card_usages: @dueling_players[0].deck, (err, deck0)=>
              if(err)
                log.error "error when find deck"
              else if(!deck0)
                deck0 = new Deck({name: 'match', user: player0._id, card_usages: @dueling_players[0].deck, used_count: 1, last_used_at: Date.now()})
                deck0.save()
              else
                deck0.used_count++
                deck0.last_used_at = Date.now()
                deck0.save()
              log.info deck0
              log.info @dueling_players[0].deck, @dueling_players[1].deck, @dueling_players
              Deck.findOne user: player1._id, card_usages: @dueling_players[1].deck, (err, deck1)=>
                if(err)
                  log.error "error when find deck"
                else if(!deck1)
                  deck1 = new Deck({name: 'match', user: player1._id, card_usages: @dueling_players[1].deck, used_count: 1, last_used_at: Date.now()})
                  deck1.save()
                else
                  deck1.used_count++
                  deck1.last_used_at = Date.now()
                  deck1.save()
                log.info deck1

                Match.create
                  players: [{user: player0._id, deck: deck0._id}, {user: player1._id, deck: deck1._id}]
                  duels: @duels
                  winner: if match_winner == 0 then player0._id else player1._id,
                  ygopro_version: settings.version
                ,(err, match)->
                    log.info err, match

            #积分
            if match_winner == 0
              winner = player0
              loser = player1
            else
              winner = player1
              loser = player0

            log.info('before_settle_result',winner.name, winner.points,loser.name, loser.points)
            winner.points += 5
            if _.last(@duels).reason == 4
              loser.points -= 8
            else
              loser.points -= 3
            log.info('duel_settle_result',winner.name, winner.points,loser.name, loser.points)
            winner.save()
            loser.save()

  connect: (client)->
    @players.push client

    if @established
      client.server.connect @port, '127.0.0.1', ->
        client.server.write buffer for buffer in client.pre_establish_buffers
        client.established = true

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