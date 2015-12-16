_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports());
spawn = require('child_process').spawn
spawnSync = require('child_process').spawnSync
ygopro = require './ygopro.js'
bunyan = require 'bunyan'
moment = require 'moment'
moment.locale('zh-cn', { relativeTime : {
            future : '%s内',
            past : '%s前',
            s : '%d秒',
            m : '1分钟',
            mm : '%d分钟',
            h : '1小时',
            hh : '%d小时',
            d : '1天',
            dd : '%d天',
            M : '1个月',
            MM : '%d个月',
            y : '1年',
            yy : '%d年'
  }})
settings = require './config.json'

log = bunyan.createLogger name: "mycard-room"

#获取可用内存
get_memory_usage = ()->
  prc_free = spawnSync("free", [])
  if (prc_free.stdout)
    lines = prc_free.stdout.toString().split(/\n/g)
    line = lines[1].split(/\s+/)
    total = parseInt(line[1], 10)
    free = parseInt(line[3], 10)
    buffers = parseInt(line[5], 10)
    cached = parseInt(line[6], 10)
    actualFree = free + buffers + cached
    percentUsed = parseFloat(((1 - (actualFree / total)) * 100).toFixed(2))
  else
    percentUsed = 0
  return percentUsed

class Room
  #name
  #port
  #players: [client]
  #process
  #established
  #alive

  @all = []
  @players_oppentlist = {}
  @players_banned = []

  @ban_player: (name, ip, reason)->
    log.info("banned", name, ip, reason)
    bannedplayer = _.find Room.players_banned, (bannedplayer)->
      ip==bannedplayer.ip
    if bannedplayer
      bannedplayer.time=moment(bannedplayer.time).add(Math.pow(2,bannedplayer.count)*30,'s')
      bannedplayer.count=bannedplayer.count+1
      bannedplayer.reason=reason
    else 
      Room.players_banned.push {"ip": ip, "time": moment().add(30, 's'), "count": 1, "reason": reason}

  @find_or_create_by_name: (name, player_ip)->
    if settings.modules.enable_random_duel and (name == '' or name.toUpperCase() == 'S' or name.toUpperCase() == 'M' or name.toUpperCase() == 'T')
      return @find_or_create_random(name.toUpperCase(), player_ip)
    if room = @find_by_name(name)
      return room
    else if get_memory_usage()>=90
      return null
    else 
      return new Room(name)
  
  @find_or_create_random: (type, player_ip)->
    bannedplayer = _.find Room.players_banned, (bannedplayer)->
      return player_ip==bannedplayer.ip
    if bannedplayer and moment()<bannedplayer.time
      return {"error":"因为您在近期游戏中#{bannedplayer.reason}，您已被禁止使用随机对战功能，将在#{moment(bannedplayer.time).fromNow(true)}后解封"}
    max_player = if type == 'T' then 4 else 2
    result = _.find @all, (room)->
      room.random_type != '' and !room.started and ((type == '' and room.random_type != 'T') or room.random_type == type) and room.get_playing_player().length < max_player and room.get_host().remoteAddress != Room.players_oppentlist[player_ip]
    if result
      result.welcome = '对手已经在等你了，开始决斗吧！'
      #log.info 'found room', player_name
    else
      type = if type then type else 'S'
      name = type + ',RANDOM#' + Math.floor(Math.random()*100000)
      result = new Room(name)
      result.random_type = type
      result.welcome = '已建立随机对战房间，正在等待对手！'
      #log.info 'create room', player_name, name
    return result

  @find_by_name: (name)->
    result = _.find @all, (room)->
      room.name == name
    #log.info 'find_by_name', name, result
    return result

  @find_by_port: (port)->
    _.find @all, (room)->
      room.port == port

  @validate: (name)->
    client_name_and_pass = name.split('$',2)
    client_name = client_name_and_pass[0]
    client_pass = client_name_and_pass[1]
    return true if !client_pass
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
    @started = false
    @established = false
    @watcher_buffers = []
    @watchers = []
    @random_type = ''
    @welcome = ''
    Room.all.push this

    @hostinfo =
      lflist: 0
      rule: if settings.modules.enable_TCG_as_default then 2 else 0
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
    
    else if (((param = name.match /(.+)#/) != null) and ( (param[1].length<=2 and param[1].match(/(S|N|M|T)(0|1|2|T|A)/i)) or (param[1].match(/^(S|N|M|T)(0|1|2|O|T|A)(0|1|O|T)/i)) ) )
      rule=param[1].toUpperCase()
      #log.info "C", rule
      
      switch rule.charAt(0)
        when "M","1"
          @hostinfo.mode = 1
        when "T","2"
          @hostinfo.mode = 2
          @hostinfo.start_lp = 16000
        else
          @hostinfo.mode = 0
     
      switch rule.charAt(1)
        when "0","O"
          @hostinfo.rule = 0
        when "1","T"
          @hostinfo.rule = 1
        else
          @hostinfo.rule = 2
      
      switch rule.charAt(2)
        when "1","T"
          @hostinfo.lflist = settings.modules.TCG_banlist_id
        else
          @hostinfo.lflist = 0
      
      if ((param = parseInt(rule.charAt(3).match(/\d/))) >= 0)
        @hostinfo.time_limit=param*60
      
      switch rule.charAt(4)
        when "T","1"
          @hostinfo.enable_priority = true
        else
          @hostinfo.enable_priority = false
    
      switch rule.charAt(5)
        when "T","1"
          @hostinfo.no_check_deck = true
        else
          @hostinfo.no_check_deck = false
    
      switch rule.charAt(6)
        when "T","1"
          @hostinfo.no_shuffle_deck = true
        else
          @hostinfo.no_shuffle_deck = false
    
      if ((param = parseInt(rule.charAt(7).match(/\d/))) > 0)
        @hostinfo.start_lp=param*4000
    
      if ((param = parseInt(rule.charAt(8).match(/\d/))) > 0)
        @hostinfo.start_hand=param
    
      if ((param = parseInt(rule.charAt(9).match(/\d/))) >= 0)
        @hostinfo.draw_count=param
    
    else if ((param = name.match /(.+)#/) != null)
      rule=param[1].toUpperCase()
      #log.info "233", rule
      
      if (rule.match /(^|，|,)(M|MATCH)(，|,|$)/)
        @hostinfo.mode = 1
      
      if (rule.match /(^|，|,)(T|TAG)(，|,|$)/)
        @hostinfo.mode = 2
        @hostinfo.start_lp = 16000
      
      if (rule.match /(^|，|,)(TCGONLY|TO)(，|,|$)/)
        @hostinfo.rule = 1
        @hostinfo.lflist = settings.modules.TCG_banlist_id
      
      if (rule.match /(^|，|,)(OT|TCG)(，|,|$)/)
        @hostinfo.rule = 2
      
      if (param = rule.match /(^|，|,)LP(\d+)(，|,|$)/)
        start_lp = parseInt(param[2])
        if (start_lp <= 0) then start_lp = 1
        if (start_lp >= 99999) then start_lp = 99999
        @hostinfo.start_lp = start_lp
      
      if (param = rule.match /(^|，|,)(TIME|TM|TI)(\d+)(，|,|$)/)
        time_limit = parseInt(param[3])
        if (time_limit < 0) then time_limit = 180
        if (time_limit >= 1 and time_limit <= 60) then time_limit = time_limit*60
        if (time_limit >= 999) then time_limit = 999
        @hostinfo.time_limit = time_limit
      
      if (param = rule.match /(^|，|,)(START|ST)(\d+)(，|,|$)/)
        start_hand = parseInt(param[3])
        if (start_hand <= 0) then start_hand = 1
        if (start_hand >= 40) then start_hand = 40
        @hostinfo.start_hand = start_hand
      
      if (param = rule.match /(^|，|,)(DRAW|DR)(\d+)(，|,|$)/)
        draw_count = parseInt(param[3])
        if (draw_count >= 35) then draw_count = 35
        @hostinfo.draw_count = draw_count
      
      if (param = rule.match /(^|，|,)(LFLIST|LF)(\d+)(，|,|$)/)
        lflist = parseInt(param[3])-1
        @hostinfo.lflist = lflist
      
      if (rule.match /(^|，|,)(NOLFLIST|NF)(，|,|$)/)
        @hostinfo.lflist = -1
      
      if (rule.match /(^|，|,)(NOUNIQUE|NU)(，|,|$)/)
        @hostinfo.rule = 3
      
      if (rule.match /(^|，|,)(NOCHECK|NC)(，|,|$)/)
        @hostinfo.no_check_deck = true
      
      if (rule.match /(^|，|,)(NOSHUFFLE|NS)(，|,|$)/)
        @hostinfo.no_shuffle_deck = true
      
      if (rule.match /(^|，|,)(IGPRIORITY|PR)(，|,|$)/)
        @hostinfo.enable_priority = true

    param = [0, @hostinfo.lflist, @hostinfo.rule, @hostinfo.mode, (if @hostinfo.enable_priority then 'T' else 'F'), (if @hostinfo.no_check_deck then 'T' else 'F'), (if @hostinfo.no_shuffle_deck then 'T' else 'F'), @hostinfo.start_lp, @hostinfo.start_hand, @hostinfo.draw_count, @hostinfo.time_limit]

    try
      @process = spawn './ygopro', param, {cwd: settings.ygopro_path}
      @process.on 'exit', (code)=>
        @disconnector = 'server' unless @disconnector
        this.delete()
        return
      @process.stdout.setEncoding('utf8')
      @process.stdout.once 'data', (data)=>
        @established = true
        @port = parseInt data
        _.each @players, (player)=>
          player.server.connect @port, '127.0.0.1',=>
            player.server.write buffer for buffer in player.pre_establish_buffers
            player.established = true
            player.pre_establish_buffers = []
            return
          return
        return
    catch
      @error = "建立房间失败，请重试"
  delete: ->
    #积分
    return if @deleted
    #log.info 'room-delete', this.name, Room.all.length
    @watcher_buffers = []
    @players = []
    @watcher.end() if @watcher
    @deleted = true
    index = _.indexOf(Room.all, this)
    #Room.all[index] = null unless index == -1
    Room.all.splice(index, 1) unless index == -1
    return
    
  get_playing_player: ->
    playing_player=[]
    _.each @players, (player)=>
      if player.pos < 4 then playing_player.push player
      return
    return playing_player

  get_host: ->
    host_player=null
    _.each @players, (player)=>
      if player.is_host then host_player=player
      return
    return host_player

  connect: (client)->
    @players.push client
    client.ip=client.remoteAddress
    if @random_type
      host_player=@get_host()
      if host_player && (host_player != client)
        #进来时已经有人在等待了，互相记录为匹配过
        Room.players_oppentlist[host_player.remoteAddress] = client.remoteAddress
        Room.players_oppentlist[client.remoteAddress] = host_player.remoteAddress
      else
        #第一个玩家刚进来，还没就位
        Room.players_oppentlist[client.remoteAddress] = null

    if @established
      client.server.connect @port, '127.0.0.1', ->
        client.server.write buffer for buffer in client.pre_establish_buffers
        client.established = true
        client.pre_establish_buffers = []
        return
    return

  disconnect: (client, error)->
    if client.is_post_watcher
      ygopro.stoc_send_chat_to_room this, "#{client.name} #{'退出了观战'}#{if error then ": #{error}" else ''}"
      index = _.indexOf(@watchers, client)
      @watchers.splice(index, 1) unless index == -1
      #client.room = null
    else
      index = _.indexOf(@players, client)
      @players.splice(index, 1) unless index == -1
      #log.info(@started,@disconnector,client.room.random_type)
      if @started and @disconnector!='server' and client.room.random_type
        Room.ban_player(client.name, client.ip, "强退")
      if @players.length
        ygopro.stoc_send_chat_to_room this, "#{client.name} #{'离开了游戏'}#{if error then ": #{error}" else ''}"
        #client.room = null
      else
        @process.kill()
        #client.room = null
        this.delete()
    return

module.exports = Room