# 标准库
net = require 'net'
http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'
os = require 'os'
crypto = require 'crypto'
execFile = require('child_process').execFile
spawn = require('child_process').spawn
spawnSync = require('child_process').spawnSync

# 三方库
_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports())

request = require 'request'

bunyan = require 'bunyan'
log = bunyan.createLogger name: "mycard"

moment = require 'moment'
moment.locale('zh-cn', {
  relativeTime: {
    future: '%s内',
    past: '%s前',
    s: '%d秒',
    m: '1分钟',
    mm: '%d分钟',
    h: '1小时',
    hh: '%d小时',
    d: '1天',
    dd: '%d天',
    M: '1个月',
    MM: '%d个月',
    y: '1年',
    yy: '%d年'
  }
})

#heapdump = require 'heapdump'

# 配置
# use nconf to save user config.user.json .
# config.json shouldn't be changed
nconf = require 'nconf'
nconf.file('./config.user.json')
defaultconfig = require('./config.json')
nconf.defaults(defaultconfig)
settings = global.settings = nconf.get()
nconf.myset = (settings, path, val) ->
  # path should be like "modules:welcome"
  nconf.set(path, val)
  nconf.save()
  log.info("setting changed", path, val) if _.isString(val)
  path=path.split(':')
  if path.length == 0
    settings[path[0]]=val
  else
    target=settings
    while path.length > 1
      key=path.shift()
      target=target[key]
    key = path.shift()
    target[key] = val
  return

# ban a user manually and permanently
ban_user = (name) ->
  settings.ban.banned_user.push(name)
  nconf.myset(settings, "ban:banned_user", settings.ban.banned_user)
  bad_ip=0
  for room in ROOM_all when room and room.established
    for player in room.players
      if player and (player.name == name or player.ip == bad_ip)
        bad_ip = player.ip
        ROOM_bad_ip.push(player.ip)
        settings.ban.banned_ip.push(player.ip)
        ygopro.stoc_send_chat_to_room(room, "#{player.name} 被系统请出了房间", ygopro.constants.COLORS.RED)
        player.destroy()
        continue
  return

settings.version = parseInt(fs.readFileSync('ygopro/gframe/game.cpp', 'utf8').match(/PRO_VERSION = ([x\dABCDEF]+)/)[1], '16')
# load the lflist of current date
settings.lflist = (for list in fs.readFileSync('ygopro/lflist.conf', 'utf8').match(/!.*/g)
  date=list.match(/!([\d\.]+)/)
  continue unless date
  {date: moment(list.match(/!([\d\.]+)/)[1], 'YYYY.MM.DD').utcOffset("-08:00"), tcg: list.indexOf('TCG') != -1})

if settings.modules.enable_cloud_replay
  redis = require 'redis'
  zlib = require 'zlib'
  redisdb = redis.createClient host: "127.0.0.1", port: settings.modules.redis_port
  redisdb.on 'error', (err)->
    log.warn err
    return

if settings.modules.enable_windbot
  settings.modules.windbots = require('./windbot/bots.json').windbots

# 组件
ygopro = require './ygopro.js'
roomlist = require './roomlist.js' if settings.modules.enable_websocket_roomlist

# cache users of mycard login
users_cache = {}

# 获取可用内存
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

# 定时清理关闭的连接
# the server write data directly to the socket object
# so this is a dumb way to clean data
Graveyard = []

tribute = (socket) ->
  setTimeout ((socket)-> Graveyard.push(socket);return)(socket), 3000
  return

setInterval ()->
  for fuck,i in Graveyard
    Graveyard[i].destroy() if Graveyard[i]
    for you,j in Graveyard[i]
      Graveyard[i][j] = null
    Graveyard[i] = null
  Graveyard = []
  #global.gc()
  return
, 3000

Cloud_replay_ids = []

ROOM_all = []
ROOM_players_oppentlist = {}
ROOM_players_banned = []
ROOM_connected_ip = {}
ROOM_bad_ip = {}

# automatically ban user to use random duel
ROOM_ban_player = (name, ip, reason, countadd = 1)->
  bannedplayer = _.find ROOM_players_banned, (bannedplayer)->
    ip == bannedplayer.ip
  if bannedplayer
    bannedplayer.count = bannedplayer.count + countadd
    bantime = if bannedplayer.count > 3 then Math.pow(2, bannedplayer.count - 3) * 2 else 0
    bannedplayer.time = if moment() < bannedplayer.time then moment(bannedplayer.time).add(bantime, 'm') else moment().add(bantime, 'm')
    bannedplayer.reasons.push(reason) if not _.find bannedplayer.reasons, (bannedreason)->
      bannedreason == reason
    bannedplayer.need_tip = true
  else
    bannedplayer = {"ip": ip, "time": moment(), "count": countadd, "reasons": [reason], "need_tip": true}
    ROOM_players_banned.push(bannedplayer)
  #log.info("banned", name, ip, reason, bannedplayer.count)
  return

ROOM_find_or_create_by_name = (name, player_ip)->
  uname=name.toUpperCase()
  if settings.modules.enable_windbot and (uname[0...2] == 'AI' or (!settings.modules.enable_random_duel and uname == ''))
    return ROOM_find_or_create_ai(name)
  if settings.modules.enable_random_duel and (uname == '' or uname == 'S' or uname == 'M' or uname == 'T')
    return ROOM_find_or_create_random(uname, player_ip)
  if room = ROOM_find_by_name(name)
    return room
  else if get_memory_usage() >= 90
    return null
  else
    return new Room(name)

ROOM_find_or_create_random = (type, player_ip)->
  bannedplayer = _.find ROOM_players_banned, (bannedplayer)->
    return player_ip == bannedplayer.ip
  if bannedplayer
    if bannedplayer.count > 6 and moment() < bannedplayer.time
      return {"error": "因为您近期在游戏中多次#{bannedplayer.reasons.join('、')}，您已被禁止使用随机对战功能，将在#{moment(bannedplayer.time).fromNow(true)}后解封"}
    if bannedplayer.count > 3 and moment() < bannedplayer.time and bannedplayer.need_tip
      bannedplayer.need_tip = false
      return {"error": "因为您近期在游戏中#{bannedplayer.reasons.join('、')}，在#{moment(bannedplayer.time).fromNow(true)}内您随机对战时只能遇到其他违规玩家"}
    else if bannedplayer.need_tip
      bannedplayer.need_tip = false
      return {"error": "系统检测到您近期在游戏中#{bannedplayer.reasons.join('、')}，若您违规超过3次，将受到惩罚"}
    else if bannedplayer.count > 2
      bannedplayer.need_tip = true
  max_player = if type == 'T' then 4 else 2
  playerbanned = (bannedplayer and bannedplayer.count > 3 and moment() < bannedplayer.time)
  result = _.find ROOM_all, (room)->
    return room and room.random_type != '' and !room.started and
    ((type == '' and room.random_type != 'T') or room.random_type == type) and
    room.get_playing_player().length < max_player and
    (room.get_host() == null or room.get_host().ip != ROOM_players_oppentlist[player_ip]) and
    (playerbanned == room.deprecated)
  if result
    result.welcome = '对手已经在等你了，开始决斗吧！'
    #log.info 'found room', player_name
  else if get_memory_usage() < 90
    type = if type then type else 'S'
    name = type + ',RANDOM#' + Math.floor(Math.random() * 100000)
    result = new Room(name)
    result.random_type = type
    result.max_player = max_player
    result.welcome = '已建立随机对战房间，正在等待对手！'
    result.deprecated = playerbanned
    #log.info 'create room', player_name, name
  else
    return null
  if result.random_type=='M' then result.welcome = result.welcome + '\n您进入了比赛模式的房间，我们推荐使用竞技卡组！'
  return result

ROOM_find_or_create_ai = (name)->
  if name == ''
    name = 'AI'
  if name[0...3] == 'AI_'
    name = 'AI#' + name.slice(3)
  namea = name.split('#')
  if room = ROOM_find_by_name(name)
    return room
  else if name == 'AI'
    windbot = _.sample settings.modules.windbots
    name = 'AI#' + Math.floor(Math.random() * 100000)
  else if namea.length>1
    ainame = namea[namea.length-1]
    windbot = _.sample _.filter settings.modules.windbots, (w)->
      w.name == ainame or w.deck == ainame
    if !windbot
      return { "error": "未找到该AI角色或卡组" }
    name = name + ',' + Math.floor(Math.random() * 100000)
  else
    windbot = _.sample settings.modules.windbots
    name = name + '#' + Math.floor(Math.random() * 100000)
  if name.replace(/[^\x00-\xff]/g,"00").length>20
    log.info "long ai name", name
    return { "error": "AI房间名过长" }
  result = new Room(name)
  result.windbot = windbot
  return result

ROOM_find_by_name = (name)->
  result = _.find ROOM_all, (room)->
    return room and room.name == name
  #log.info 'find_by_name', name, result
  return result

ROOM_find_by_port = (port)->
  _.find ROOM_all, (room)->
    return room and room.port == port

ROOM_validate = (name)->
  client_name_and_pass = name.split('$', 2)
  client_name = client_name_and_pass[0]
  client_pass = client_name_and_pass[1]
  return true if !client_pass
  !_.find ROOM_all, (room)->
    return false unless room
    room_name_and_pass = room.name.split('$', 2)
    room_name = room_name_and_pass[0]
    room_pass = room_name_and_pass[1]
    client_name == room_name and client_pass != room_pass

class Room
  constructor: (name, @hostinfo) ->
    @name = name
    @alive = true
    @players = []
    @player_datas = []
    @status = 'starting'
    @started = false
    @established = false
    @watcher_buffers = []
    @recorder_buffers = []
    @cloud_replay_id = Math.floor(Math.random()*100000000)
    @watchers = []
    @random_type = ''
    @welcome = ''
    ROOM_all.push this

    @hostinfo ||=
      lflist: _.findIndex settings.lflist, (list)-> !list.tcg and list.date.isBefore()
      rule: if settings.modules.enable_TCG_as_default then 2 else 0
      mode: 0
      enable_priority: false
      no_check_deck: false
      no_shuffle_deck: false
      start_lp: 8000
      start_hand: 5
      draw_count: 1
      time_limit: 180
      replay_mode: if settings.modules.tournament_mode.enabled then 1 else 0

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

    else if (((param = name.match /(.+)#/) != null) and ( (param[1].length <= 2 and param[1].match(/(S|N|M|T)(0|1|2|T|A)/i)) or (param[1].match(/^(S|N|M|T)(0|1|2|O|T|A)(0|1|O|T)/i)) ) )
      rule = param[1].toUpperCase()
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
          @hostinfo.lflist = _.findIndex settings.lflist, (list)-> list.tcg and list.date.isBefore()
        else
          @hostinfo.lflist = _.findIndex settings.lflist, (list)-> !list.tcg and list.date.isBefore()

      if ((param = parseInt(rule.charAt(3).match(/\d/))) >= 0)
        @hostinfo.time_limit = param * 60

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
        @hostinfo.start_lp = param * 4000

      if ((param = parseInt(rule.charAt(8).match(/\d/))) > 0)
        @hostinfo.start_hand = param

      if ((param = parseInt(rule.charAt(9).match(/\d/))) >= 0)
        @hostinfo.draw_count = param

    else if ((param = name.match /(.+)#/) != null)
      rule = param[1].toUpperCase()
      #log.info "233", rule

      if (rule.match /(^|，|,)(M|MATCH)(，|,|$)/)
        @hostinfo.mode = 1

      if (rule.match /(^|，|,)(T|TAG)(，|,|$)/)
        @hostinfo.mode = 2
        @hostinfo.start_lp = 16000

      if (rule.match /(^|，|,)(TCGONLY|TO)(，|,|$)/)
        @hostinfo.rule = 1
        @hostinfo.lflist = _.findIndex settings.lflist, (list)-> list.tcg and list.date.isBefore()

      if (rule.match /(^|，|,)(OCGONLY|OO)(，|,|$)/)
        @hostinfo.rule = 0

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
        if (time_limit >= 1 and time_limit <= 60) then time_limit = time_limit * 60
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
        lflist = parseInt(param[3]) - 1
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

    param = [0, @hostinfo.lflist, @hostinfo.rule, @hostinfo.mode, (if @hostinfo.enable_priority then 'T' else 'F'),
      (if @hostinfo.no_check_deck then 'T' else 'F'), (if @hostinfo.no_shuffle_deck then 'T' else 'F'),
      @hostinfo.start_lp, @hostinfo.start_hand, @hostinfo.draw_count, @hostinfo.time_limit, @hostinfo.replay_mode]

    try
      @process = spawn './ygopro', param, {cwd: settings.ygopro_path}
      @process.on 'exit', (code)=>
        @disconnector = 'server' unless @disconnector
        this.delete()
        return
      @process.stdout.setEncoding('utf8')
      @process.stdout.once 'data', (data)=>
        @established = true
        roomlist.create(this) if !@private and settings.modules.enable_websocket_roomlist
        @port = parseInt data
        _.each @players, (player)=>
          player.server.connect @port, '127.0.0.1', ->
            player.server.write buffer for buffer in player.pre_establish_buffers
            player.established = true
            player.pre_establish_buffers = []
            return
          return
        if @windbot
          setTimeout ()=>
            @add_windbot(@windbot)
          , 200
        return
      @process.stderr.on 'data', (data)=>
        data = "Debug: " + data
        data = data.replace(/\n$/, "")
        log.info "YGOPRO " + data
        ygopro.stoc_send_chat_to_room this, data, ygopro.constants.COLORS.RED
        @has_ygopro_error = true
        return
    catch
      @error = "建立房间失败，请重试"
  delete: ->
    return if @deleted
    #log.info 'room-delete', this.name, ROOM_all.length
    if @player_datas.length and settings.modules.enable_cloud_replay
      replay_id = @cloud_replay_id
      if @has_ygopro_error
        log_rep_id = true
      player_names=@player_datas[0].name + (if @player_datas[2] then "+" + @player_datas[2].name else "") +
                    " VS " +
                   (if @player_datas[1] then @player_datas[1].name else "AI") +
                   (if @player_datas[3] then "+" + @player_datas[3].name else "")
      player_ips=[]
      _.each @player_datas, (player)->
        player_ips.push(player.ip)
        return
      recorder_buffer=Buffer.concat(@recorder_buffers)
      zlib.deflate recorder_buffer, (err, replay_buffer) ->
        replay_buffer=replay_buffer.toString('binary')
        #log.info err, replay_buffer
        date_time=moment().format('YYYY-MM-DD HH:mm:ss')
        #replay_id=Math.floor(Math.random()*100000000)
        redisdb.hmset("replay:"+replay_id,
                      "replay_id", replay_id,
                      "replay_buffer", replay_buffer,
                      "player_names", player_names,
                      "date_time", date_time)
        if !log_rep_id
          redisdb.expire("replay:"+replay_id, 60*60*24)
        recorded_ip=[]
        _.each player_ips, (player_ip)->
          return if _.contains(recorded_ip, player_ip)
          recorded_ip.push player_ip
          redisdb.lpush(player_ip+":replays", replay_id)
          return
        if log_rep_id
          log.info "error replay: R#" + replay_id
        return
    @watcher_buffers = []
    @recorder_buffers = []
    @players = []
    @watcher.destroy() if @watcher
    @deleted = true
    index = _.indexOf(ROOM_all, this)
    ROOM_all[index] = null unless index == -1
    #ROOM_all.splice(index, 1) unless index == -1
    roomlist.delete @name if !@private and !@started and @established and settings.modules.enable_websocket_roomlist
    return

  get_playing_player: ->
    playing_player = []
    _.each @players, (player)->
      if player.pos < 4 then playing_player.push player
      return
    return playing_player

  get_host: ->
    host_player = null
    _.each @players, (player)->
      if player.is_host then host_player = player
      return
    return host_player

  add_windbot: (botdata)->
    @windbot = botdata
    request
      url: "http://127.0.0.1:#{settings.modules.windbot_port}/?name=#{encodeURIComponent(botdata.name)}&deck=#{encodeURIComponent(botdata.deck)}&host=127.0.0.1&port=#{settings.port}&dialog=#{encodeURIComponent(botdata.dialog)}&version=#{settings.version}&password=#{encodeURIComponent(@name)}"
    , (error, response, body)=>
      if error
        log.warn 'windbot add error', error, this.name, response
        ygopro.stoc_send_chat_to_room(this, "添加AI失败，可尝试输入 /ai 重新添加", ygopro.constants.COLORS.RED)
      #else
        #log.info "windbot added"
      return
    return

  connect: (client)->
    @players.push client
    if @random_type
      client.abuse_count = 0
      host_player = @get_host()
      if host_player && (host_player != client)
        # 进来时已经有人在等待了，互相记录为匹配过
        ROOM_players_oppentlist[host_player.ip] = client.ip
        ROOM_players_oppentlist[client.ip] = host_player.ip
      else
        # 第一个玩家刚进来，还没就位
        ROOM_players_oppentlist[client.ip] = null

    if @established
      roomlist.update(this) if !@private and !@started and settings.modules.enable_websocket_roomlist
      client.server.connect @port, '127.0.0.1', ->
        client.server.write buffer for buffer in client.pre_establish_buffers
        client.established = true
        client.pre_establish_buffers = []
        return
    return

  disconnect: (client, error)->
    if client.is_post_watcher
      ygopro.stoc_send_chat_to_room this, "#{client.name} 退出了观战" + if error then ": #{error}" else ''
      index = _.indexOf(@watchers, client)
      @watchers.splice(index, 1) unless index == -1
      #client.room = null
    else
      index = _.indexOf(@players, client)
      @players.splice(index, 1) unless index == -1
      #log.info(@started,@disconnector,@random_type)
      if @started and @disconnector != 'server' and @random_type and (client.pos < 4 or client.is_host)
        ROOM_ban_player(client.name, client.ip, "强退")
      if @players.length and !(@windbot and client.is_host)
        ygopro.stoc_send_chat_to_room this, "#{client.name} 离开了游戏" + if error then ": #{error}" else ''
        roomlist.update(this) if !@private and !@started and settings.modules.enable_websocket_roomlist
        #client.room = null
      else
        @process.kill()
        #client.room = null
        this.delete()
    return


# 网络连接
net.createServer (client) ->
  client.ip = client.remoteAddress
  connect_count = ROOM_connected_ip[client.ip] or 0
  if client.ip != '::ffff:127.0.0.1'
    connect_count++
  ROOM_connected_ip[client.ip] = connect_count
  #log.info "connect", client.ip, ROOM_connected_ip[client.ip]

  # server stand for the connection to ygopro server process
  server = new net.Socket()
  client.server = server

  client.setTimeout(300000) #5分钟

  # 释放处理
  client.on 'close', (had_error) ->
    #log.info "client closed", client.name, had_error
    room=ROOM_all[client.rid]
    connect_count = ROOM_connected_ip[client.ip]
    if connect_count > 0
      connect_count--
    ROOM_connected_ip[client.ip] = connect_count
    #log.info "disconnect", client.ip, ROOM_connected_ip[client.ip]
    tribute(client)
    unless client.closed
      client.closed = true
      room.disconnect(client) if room
    server.destroy()
    return

  client.on 'error', (error)->
    #log.info "client error", client.name, error
    room=ROOM_all[client.rid]
    connect_count = ROOM_connected_ip[client.ip]
    if connect_count > 0
      connect_count--
    ROOM_connected_ip[client.ip] = connect_count
    #log.info "err disconnect", client.ip, ROOM_connected_ip[client.ip]
    tribute(client)
    unless client.closed
      client.closed = error
      room.disconnect(client, error) if room
    server.destroy()
    return

  client.on 'timeout', ()->
    server.destroy()
    return

  server.on 'close', (had_error) ->
    #log.info "server closed", client.name, had_error
    room=ROOM_all[client.rid]
    #log.info "server close", client.ip, ROOM_connected_ip[client.ip]
    tribute(server)
    room.disconnector = 'server' if room
    server.closed = true unless server.closed
    unless client.closed
      ygopro.stoc_send_chat(client, "服务器关闭了连接", ygopro.constants.COLORS.RED)
      client.destroy()
    return

  server.on 'error', (error)->
    #log.info "server error", client.name, error
    room=ROOM_all[client.rid]
    #log.info "server err close", client.ip, ROOM_connected_ip[client.ip]
    tribute(server)
    room.disconnector = 'server' if room
    server.closed = error
    unless client.closed
      ygopro.stoc_send_chat(client, "服务器错误: #{error}", ygopro.constants.COLORS.RED)
      client.destroy()
    return
  
  if ROOM_bad_ip[client.ip] > 5
    log.info 'BAD IP', client.ip
    client.destroy()
    return

  if settings.modules.enable_cloud_replay
    client.open_cloud_replay= (err, replay)->
      if err or !replay
        ygopro.stoc_die(client, "没有找到录像")
        return
      redisdb.expire("replay:"+replay.replay_id, 60*60*48)
      buffer=new Buffer(replay.replay_buffer,'binary')
      zlib.unzip buffer, (err, replay_buffer) ->
        if err
          log.info "cloud replay unzip error: " + err
          ygopro.stoc_send_chat(client, "播放录像出错", ygopro.constants.COLORS.RED)
          client.destroy()
          return
        ygopro.stoc_send_chat(client, "正在观看云录像：R##{replay.replay_id} #{replay.player_names} #{replay.date_time}", ygopro.constants.COLORS.BABYBLUE)
        client.write replay_buffer
        client.end()
        return
      return
    
  # 需要重构
  # 客户端到服务端(ctos)协议分析
  
  client.pre_establish_buffers = new Array()

  client.on 'data', (data) ->
    if client.is_post_watcher
      room=ROOM_all[client.rid]
      room.watcher.write data if room
    else
      ctos_buffer = new Buffer(0)
      ctos_message_length = 0
      ctos_proto = 0
      ctos_buffer = Buffer.concat([ctos_buffer, data], ctos_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

      datas = []

      looplimit = 0

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
            #console.log "CTOS", ygopro.constants.CTOS[ctos_proto]
            cancel = false
            if ygopro.ctos_follows[ctos_proto]
              b = ctos_buffer.slice(3, ctos_message_length - 1 + 3)
              if struct = ygopro.structs[ygopro.proto_structs.CTOS[ygopro.constants.CTOS[ctos_proto]]]
                struct._setBuff(b)
                if ygopro.ctos_follows[ctos_proto].synchronous
                  cancel = ygopro.ctos_follows[ctos_proto].callback b, _.clone(struct.fields), client, server
                else
                  ygopro.ctos_follows[ctos_proto].callback b, _.clone(struct.fields), client, server
              else
                ygopro.ctos_follows[ctos_proto].callback b, null, client, server
            datas.push ctos_buffer.slice(0, 2 + ctos_message_length) unless cancel
            ctos_buffer = ctos_buffer.slice(2 + ctos_message_length)
            ctos_message_length = 0
            ctos_proto = 0
          else
            break

        looplimit++
        #log.info(looplimit)
        if looplimit > 800 or ROOM_bad_ip[client.ip] > 5
          log.info("error ctos", client.name, client.ip)
          bad_ip_count = ROOM_bad_ip[client.ip]
          if bad_ip_count
            ROOM_bad_ip[client.ip] = bad_ip_count + 1
          else
            ROOM_bad_ip[client.ip] = 1
          client.destroy()
          break

      if client.established
        server.write buffer for buffer in datas
      else
        client.pre_establish_buffers.push buffer for buffer in datas

    return

  # 服务端到客户端(stoc)
  server.on 'data', (data)->
    stoc_buffer = new Buffer(0)
    stoc_message_length = 0
    stoc_proto = 0
    stoc_buffer = Buffer.concat([stoc_buffer, data], stoc_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

    #unless ygopro.stoc_follows[stoc_proto] and ygopro.stoc_follows[stoc_proto].synchronous
    #client.write data
    datas = []

    looplimit = 0

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
          #console.log "STOC", ygopro.constants.STOC[stoc_proto]
          cancel = false
          stanzas = stoc_proto
          if ygopro.stoc_follows[stoc_proto]
            b = stoc_buffer.slice(3, stoc_message_length - 1 + 3)
            if struct = ygopro.structs[ygopro.proto_structs.STOC[ygopro.constants.STOC[stoc_proto]]]
              struct._setBuff(b)
              if ygopro.stoc_follows[stoc_proto].synchronous
                cancel = ygopro.stoc_follows[stoc_proto].callback b, _.clone(struct.fields), client, server
              else
                ygopro.stoc_follows[stoc_proto].callback b, _.clone(struct.fields), client, server
            else
              if ygopro.stoc_follows[stoc_proto].synchronous
                cancel = ygopro.stoc_follows[stoc_proto].callback b, null, client, server
              else
                ygopro.stoc_follows[stoc_proto].callback b, null, client, server
          datas.push stoc_buffer.slice(0, 2 + stoc_message_length) unless cancel
          stoc_buffer = stoc_buffer.slice(2 + stoc_message_length)
          stoc_message_length = 0
          stoc_proto = 0
        else
          break

      looplimit++
      #log.info(looplimit)
      if looplimit > 800
        log.info("error stoc", client.name)
        server.destroy()
        break
    client.write buffer for buffer in datas

    return
  return
.listen settings.port, ->
  log.info "server started", settings.port
  return

# 功能模块
# return true to cancel a synchronous message

ygopro.ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server)->
  # checkmate use username$password, but here don't
  # so remove the password
  name = info.name.split("$")[0]
  struct = ygopro.structs["CTOS_PlayerInfo"]
  struct._setBuff(buffer)
  struct.set("name", name)
  buffer = struct.buffer
  client.name = name
  return false

ygopro.ctos_follow 'JOIN_GAME', false, (buffer, info, client, server)->
#log.info info
  if settings.modules.stop
    ygopro.stoc_die(client, settings.modules.stop)
    
  else if info.pass.toUpperCase()=="R" and settings.modules.enable_cloud_replay
    ygopro.stoc_send_chat(client,"以下是您近期的云录像，密码处输入 R#录像编号 即可观看", ygopro.constants.COLORS.BABYBLUE)
    redisdb.lrange client.ip+":replays", 0, 2, (err, result)->
      _.each result, (replay_id,id)->
        redisdb.hgetall "replay:"+replay_id, (err, replay)->
          if err or !replay
            log.info "cloud replay getall error: " + err if err
            return
          ygopro.stoc_send_chat(client,"<#{id-0+1}> R##{replay_id} #{replay.player_names} #{replay.date_time}", ygopro.constants.COLORS.BABYBLUE)
          return
        return
      return
    # 强行等待异步执行完毕_(:з」∠)_
    setTimeout (()->
      ygopro.stoc_send client, 'ERROR_MSG',{
        msg: 1
        code: 2
      }
      client.destroy()
      return), 500
      
  else if info.pass[0...2].toUpperCase()=="R#" and settings.modules.enable_cloud_replay
    replay_id=info.pass.split("#")[1]
    if (replay_id>0 and replay_id<=9)
      redisdb.lindex client.ip+":replays", replay_id-1, (err, replay_id)->
        if err or !replay_id
          log.info "cloud replay replayid error: " + err if err
          ygopro.stoc_die(client, "没有找到录像")
          return
        redisdb.hgetall "replay:"+replay_id, client.open_cloud_replay
        return
    else if replay_id
      redisdb.hgetall "replay:"+replay_id, client.open_cloud_replay
    else
      ygopro.stoc_die(client, "没有找到录像")

  else if info.pass.toUpperCase()=="W" and settings.modules.enable_cloud_replay
    replay_id=Cloud_replay_ids[Math.floor(Math.random()*Cloud_replay_ids.length)]
    redisdb.hgetall "replay:"+replay_id, client.open_cloud_replay

  else if info.version != settings.version and info.version != 4921 #YGOMobile不更新，强行兼容
    ygopro.stoc_send_chat(client, settings.modules.update, ygopro.constants.COLORS.RED)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 4
      code: settings.version
    }
    client.destroy()

  else if !info.pass.length and !settings.modules.enable_random_duel and !settings.modules.enable_windbot
    ygopro.stoc_die(client, "房间名为空，请填写主机密码")

  else if info.pass.length and settings.modules.mycard_auth and info.pass[0...2] != 'AI'
    ygopro.stoc_send_chat(client, '正在读取用户信息...', ygopro.constants.COLORS.BABYBLUE)
    if info.pass.length <= 8
      ygopro.stoc_die(client, '主机密码不正确 (Invalid Length)')
      return

    buffer = new Buffer(info.pass[0...8], 'base64')

    if buffer.length != 6
      ygopro.stoc_die(client, '主机密码不正确 (Invalid Payload Length)')
      return

    check = (buf)->
      checksum = 0
      for i in [0...buf.length]
        checksum += buf.readUInt8(i)
      (checksum & 0xFF) == 0

    finish = (buffer)->
      action = buffer.readUInt8(1) >> 4
      if buffer != decrypted_buffer and action in [1, 2, 4]
        ygopro.stoc_die(client, '主机密码不正确 (Unauthorized)')
        return

      # 1 create public room
      # 2 create private room
      # 3 join room
      # 4 join match
      switch action
        when 1,2
          name = crypto.createHash('md5').update(info.pass + client.name).digest('base64')[0...10].replace('+', '-').replace('/', '_')
          if ROOM_find_by_name(name)
            ygopro.stoc_die(client, '主机密码不正确 (Already Existed)')
            return

          opt1 = buffer.readUInt8(2)
          opt2 = buffer.readUInt16LE(3)
          opt3 = buffer.readUInt8(5)
          options = {
            lflist: 0
            time_limit: 180
            rule: (opt1 >> 5) & 3
            mode: (opt1 >> 3) & 3
            enable_priority: !!((opt1 >> 2) & 1)
            no_check_deck: !!((opt1 >> 1) & 1)
            no_shuffle_deck: !!(opt1 & 1)
            start_lp: opt2
            start_hand: opt3 >> 4
            draw_count: opt3 & 0xF
          }
          options.lflist = _.findIndex settings.lflist, (list)-> ((options.rule == 1) == list.tcg) and list.date.isBefore()
          room = new Room(name, options)
          room.title = info.pass.slice(8).replace(String.fromCharCode(0xFEFF), ' ')
          room.private = action == 2
        when 3
          name = info.pass.slice(8)
          room = ROOM_find_by_name(name)
          if(!room)
            ygopro.stoc_die(client, '主机密码不正确 (Not Found)')
            return
        when 4
          room = ROOM_find_or_create_by_name('M#' + info.pass.slice(8))
          room.private = true
        else
          ygopro.stoc_die(client, '主机密码不正确 (Invalid Action)')
          return
      
      if !room
        ygopro.stoc_die(client, "服务器已经爆满，请稍候再试")
      else if room.error
        ygopro.stoc_die(client, room.error)
      else
        #client.room = room
        client.rid = _.indexOf(ROOM_all, room)
        room.connect(client)
      return

    if id = users_cache[client.name]
      secret = id % 65535 + 1
      decrypted_buffer = new Buffer(6)
      for i in [0, 2, 4]
        decrypted_buffer.writeUInt16LE(buffer.readUInt16LE(i) ^ secret, i)
      if check(decrypted_buffer)
        return finish(decrypted_buffer)

    #TODO: query database directly, like preload.
    request
      baseUrl: settings.modules.mycard_auth,
      url: '/users/' + encodeURIComponent(client.name) + '.json',
      qs:
        api_key: settings.modules.mycard_auth_key,
        api_username: client.name,
        skip_track_visit: true
      json: true
    , (error, response, body)->
      if body and body.user
        secret = body.user.id % 65535 + 1
        decrypted_buffer = new Buffer(6)
        for i in [0, 2, 4]
          decrypted_buffer.writeUInt16LE(buffer.readUInt16LE(i) ^ secret, i)
        if check(decrypted_buffer)
          buffer = decrypted_buffer

      # buffer != decrypted_buffer  ==> auth failed

      if !check(buffer)
        ygopro.stoc_die(client, '主机密码不正确 (Checksum Failed)')
        return
      users_cache[client.name] = body.user.id
      finish(buffer)
  
  else if !client.name or client.name==""
    ygopro.stoc_die(client, "请输入正确的用户名")

  else if ROOM_connected_ip[client.ip] > 5
    log.warn("MULTI LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "同时开启的客户端数量过多 " + client.ip)

  else if _.indexOf(settings.ban.banned_user, client.name) > -1 #账号被封
    settings.ban.banned_ip.push(client.ip)
    log.warn("BANNED USER LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "您的账号已被封禁")

  else if _.indexOf(settings.ban.banned_ip, client.ip) > -1 #IP被封
    log.warn("BANNED IP LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "您的账号已被封禁")

  else if _.any(settings.ban.badword_level3, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 3", client.name, client.ip)
    ygopro.stoc_die(client, "您的用户名存在不适当的内容")

  else if _.any(settings.ban.badword_level2, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 2", client.name, client.ip)
    ygopro.stoc_die(client, "您的用户名存在不适当的内容")

  else if _.any(settings.ban.badword_level1, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 1", client.name, client.ip)
    ygopro.stoc_die(client, "您的用户名存在不适当的内容，请注意更改")

  else if info.pass.length && !ROOM_validate(info.pass)
    ygopro.stoc_die(client, "房间密码不正确")
  
  else
    if info.version == 4921 #YGOMobile不更新，强行兼容
      info.version = settings.version
      struct = ygopro.structs["CTOS_JoinGame"]
      struct._setBuff(buffer)
      struct.set("version", info.version)
      buffer = struct.buffer
      ygopro.stoc_send_chat(client, "您的版本号过低，可能出现未知问题，电脑用户请升级版本，YGOMobile用户请等待作者更新", ygopro.constants.COLORS.BABYBLUE)
      
    #log.info 'join_game',info.pass, client.name
    room = ROOM_find_or_create_by_name(info.pass, client.ip)
    if !room
      ygopro.stoc_die(client, "服务器已经爆满，请稍候再试")
    else if room.error
      ygopro.stoc_die(client, room.error)
    else if room.started
      if settings.modules.enable_halfway_watch
        #client.room = room
        client.rid = _.indexOf(ROOM_all, room)
        client.is_post_watcher = true
        ygopro.stoc_send_chat_to_room(room, "#{client.name} 加入了观战")
        room.watchers.push client
        ygopro.stoc_send_chat(client, "观战中", ygopro.constants.COLORS.BABYBLUE)
        for buffer in room.watcher_buffers
          client.write buffer
      else
        ygopro.stoc_die(client, "决斗已开始，不允许观战")
    else
      #client.room = room
      client.rid = _.indexOf(ROOM_all, room)
      room.connect(client)
  return

ygopro.stoc_follow 'JOIN_GAME', false, (buffer, info, client, server)->
  #欢迎信息
  room=ROOM_all[client.rid]
  return unless room
  if settings.modules.welcome
    ygopro.stoc_send_chat(client, settings.modules.welcome, ygopro.constants.COLORS.GREEN)
  if room.welcome
    ygopro.stoc_send_chat(client, room.welcome, ygopro.constants.COLORS.BABYBLUE)
    #log.info(ROOM_all)

  if !room.recorder
    room.recorder = recorder = net.connect room.port, ->
      ygopro.ctos_send recorder, 'PLAYER_INFO', {
        name: "Marshtomp"
      }
      ygopro.ctos_send recorder, 'JOIN_GAME', {
        version: settings.version,
        gameid: 2577,
        some_unknown_mysterious_fucking_thing: 0
        pass: ""
      }
      ygopro.ctos_send recorder, 'HS_TOOBSERVER'
      return

    recorder.on 'data', (data)->
      room=ROOM_all[client.rid]
      return unless room and settings.modules.enable_cloud_replay
      room.recorder_buffers.push data
      return

    recorder.on 'error', (error)->
      return

  if settings.modules.enable_halfway_watch and !room.watcher
    room.watcher = watcher = net.connect room.port, ->
      ygopro.ctos_send watcher, 'PLAYER_INFO', {
        name: "the Big Brother"
      }
      ygopro.ctos_send watcher, 'JOIN_GAME', {
        version: settings.version,
        gameid: 2577,
        some_unknown_mysterious_fucking_thing: 0
        pass: ""
      }
      ygopro.ctos_send watcher, 'HS_TOOBSERVER'
      return

    watcher.on 'data', (data)->
      room=ROOM_all[client.rid]
      return unless room
      room.watcher_buffers.push data
      for w in room.watchers
        w.write data if w #a WTF fix
      return

    watcher.on 'error', (error)->
#log.error "watcher error", error
      return
  return

# 登场台词
load_dialogues = () ->
  request
    url: settings.modules.dialogues
    json: true
  , (error, response, body)->
    if _.isString body
      log.warn "dialogues bad json", body
    else if error or !body
      log.warn 'dialogues error', error, response
    else
      nconf.myset(settings, "dialogues", body)
      log.info "dialogues loaded", _.size body
    return
  return

if settings.modules.dialogues
  load_dialogues()

ygopro.stoc_follow 'GAME_MSG', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  msg = buffer.readInt8(0)

  if msg >= 10 and msg < 30 #SELECT开头的消息
    room.waiting_for_player = client
    room.last_active_time = moment()
  #log.info("#{ygopro.constants.MSG[msg]}等待#{room.waiting_for_player.name}")

  #log.info 'MSG', ygopro.constants.MSG[msg]
  if ygopro.constants.MSG[msg] == 'START'
    playertype = buffer.readUInt8(1)
    client.is_first = !(playertype & 0xf)
    client.lp = room.hostinfo.start_lp

  #ygopro.stoc_send_chat_to_room(room, "LP跟踪调试信息: #{client.name} 初始LP #{client.lp}")
  
  if ygopro.constants.MSG[msg] == 'WIN' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first or pos == 2
    reason = buffer.readUInt8(2)
    #log.info {winner: pos, reason: reason}
    #room.duels.push {winner: pos, reason: reason}
    room.winner = pos

  #lp跟踪
  if ygopro.constants.MSG[msg] == 'DAMAGE' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "你的生命已经如风中残烛了！", ygopro.constants.COLORS.PINK)

  if ygopro.constants.MSG[msg] == 'RECOVER' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp += val

  if ygopro.constants.MSG[msg] == 'LPUPDATE' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp = val

  if ygopro.constants.MSG[msg] == 'PAY_LPCOST' and client.is_host
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "背水一战！", ygopro.constants.COLORS.PINK)

  #登场台词
  if settings.modules.dialogues
    if ygopro.constants.MSG[msg] == 'SUMMONING' or ygopro.constants.MSG[msg] == 'SPSUMMONING'
      card = buffer.readUInt32LE(1)
      if settings.dialogues[card]
        for line in _.lines settings.dialogues[card][Math.floor(Math.random() * settings.dialogues[card].length)]
          ygopro.stoc_send_chat(client, line, ygopro.constants.COLORS.PINK)
  return

#房间管理
ygopro.ctos_follow 'HS_KICK', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  for player in room.players
    if player and player.pos == info.pos and player != client
      client.kick_count = if client.kick_count then client.kick_count+1 else 1
      if client.kick_count>=5
        ygopro.stoc_send_chat_to_room(room, "#{client.name} 被系统请出了房间", ygopro.constants.COLORS.RED)
        ROOM_ban_player(player.name, player.ip, "挂房间")
        client.destroy()
        return true
      ygopro.stoc_send_chat_to_room(room, "#{player.name} 被请出了房间", ygopro.constants.COLORS.RED)
  return false

ygopro.stoc_follow 'TYPE_CHANGE', false, (buffer, info, client, server)->
  selftype = info.type & 0xf
  is_host = ((info.type >> 4) & 0xf) != 0
  client.is_host = is_host
  client.pos = selftype
  #console.log "TYPE_CHANGE to #{client.name}:", info, selftype, is_host
  return

ygopro.stoc_follow 'HS_PLAYER_CHANGE', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and room.max_player and client.is_host
  pos = info.status >> 4
  is_ready = (info.status & 0xf) == 9
  if pos < room.max_player
    room.ready_player_count_without_host = 0
    for player in room.players
      if player.pos == pos
        player.is_ready = is_ready
      unless player.is_host
        room.ready_player_count_without_host += player.is_ready
    if room.ready_player_count_without_host >= room.max_player - 1
      #log.info "all ready"
      setTimeout (()-> wait_room_start(ROOM_all[client.rid], 20);return), 1000
  return

wait_room_start = (room, time)->
  unless !room or room.started or room.ready_player_count_without_host < room.max_player - 1
    time -= 1
    if time
      unless time % 5
        ygopro.stoc_send_chat_to_room(room, "#{if time <= 9 then ' ' else ''}#{time}秒后房主若不开始游戏将被请出房间", if time <= 9 then ygopro.constants.COLORS.RED else ygopro.constants.COLORS.LIGHTBLUE)
      setTimeout (()-> wait_room_start(room, time);return), 1000
    else
      for player in room.players
        if player and player.is_host
          ROOM_ban_player(player.name, player.ip, "挂房间")
          ygopro.stoc_send_chat_to_room(room, "#{player.name} 被系统请出了房间", ygopro.constants.COLORS.RED)
          player.destroy()
  return

#tip
ygopro.stoc_send_random_tip = (client)->
  ygopro.stoc_send_chat(client, "Tip: " + settings.tips[Math.floor(Math.random() * settings.tips.length)]) if settings.modules.tips
  return
ygopro.stoc_send_random_tip_to_room = (room)->
  ygopro.stoc_send_chat_to_room(room, "Tip: " + settings.tips[Math.floor(Math.random() * settings.tips.length)]) if settings.modules.tips
  return

load_tips = ()->
  request
    url: settings.modules.tips
    json: true
  , (error, response, body)->
    if _.isString body
      log.warn "tips bad json", body
    else if error or !body
      log.warn 'tips error', error, response
    else
      nconf.myset(settings, "tips", body)
      log.info "tips loaded", settings.tips.length
    return
  return

if settings.modules.tips
  load_tips()
  setInterval ()->
    for room in ROOM_all when room and room.established
      ygopro.stoc_send_random_tip_to_room(room) unless room and room.started
    return
  , 30000

if settings.modules.mycard_auth and process.env.MYCARD_AUTH_DATABASE
  pg = require('pg')
  pg.connect process.env.MYCARD_AUTH_DATABASE, (error, client, done)->
    throw error if error
    client.query 'SELECT username, id from users', (error, result)->
      throw error if error
      done()
      for row in result.rows
        users_cache[row.username] = row.id
      console.log("users loaded", _.keys(users_cache).length)
      return
    return

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  unless room.started #first start
    room.started = true
    roomlist.delete room.name if settings.modules.enable_websocket_roomlist and not room.private
    #room.duels = []
    room.dueling_players = []
    for player in room.players when player.pos != 7
      room.dueling_players[player.pos] = player
      room.player_datas.push ip: player.ip, name: player.name
  if settings.modules.tips
    ygopro.stoc_send_random_tip(client)
  return

ygopro.ctos_follow 'CHAT', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  msg = _.trim(info.msg)
  cancel = _.startsWith(msg, "/")
  room.last_active_time = moment() unless cancel or not room.random_type
  cmd = msg.split(' ')
  switch cmd[0]
    when '/help'
      ygopro.stoc_send_chat(client, "YGOSrv233 指令帮助")
      ygopro.stoc_send_chat(client, "/help 显示这个帮助信息")
      ygopro.stoc_send_chat(client, "/roomname 显示当前房间的名字")
      ygopro.stoc_send_chat(client, "/ai 添加一个AI，/ai 角色名 可指定添加的角色") if settings.modules.enable_windbot
      ygopro.stoc_send_chat(client, "/tip 显示一条提示") if settings.modules.tips

    when '/tip'
      ygopro.stoc_send_random_tip(client) if settings.modules.tips

    when '/ai'
      if settings.modules.enable_windbot
        if name = cmd[1]
          windbot = _.sample _.filter settings.modules.windbots, (w)->
            w.name == name or w.deck == name
          if !windbot
            ygopro.stoc_send_chat(client, "未找到该AI角色或卡组", ygopro.constants.COLORS.RED)
            return
        else
          windbot = _.sample settings.modules.windbots
        room.add_windbot(windbot)

    when '/roomname'
      ygopro.stoc_send_chat(client, "您当前的房间名是 " + room.name, ygopro.constants.COLORS.BABYBLUE) if room

    #when '/test'
    #  ygopro.stoc_send_hint_card_to_room(room, 2333365)
  if !(room and room.random_type)
    return cancel
  if client.abuse_count>=5
    log.warn "BANNED CHAT", client.name, client.ip, msg
    ygopro.stoc_send_chat(client, "您已被禁言！", ygopro.constants.COLORS.RED)
    return true
  oldmsg = msg
  if (_.any(settings.ban.badword_level3, (badword) ->
    regexp = new RegExp(badword, 'i')
    return msg.match(regexp)
  , msg))
    log.warn "BAD WORD LEVEL 3", client.name, client.ip, oldmsg
    cancel = true
    if client.abuse_count>0
      ygopro.stoc_send_chat(client, "您的发言存在严重不适当的内容，禁止您使用随机对战功能！", ygopro.constants.COLORS.RED)
      ROOM_ban_player(client.name, client.ip, "发言违规")
      ROOM_ban_player(client.name, client.ip, "发言违规", 3)
      client.destroy()
      return true
    else
      client.abuse_count=client.abuse_count+4
      ygopro.stoc_send_chat(client, "您的发言存在不适当的内容，发送失败！", ygopro.constants.COLORS.RED)
  else if (_.any(settings.ban.badword_level2, (badword) ->
    regexp = new RegExp(badword, 'i')
    return msg.match(regexp)
  , msg))
    log.warn "BAD WORD LEVEL 2", client.name, client.ip, oldmsg
    client.abuse_count=client.abuse_count+3
    ygopro.stoc_send_chat(client, "您的发言存在不适当的内容，发送失败！", ygopro.constants.COLORS.RED)
    cancel = true
  else
    _.each(settings.ban.badword_level1, (badword) ->
      #log.info msg
      regexp = new RegExp(badword, "ig")
      msg = msg.replace(regexp, "**")
      return
    , msg)
    if oldmsg != msg
      log.warn "BAD WORD LEVEL 1", client.name, client.ip, oldmsg
      client.abuse_count=client.abuse_count+1
      ygopro.stoc_send_chat(client, "请使用文明用语！")
      struct = ygopro.structs["chat"]
      struct._setBuff(buffer)
      struct.set("msg", msg)
      buffer = struct.buffer
    else if (_.any(settings.ban.badword_level0, (badword) ->
      regexp = new RegExp(badword, 'i')
      return msg.match(regexp)
    , msg))
      log.info "BAD WORD LEVEL 0", client.name, client.ip, oldmsg
  if client.abuse_count>=5
    ygopro.stoc_send_chat_to_room(room, "#{client.name} 已被禁言！", ygopro.constants.COLORS.RED)
    ROOM_ban_player(client.name, client.ip, "发言违规")
  return cancel

ygopro.ctos_follow 'UPDATE_DECK', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return false unless room
  #log.info info
  buff_main = (info.deckbuf[i] for i in [0...info.mainc])
  buff_side = (info.deckbuf[i] for i in [info.mainc...info.mainc + info.sidec])
  ##client.main = main
  ##client.side = side
  if room.random_type
    if client.is_host
      room.waiting_for_player = room.waiting_for_player2
    room.last_active_time = moment()
  else if !room.started and room.hostinfo.mode == 1 and settings.modules.tournament_mode.enabled
    struct = ygopro.structs["deck"]
    struct._setBuff(buffer)
    struct.set("mainc", 1)
    struct.set("sidec", 1)
    struct.set("deckbuf", [4392470, 4392470])
    buffer = struct.buffer
    found_deck=false
    decks=fs.readdirSync(settings.modules.tournament_mode.deck_path)
    for deck in decks
      if _.endsWith(deck, client.name+".ydk")
        found_deck=deck
      if _.endsWith(deck, client.name+".ydk.ydk")
        found_deck=deck
    if found_deck
      deck_text=fs.readFileSync(settings.modules.tournament_mode.deck_path+found_deck,{encoding:"ASCII"})
      deck_array=deck_text.split("\n")
      deck_main=[]
      deck_side=[]
      current_deck=deck_main
      for line in deck_array
        if line.indexOf("!side")>=0
          current_deck=deck_side
        card=parseInt(line)
        current_deck.push(card) unless isNaN(card)
      if _.isEqual(buff_main, deck_main) and _.isEqual(buff_side, deck_side)
        deckbuf=deck_main.concat(deck_side)
        struct.set("mainc", deck_main.length)
        struct.set("sidec", deck_side.length)
        struct.set("deckbuf", deckbuf)
        buffer = struct.buffer
        #log.info("deck ok: " + client.name)
        ygopro.stoc_send_chat(client, "成功使用卡组 #{found_deck} 参加比赛。", ygopro.constants.COLORS.BABYBLUE)
      else
        #log.info("bad deck: " + client.name + " / " + buff_main + " / " + buff_side)
        ygopro.stoc_send_chat(client, "您的卡组与报名卡组 #{found_deck} 不符。注意卡组不能有包括卡片顺序在内的任何修改。", ygopro.constants.COLORS.RED)
    else
      #log.info("player deck not found: " + client.name)
      ygopro.stoc_send_chat(client, "#{client.name}，没有找到您的报名信息，请确定您使用昵称与报名ID一致。", ygopro.constants.COLORS.RED)
  return false

ygopro.ctos_follow 'RESPONSE', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and room.random_type
  room.last_active_time = moment()
  return

ygopro.ctos_follow 'HAND_RESULT', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and room.random_type
  if client.is_host
    room.waiting_for_player = room.waiting_for_player2
  room.last_active_time = moment().subtract(settings.modules.hang_timeout - 19, 's')
  return

ygopro.ctos_follow 'TP_RESULT', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and room.random_type
  room.last_active_time = moment()
  return

ygopro.stoc_follow 'SELECT_HAND', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and room.random_type
  if client.is_host
    room.waiting_for_player = client
  else
    room.waiting_for_player2 = client
  room.last_active_time = moment().subtract(settings.modules.hang_timeout - 19, 's')
  return

ygopro.stoc_follow 'SELECT_TP', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and room.random_type
  room.waiting_for_player = client
  room.last_active_time = moment()
  return

ygopro.stoc_follow 'CHANGE_SIDE', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and room.random_type
  if client.is_host
    room.waiting_for_player = client
  else
    room.waiting_for_player2 = client
  room.last_active_time = moment()
  return

ygopro.stoc_follow 'REPLAY', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return settings.modules.tournament_mode.enabled unless room
  if settings.modules.enable_cloud_replay and room.random_type
    Cloud_replay_ids.push room.cloud_replay_id
  if settings.modules.tournament_mode.enabled
    if client.is_host
      log = {
        time: moment().format('YYYY-MM-DD HH:mm:ss'),
        name: room.name,
        roomid: room.port.toString(),
        cloud_replay_id: "R#"+room.cloud_replay_id,
        players: (for player in room.players
          name: player.name,
          winner: player.pos == room.winner
        )
      }
      settings.modules.tournament_mode.duel_log.push log
      nconf.myset(settings, "modules:tournament_mode:duel_log", settings.modules.tournament_mode.duel_log)
    if settings.modules.enable_cloud_replay
      ygopro.stoc_send_chat(client, "本场比赛云录像：R##{room.cloud_replay_id}。将于本局结束后可播放。", ygopro.constants.COLORS.BABYBLUE)
    return true
  else
    return false

setInterval ()->
  for room in ROOM_all when room and room.started and room.random_type and room.last_active_time and room.waiting_for_player
    time_passed = Math.floor((moment() - room.last_active_time) / 1000)
    #log.info time_passed
    if time_passed >= settings.modules.hang_timeout
      room.last_active_time = moment()
      ROOM_ban_player(room.waiting_for_player.name, room.waiting_for_player.ip, "挂机")
      ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} 被系统请出了房间", ygopro.constants.COLORS.RED)
      room.waiting_for_player.server.destroy()
    else if time_passed >= (settings.modules.hang_timeout - 20) and not (time_passed % 10)
      ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} 已经很久没有操作了，若继续挂机，将于#{settings.modules.hang_timeout - time_passed}秒后被请出房间", ygopro.constants.COLORS.RED)
  return
, 1000

#http
if settings.modules.http

  requestListener = (request, response)->
    parseQueryString = true
    u = url.parse(request.url, parseQueryString)
    pass_validated = u.query.pass == settings.modules.http.password

    if u.pathname == '/api/getrooms'
      if !pass_validated
        response.writeHead(200)
        response.end(u.query.callback + '( {"rooms":[{"roomid":"0","roomname":"密码错误","needpass":"true"}]} );')
      else
        response.writeHead(200)
        roomsjson = JSON.stringify rooms: (for room in ROOM_all when room and room.established
          pid: room.process.pid.toString(),
          roomid: room.port.toString(),
          roomname: if pass_validated then room.name else room.name.split('$', 2)[0],
          needpass: (room.name.indexOf('$') != -1).toString(),
          users: (for player in room.players when player.pos?
            id: (-1).toString(),
            name: player.name,
            pos: player.pos
          ),
          istart: if room.started then 'start' else 'wait'
        )
        response.end(u.query.callback + "( " + roomsjson + " );")

    else if u.pathname == '/api/duellog' and settings.modules.tournament_mode.enabled
      if !pass_validated
        response.writeHead(200)
        response.end("密码错误")
        return
      else
        response.writeHead(200)
        duellog = JSON.stringify settings.modules.tournament_mode.duel_log
        response.end(u.query.callback + "( " + duellog + " );")

    else if u.pathname == '/api/message'
      if !pass_validated
        response.writeHead(200)
        response.end(u.query.callback + "( ['密码错误', 0] );")
        return

      if u.query.shout
        for room in ROOM_all when room and room.established
          ygopro.stoc_send_chat_to_room(room, u.query.shout, ygopro.constants.COLORS.YELLOW)
        response.writeHead(200)
        response.end(u.query.callback + "( ['shout ok', '" + u.query.shout + "'] );")

      else if u.query.stop
        if u.query.stop == 'false'
          u.query.stop = false
        settings.modules.stop = u.query.stop
        response.writeHead(200)
        response.end(u.query.callback + "( ['stop ok', '" + u.query.stop + "'] );")

      else if u.query.welcome
        nconf.myset(settings, 'modules:welcome', u.query.welcome)
        response.writeHead(200)
        response.end(u.query.callback + "( ['welcome ok', '" + u.query.welcome + "'] );")

      else if u.query.getwelcome
        response.writeHead(200)
        response.end(u.query.callback + "( ['get ok', '" + settings.modules.welcome + "'] );")

      else if u.query.loadtips
        load_tips()
        response.writeHead(200)
        response.end(u.query.callback + "( ['loading tip', '" + settings.modules.tips + "'] );")

      else if u.query.loaddialogues
        load_dialogues()
        response.writeHead(200)
        response.end(u.query.callback + "( ['loading dialogues', '" + settings.modules.dialogues + "'] );")

      else if u.query.ban
        ban_user(u.query.ban)
        response.writeHead(200)
        response.end(u.query.callback + "( ['ban ok', '" + u.query.ban + "'] );")

      else
        response.writeHead(404)
        response.end()

    else
      response.writeHead(404)
      response.end()
    return

  http_server = http.createServer(requestListener)
  http_server.listen settings.modules.http.port

  if settings.modules.http.ssl.enabled
    https = require 'https'
    options =
      cert: fs.readFileSync(settings.modules.http.ssl.cert)
      key: fs.readFileSync(settings.modules.http.ssl.key)
    https_server = https.createServer(options, requestListener)
    roomlist.init https_server, Room
    https_server.listen settings.modules.http.ssl.port