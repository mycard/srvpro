# 标准库
net = require 'net'
http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'
os = require 'os'
crypto = require 'crypto'
exec = require('child_process').exec
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

merge = require 'deepmerge'

#heapdump = require 'heapdump'

# 配置
# 导入旧配置
if not fs.existsSync('./config')
  fs.mkdirSync('./config')
try
  oldconfig=require('./config.user.json')
  if oldconfig.tips
    oldtips = {}
    oldtips.file = './config/tips.json'
    oldtips.tips = oldconfig.tips
    fs.writeFileSync(oldtips.file, JSON.stringify(oldtips, null, 2))
    delete oldconfig.tips
  if oldconfig.dialogues
    olddialogues = {}
    olddialogues.file = './config/dialogues.json'
    olddialogues.dialogues = oldconfig.dialogues
    fs.writeFileSync(olddialogues.file, JSON.stringify(olddialogues, null, 2))
    delete oldconfig.dialogues
  if oldconfig.modules.tournament_mode and oldconfig.modules.tournament_mode.duel_log
    oldduellog = {}
    oldduellog.file = './config/duel_log.json'
    oldduellog.duel_log = oldconfig.modules.tournament_mode.duel_log
    fs.writeFileSync(oldduellog.file, JSON.stringify(oldduellog, null, 2))
    delete oldconfig.oldduellog
  oldbadwords={}
  if oldconfig.ban.badword_level0
    oldbadwords.level0 = oldconfig.ban.badword_level0
  if oldconfig.ban.badword_level1
    oldbadwords.level1 = oldconfig.ban.badword_level1
  if oldconfig.ban.badword_level2
    oldbadwords.level2 = oldconfig.ban.badword_level2
  if oldconfig.ban.badword_level3
    oldbadwords.level3 = oldconfig.ban.badword_level3
  if not _.isEmpty(oldbadwords)
    oldbadwords.file = './config/badwords.json'
    fs.writeFileSync(oldbadwords.file, JSON.stringify(oldbadwords, null, 2))
    delete oldconfig.ban.badword_level0
    delete oldconfig.ban.badword_level1
    delete oldconfig.ban.badword_level2
    delete oldconfig.ban.badword_level3
  if not _.isEmpty(oldconfig)
    # log.info oldconfig
    fs.writeFileSync('./config/config.json', JSON.stringify(oldconfig, null, 2))
    log.info 'imported old config from config.user.json'
  fs.renameSync('./config.user.json', './config.user.bak')
catch e
  log.info e unless e.code == 'MODULE_NOT_FOUND'

setting_save = (settings) ->
  fs.writeFileSync(settings.file, JSON.stringify(settings, null, 2))
  return

setting_change = (settings, path, val) ->
  # path should be like "modules:welcome"
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
  setting_save(settings)
  return

# 读取配置
default_config = require('./data/default_config.json')
try
  config = require('./config/config.json')
catch
  config = {}
settings = global.settings = merge(default_config, config, { arrayMerge: (destination, source) -> source })

# 读取数据
default_data = require('./data/default_data.json')
try
  tips = require('./config/tips.json')
catch
  tips = default_data.tips
  setting_save(tips)
try
  dialogues = require('./config/dialogues.json')
catch
  dialogues = default_data.dialogues
  setting_save(dialogues)
try
  badwords = require('./config/badwords.json')
catch
  badwords = default_data.badwords
  setting_save(badwords)
try
  duel_log = require('./config/duel_log.json')
catch
  duel_log = default_data.duel_log
  setting_save(duel_log)

try
  cppversion = parseInt(fs.readFileSync('ygopro/gframe/game.cpp', 'utf8').match(/PRO_VERSION = ([x\dABCDEF]+)/)[1], '16')
  setting_change(settings, "version", cppversion)
  log.info "ygopro version 0x"+settings.version.toString(16), "(from source code)"
catch
  #settings.version = settings.version_default
  log.info "ygopro version 0x"+settings.version.toString(16), "(from config)"
# load the lflist of current date
lflists = (for list in fs.readFileSync('ygopro/lflist.conf', 'utf8').match(/!.*/g)
  date=list.match(/!([\d\.]+)/)
  continue unless date
  {date: moment(list.match(/!([\d\.]+)/)[1], 'YYYY.MM.DD').utcOffset("-08:00"), tcg: list.indexOf('TCG') != -1})

if settings.modules.cloud_replay.enabled
  redis = require 'redis'
  zlib = require 'zlib'
  redisdb = redis.createClient host: "127.0.0.1", port: settings.modules.cloud_replay.redis_port
  redisdb.on 'error', (err)->
    log.warn err
    return

if settings.modules.windbot.enabled
  windbots = require(settings.modules.windbot.botlist).windbots

# 组件
ygopro = require './ygopro.js'
roomlist = require './roomlist.js' if settings.modules.http.websocket_roomlist

if settings.modules.i18n.auto_pick
  geoip = require('geoip-country-lite')

# cache users of mycard login
users_cache = {}

if settings.modules.mycard.enabled
  pgClient = require('pg').Client
  pg_client = new pgClient(settings.modules.mycard.auth_database)
  pg_client.on 'error', (err) ->
    log.warn "PostgreSQL ERROR: ", err
    return
  pg_query = pg_client.query('SELECT username, id from users')
  pg_query.on 'error', (err) ->
    log.warn "PostgreSQL Query ERROR: ", err
    return
  pg_query.on 'row', (row) ->
    #log.info "load user", row.username, row.id
    users_cache[row.username] = row.id
    return
  pg_query.on 'end', (result) ->
    log.info "users loaded", result.rowCount
    return
  pg_client.on 'drain', pg_client.end.bind(pg_client)
  log.info "loading mycard user..."
  pg_client.connect()

# 获取可用内存
memory_usage = 0
get_memory_usage = ()->
  prc_free = exec("free")
  prc_free.stdout.on 'data', (data)->
    lines = data.toString().split(/\n/g)
    line = lines[0].split(/\s+/)
    new_free = if line[6] == 'available' then true else false
    line = lines[1].split(/\s+/)
    total = parseInt(line[1], 10)
    free = parseInt(line[3], 10)
    buffers = parseInt(line[5], 10)
    if new_free
      actualFree = parseInt(line[6], 10)
    else
      cached = parseInt(line[6], 10)
      actualFree = free + buffers + cached
    percentUsed = parseFloat(((1 - (actualFree / total)) * 100).toFixed(2))
    memory_usage = percentUsed
    return
  return
get_memory_usage()
setInterval(get_memory_usage, 3000)

Cloud_replay_ids = []

ROOM_all = []
ROOM_players_oppentlist = {}
ROOM_players_banned = []
ROOM_connected_ip = {}
ROOM_bad_ip = {}

# ban a user manually and permanently
ban_user = (name) ->
  settings.ban.banned_user.push(name)
  setting_save(settings)
  bad_ip=0
  for room in ROOM_all when room and room.established
    for player in room.players
      if player and (player.name == name or player.ip == bad_ip)
        bad_ip = player.ip
        ROOM_bad_ip[bad_ip]=99
        settings.ban.banned_ip.push(player.ip)
        ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        player.destroy()
        continue
  return

# automatically ban user to use random duel
ROOM_ban_player = (name, ip, reason, countadd = 1)->
  return if settings.modules.test_mode.no_ban_player
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
  if settings.modules.windbot.enabled and (uname[0...2] == 'AI' or (!settings.modules.random_duel.enabled and uname == ''))
    return ROOM_find_or_create_ai(name)
  if settings.modules.random_duel.enabled and (uname == '' or uname == 'S' or uname == 'M' or uname == 'T')
    return ROOM_find_or_create_random(uname, player_ip)
  if room = ROOM_find_by_name(name)
    return room
  else if memory_usage >= 90
    return null
  else
    return new Room(name)

ROOM_find_or_create_random = (type, player_ip)->
  bannedplayer = _.find ROOM_players_banned, (bannedplayer)->
    return player_ip == bannedplayer.ip
  if bannedplayer
    if bannedplayer.count > 6 and moment() < bannedplayer.time
      return {"error": "${random_banned_part1}#{bannedplayer.reasons.join('${random_ban_reason_separator}')}${random_banned_part2}#{moment(bannedplayer.time).fromNow(true)}${random_banned_part3}"}
    if bannedplayer.count > 3 and moment() < bannedplayer.time and bannedplayer.need_tip and type != 'T'
      bannedplayer.need_tip = false
      return {"error": "${random_deprecated_part1}#{bannedplayer.reasons.join('${random_ban_reason_separator}')}${random_deprecated_part2}#{moment(bannedplayer.time).fromNow(true)}${random_deprecated_part3}"}
    else if bannedplayer.need_tip
      bannedplayer.need_tip = false
      return {"error": "${random_warn_part1}#{bannedplayer.reasons.join('${random_ban_reason_separator}')}${random_warn_part2}"}
    else if bannedplayer.count > 2
      bannedplayer.need_tip = true
  max_player = if type == 'T' then 4 else 2
  playerbanned = (bannedplayer and bannedplayer.count > 3 and moment() < bannedplayer.time)
  result = _.find ROOM_all, (room)->
    return room and room.random_type != '' and !room.started and
    ((type == '' and room.random_type != 'T') or room.random_type == type) and
    room.get_playing_player().length < max_player and
    (settings.modules.random_duel.no_rematch_check or room.get_host() == null or
    room.get_host().ip != ROOM_players_oppentlist[player_ip]) and
    (playerbanned == room.deprecated or type == 'T')
  if result
    result.welcome = '${random_duel_enter_room_waiting}'
    #log.info 'found room', player_name
  else if memory_usage < 90
    type = if type then type else 'S'
    name = type + ',RANDOM#' + Math.floor(Math.random() * 100000)
    result = new Room(name)
    result.random_type = type
    result.max_player = max_player
    result.welcome = '${random_duel_enter_room_new}'
    result.deprecated = playerbanned
    #log.info 'create room', player_name, name
  else
    return null
  if result.random_type=='M' then result.welcome = result.welcome + '\n${random_duel_enter_room_match}'
  return result

ROOM_find_or_create_ai = (name)->
  if name == ''
    name = 'AI'
  namea = name.split('#')
  uname = name.toUpperCase()
  if room = ROOM_find_by_name(name)
    return room
  else if uname == 'AI'
    windbot = _.sample windbots
    name = 'AI#' + Math.floor(Math.random() * 100000)
  else if namea.length>1
    ainame = namea[namea.length-1]
    windbot = _.sample _.filter windbots, (w)->
      w.name == ainame or w.deck == ainame
    if !windbot
      return { "error": "${windbot_deck_not_found}" }
    name = name + ',' + Math.floor(Math.random() * 100000)
  else
    windbot = _.sample windbots
    name = name + '#' + Math.floor(Math.random() * 100000)
  if name.replace(/[^\x00-\xff]/g,"00").length>20
    log.info "long ai name", name
    return { "error": "${windbot_name_too_long}" }
  result = new Room(name)
  result.windbot = windbot
  result.private = true
  return result

ROOM_find_by_name = (name)->
  result = _.find ROOM_all, (room)->
    return room and room.name == name
  return result

ROOM_find_by_title = (title)->
  result = _.find ROOM_all, (room)->
    return room and room.title == title
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

ROOM_unwelcome = (room, bad_player, reason)->
  return unless room
  for player in room.players
    if player and player == bad_player
      ygopro.stoc_send_chat(player, "${unwelcome_warn_part1}#{reason}${unwelcome_warn_part2}", ygopro.constants.COLORS.RED)
    else if player and player.pos!=7 and player != bad_player
      player.flee_free=true
      ygopro.stoc_send_chat(player, "${unwelcome_tip_part1}#{reason}${unwelcome_tip_part2}", ygopro.constants.COLORS.BABYBLUE)
  return

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
    @scores = {}
    @duel_count = 0
    @death = 0
    ROOM_all.push this

    @hostinfo ||= JSON.parse(JSON.stringify(settings.hostinfo))
    if lflists.length
      if @hostinfo.rule == 1 and @hostinfo.lflist == 0
        @hostinfo.lflist = _.findIndex lflists, (list)-> list.tcg
    else
      @hostinfo.lflist =  -1
    @hostinfo.replay_mode = if settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.replay_safe then 1 else 0

    if name[0...2] == 'M#'
      @hostinfo.mode = 1
    else if name[0...2] == 'T#'
      @hostinfo.mode = 2
      @hostinfo.start_lp = 16000
    else if name[0...3] == 'AI#'
      @hostinfo.rule = 2
      @hostinfo.lflist = -1

    else if (param = name.match /^(\d)(\d)(T|F)(T|F)(T|F)(\d+),(\d+),(\d+)/i)
      @hostinfo.rule = parseInt(param[1])
      @hostinfo.mode = parseInt(param[2])
      @hostinfo.enable_priority = param[3] == 'T'
      @hostinfo.no_check_deck = param[4] == 'T'
      @hostinfo.no_shuffle_deck = param[5] == 'T'
      @hostinfo.start_lp = parseInt(param[6])
      @hostinfo.start_hand = parseInt(param[7])
      @hostinfo.draw_count = parseInt(param[8])

    else if ((param = name.match /(.+)#/) != null)
      rule = param[1].toUpperCase()

      if (rule.match /(^|，|,)(M|MATCH)(，|,|$)/)
        @hostinfo.mode = 1

      if (rule.match /(^|，|,)(T|TAG)(，|,|$)/)
        @hostinfo.mode = 2
        @hostinfo.start_lp = 16000

      if (rule.match /(^|，|,)(TCGONLY|TO)(，|,|$)/)
        @hostinfo.rule = 1
        @hostinfo.lflist = _.findIndex lflists, (list)-> list.tcg

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
      @process = spawn './ygopro', param, {cwd: 'ygopro'}
      @process.on 'error', (err)=>
        _.each @players, (player)->
          ygopro.stoc_die(player, "${create_room_failed}")
        this.delete()
        return
      @process.on 'exit', (code)=>
        @disconnector = 'server' unless @disconnector
        this.delete()
        return
      @process.stdout.setEncoding('utf8')
      @process.stdout.once 'data', (data)=>
        @established = true
        roomlist.create(this) if !@windbot and settings.modules.http.websocket_roomlist
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
        @ygopro_error_length = if @ygopro_error_length then @ygopro_error_length + data.length else data.length
        if @ygopro_error_length > 10000
          @process.kill()
        return
    catch
      @error = "${create_room_failed}"
  delete: ->
    return if @deleted
    #log.info 'room-delete', this.name, ROOM_all.length
    score_array=[]
    for name, score of @scores
      score_array.push { name: name, score: score }
    if score_array.length > 0 and settings.modules.arena_mode.enabled and @arena
      #log.info 'SCORE', score_array, @start_time
      if score_array.length == 2
        end_time = moment().format()
        if !@start_time
          @start_time = end_time
        request.post { url : settings.modules.arena_mode.post_score , form : {
          accesskey: settings.modules.arena_mode.accesskey,
          usernameA: score_array[0].name,
          usernameB: score_array[1].name,
          userscoreA: score_array[0].score,
          userscoreB: score_array[1].score,
          start: @start_time,
          end: end_time,
          arena: @arena
        }}, (error, response, body)=>
          if error
            log.warn 'SCORE POST ERROR', error
          else
            if response.statusCode != 204 and response.statusCode != 200
              log.warn 'SCORE POST FAIL', response.statusCode, response.statusMessage, @name, body
            #else
            #  log.info 'SCORE POST OK', response.statusCode, response.statusMessage, @name, body
          return
    if @player_datas.length and settings.modules.cloud_replay.enabled
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
    @recorder.destroy() if @recorder
    @deleted = true
    index = _.indexOf(ROOM_all, this)
    ROOM_all[index] = null unless index == -1
    #ROOM_all.splice(index, 1) unless index == -1
    roomlist.delete this if !@windbot and @established and settings.modules.http.websocket_roomlist
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
      url: "http://#{settings.modules.windbot.server_ip}:#{settings.modules.windbot.port}/?name=#{encodeURIComponent(botdata.name)}&deck=#{encodeURIComponent(botdata.deck)}&host=#{settings.modules.windbot.my_ip}&port=#{settings.port}&dialog=#{encodeURIComponent(botdata.dialog)}&version=#{settings.version}&password=#{encodeURIComponent(@name)}"
    , (error, response, body)=>
      if error
        log.warn 'windbot add error', error, this.name
        ygopro.stoc_send_chat_to_room(this, "${add_windbot_failed}", ygopro.constants.COLORS.RED)
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
      roomlist.update(this) if !@windbot and !@started and settings.modules.http.websocket_roomlist
      client.server.connect @port, '127.0.0.1', ->
        client.server.write buffer for buffer in client.pre_establish_buffers
        client.established = true
        client.pre_establish_buffers = []
        return
    return

  disconnect: (client, error)->
    if client.is_post_watcher
      ygopro.stoc_send_chat_to_room this, "#{client.name} ${quit_watch}" + if error then ": #{error}" else ''
      index = _.indexOf(@watchers, client)
      @watchers.splice(index, 1) unless index == -1
      #client.room = null
    else
      #log.info(client.name, @started, @disconnector, @random_type, @players.length)
      if @arena == "athletic" and !@started and @players.length == 2
        for player in @players when player.pos != 7
          @scores[player.name] = 0
        @scores[client.name] = -9
      index = _.indexOf(@players, client)
      @players.splice(index, 1) unless index == -1
      if @started and @disconnector != 'server' and (client.pos < 4 or client.is_host)
        @finished = true
        @scores[client.name] = -9
        if @random_type and not client.flee_free
          ROOM_ban_player(client.name, client.ip, "${random_ban_reason_flee}")
      if @players.length and !(@windbot and client.is_host)
        ygopro.stoc_send_chat_to_room this, "#{client.name} ${left_game}" + if error then ": #{error}" else ''
        roomlist.update(this) if !@windbot and !@started and settings.modules.http.websocket_roomlist
        #client.room = null
      else
        @process.kill()
        #client.room = null
        this.delete()
    return


# 网络连接
net.createServer (client) ->
  client.ip = client.remoteAddress
  client.is_local = client.ip and (client.ip.includes('127.0.0.1') or client.ip.includes(settings.modules.windbot.server_ip))

  connect_count = ROOM_connected_ip[client.ip] or 0
  if !settings.modules.test_mode.no_connect_count_limit and !client.is_local
    connect_count++
  ROOM_connected_ip[client.ip] = connect_count
  #log.info "connect", client.ip, ROOM_connected_ip[client.ip]

  # server stand for the connection to ygopro server process
  server = new net.Socket()
  client.server = server

  client.setTimeout(2000) #连接前超时2秒

  # 释放处理
  client.on 'close', (had_error) ->
    #log.info "client closed", client.name, had_error
    room=ROOM_all[client.rid]
    connect_count = ROOM_connected_ip[client.ip]
    if connect_count > 0
      connect_count--
    ROOM_connected_ip[client.ip] = connect_count
    #log.info "disconnect", client.ip, ROOM_connected_ip[client.ip]
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
    room.disconnector = 'server' if room
    server.closed = true unless server.closed
    unless client.closed
      ygopro.stoc_send_chat(client, "${server_closed}", ygopro.constants.COLORS.RED)
      client.destroy()
    return

  server.on 'error', (error)->
    #log.info "server error", client.name, error
    room=ROOM_all[client.rid]
    #log.info "server err close", client.ip, ROOM_connected_ip[client.ip]
    room.disconnector = 'server' if room
    server.closed = error
    unless client.closed
      ygopro.stoc_send_chat(client, "${server_error}: #{error}", ygopro.constants.COLORS.RED)
      client.destroy()
    return
  
  if ROOM_bad_ip[client.ip] > 5 or ROOM_connected_ip[client.ip] > 10
    log.info 'BAD IP', client.ip
    client.destroy()
    return

  if settings.modules.cloud_replay.enabled
    client.open_cloud_replay= (err, replay)->
      if err or !replay
        ygopro.stoc_die(client, "${cloud_replay_no}")
        return
      redisdb.expire("replay:"+replay.replay_id, 60*60*48)
      buffer=new Buffer(replay.replay_buffer,'binary')
      zlib.unzip buffer, (err, replay_buffer) ->
        if err
          log.info "cloud replay unzip error: " + err
          ygopro.stoc_send_chat(client, "${cloud_replay_error}", ygopro.constants.COLORS.RED)
          client.destroy()
          return
        ygopro.stoc_send_chat(client, "${cloud_replay_playing} R##{replay.replay_id} #{replay.player_names} #{replay.date_time}", ygopro.constants.COLORS.BABYBLUE)
        client.write replay_buffer, ()->
          client.destroy()
          return
        return
      return
      
  # 需要重构
  # 客户端到服务端(ctos)协议分析
  
  client.pre_establish_buffers = new Array()

  client.on 'data', (ctos_buffer) ->
    if client.is_post_watcher
      room=ROOM_all[client.rid]
      room.watcher.write ctos_buffer if room
    else
      #ctos_buffer = new Buffer(0)
      ctos_message_length = 0
      ctos_proto = 0
      #ctos_buffer = Buffer.concat([ctos_buffer, data], ctos_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

      datas = []

      looplimit = 0

      while true
        if ctos_message_length == 0
          if ctos_buffer.length >= 2
            ctos_message_length = ctos_buffer.readUInt16LE(0)
          else
            log.warn("bad ctos_buffer length", client.ip) unless ctos_buffer.length == 0
            break
        else if ctos_proto == 0
          if ctos_buffer.length >= 3
            ctos_proto = ctos_buffer.readUInt8(2)
          else
            log.warn("bad ctos_proto length", client.ip)
            break
        else
          if ctos_buffer.length >= 2 + ctos_message_length
            #console.log "CTOS", ygopro.constants.CTOS[ctos_proto]
            cancel = false
            if ygopro.ctos_follows[ctos_proto]
              b = ctos_buffer.slice(3, ctos_message_length - 1 + 3)
              info = null
              if struct = ygopro.structs[ygopro.proto_structs.CTOS[ygopro.constants.CTOS[ctos_proto]]]
                struct._setBuff(b)
                info = _.clone(struct.fields)
              if ygopro.ctos_follows[ctos_proto].synchronous
                cancel = ygopro.ctos_follows[ctos_proto].callback b, info, client, server
              else
                ygopro.ctos_follows[ctos_proto].callback b, info, client, server
            datas.push ctos_buffer.slice(0, 2 + ctos_message_length) unless cancel
            ctos_buffer = ctos_buffer.slice(2 + ctos_message_length)
            ctos_message_length = 0
            ctos_proto = 0
          else
            log.warn("bad ctos_message length", client.ip, ctos_buffer.length, ctos_message_length, ctos_proto) if ctos_message_length != 17735
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
  server.on 'data', (stoc_buffer)->
    #stoc_buffer = new Buffer(0)
    stoc_message_length = 0
    stoc_proto = 0
    #stoc_buffer = Buffer.concat([stoc_buffer, data], stoc_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

    #unless ygopro.stoc_follows[stoc_proto] and ygopro.stoc_follows[stoc_proto].synchronous
    #client.write data
    datas = []

    looplimit = 0

    while true
      if stoc_message_length == 0
        if stoc_buffer.length >= 2
          stoc_message_length = stoc_buffer.readUInt16LE(0)
        else
          log.warn("bad stoc_buffer length", client.ip) unless stoc_buffer.length == 0
          break
      else if stoc_proto == 0
        if stoc_buffer.length >= 3
          stoc_proto = stoc_buffer.readUInt8(2)
        else
          log.warn("bad stoc_proto length", client.ip)
          break
      else
        if stoc_buffer.length >= 2 + stoc_message_length
          #console.log "STOC", ygopro.constants.STOC[stoc_proto]
          cancel = false
          stanzas = stoc_proto
          if ygopro.stoc_follows[stoc_proto]
            b = stoc_buffer.slice(3, stoc_message_length - 1 + 3)
            info = null
            if struct = ygopro.structs[ygopro.proto_structs.STOC[ygopro.constants.STOC[stoc_proto]]]
              struct._setBuff(b)
              info = _.clone(struct.fields)
            if ygopro.stoc_follows[stoc_proto].synchronous
              cancel = ygopro.stoc_follows[stoc_proto].callback b, info, client, server
            else
              ygopro.stoc_follows[stoc_proto].callback b, info, client, server
          datas.push stoc_buffer.slice(0, 2 + stoc_message_length) unless cancel
          stoc_buffer = stoc_buffer.slice(2 + stoc_message_length)
          stoc_message_length = 0
          stoc_proto = 0
        else
          log.warn("bad stoc_message length", client.ip)
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

if settings.modules.stop
  log.info "NOTE: server not open due to config, ", settings.modules.stop

# 功能模块
# return true to cancel a synchronous message

ygopro.ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server)->
  # checkmate use username$password, but here don't
  # so remove the password
  name = info.name.split("$")[0]
  if (_.any(settings.ban.illegal_id, (badid) ->
    regexp = new RegExp(badid, 'i')
    matchs = name.match(regexp)
    if matchs
      name = matchs[1]
      return true
    return false
  , name))
    client.rag = true
  struct = ygopro.structs["CTOS_PlayerInfo"]
  struct._setBuff(buffer)
  struct.set("name", name)
  buffer = struct.buffer
  client.name = name

  if not settings.modules.i18n.auto_pick or client.is_local
    client.lang=settings.modules.i18n.default
  else
    geo = geoip.lookup(client.ip)
    if not geo
      log.warn("fail to locate ip", client.name, client.ip)
      client.lang=settings.modules.i18n.fallback
    else
      if lang=settings.modules.i18n.map[geo.country]
        client.lang=lang
      else
        #log.info("Not in map", geo.country, client.name, client.ip)
        client.lang=settings.modules.i18n.fallback
  return false

ygopro.ctos_follow 'JOIN_GAME', false, (buffer, info, client, server)->
#log.info info
  info.pass=info.pass.trim()
  if settings.modules.stop
    ygopro.stoc_die(client, settings.modules.stop)
    
  else if info.pass.toUpperCase()=="R" and settings.modules.cloud_replay.enabled
    ygopro.stoc_send_chat(client,"${cloud_replay_hint}", ygopro.constants.COLORS.BABYBLUE)
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
        code: 9
      }
      client.destroy()
      return), 500
      
  else if info.pass[0...2].toUpperCase()=="R#" and settings.modules.cloud_replay.enabled
    replay_id=info.pass.split("#")[1]
    if (replay_id>0 and replay_id<=9)
      redisdb.lindex client.ip+":replays", replay_id-1, (err, replay_id)->
        if err or !replay_id
          log.info "cloud replay replayid error: " + err if err
          ygopro.stoc_die(client, "${cloud_replay_no}")
          return
        redisdb.hgetall "replay:"+replay_id, client.open_cloud_replay
        return
    else if replay_id
      redisdb.hgetall "replay:"+replay_id, client.open_cloud_replay
    else
      ygopro.stoc_die(client, "${cloud_replay_no}")

  else if info.pass.toUpperCase()=="W" and settings.modules.cloud_replay.enabled
    replay_id=Cloud_replay_ids[Math.floor(Math.random()*Cloud_replay_ids.length)]
    redisdb.hgetall "replay:"+replay_id, client.open_cloud_replay

  else if info.version != settings.version # and (info.version < 9020 or settings.version != 4927) #强行兼容23333版
    ygopro.stoc_send_chat(client, settings.modules.update, ygopro.constants.COLORS.RED)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 4
      code: settings.version
    }
    client.destroy()

  else if !info.pass.length and !settings.modules.random_duel.enabled and !settings.modules.windbot.enabled
    ygopro.stoc_die(client, "${blank_room_name}")

  else if info.pass.length and settings.modules.mycard.enabled and info.pass[0...3] != 'AI#'
    ygopro.stoc_send_chat(client, '${loading_user_info}', ygopro.constants.COLORS.BABYBLUE)
    if info.pass.length <= 8
      ygopro.stoc_die(client, '${invalid_password_length}')
      return

    #if info.version >= 9020 and settings.version == 4927 #强行兼容23333版
    #  info.version = settings.version
    #  struct = ygopro.structs["CTOS_JoinGame"]
    #  struct._setBuff(buffer)
    #  struct.set("version", info.version)
    #  buffer = struct.buffer

    buffer = new Buffer(info.pass[0...8], 'base64')

    if buffer.length != 6
      ygopro.stoc_die(client, '${invalid_password_payload}')
      return

    check = (buf)->
      checksum = 0
      for i in [0...buf.length]
        checksum += buf.readUInt8(i)
      (checksum & 0xFF) == 0

    finish = (buffer)->
      action = buffer.readUInt8(1) >> 4
      if buffer != decrypted_buffer and action in [1, 2, 4]
        ygopro.stoc_die(client, '${invalid_password_unauthorized}')
        return

      # 1 create public room
      # 2 create private room
      # 3 join room by id
      # 4 create or join room by id (use for match)
      # 5 join room by title
      switch action
        when 1,2
          name = crypto.createHash('md5').update(info.pass + client.name).digest('base64')[0...10].replace('+', '-').replace('/', '_')
          if ROOM_find_by_name(name)
            ygopro.stoc_die(client, '${invalid_password_existed}')
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
          options.lflist = _.findIndex lflists, (list)-> ((options.rule == 1) == list.tcg) and list.date.isBefore()
          room = new Room(name, options)
          room.title = info.pass.slice(8).replace(String.fromCharCode(0xFEFF), ' ')
          room.private = action == 2
        when 3
          name = info.pass.slice(8)
          room = ROOM_find_by_name(name)
          if(!room)
            ygopro.stoc_die(client, '${invalid_password_not_found}')
            return
        when 4
          room = ROOM_find_or_create_by_name('M#' + info.pass.slice(8))
          room.private = true
          room.arena = settings.modules.arena_mode.mode
          if room.arena == "athletic"
            room.max_player = 2
            room.welcome = "${athletic_arena_tip}"
        when 5
          title = info.pass.slice(8).replace(String.fromCharCode(0xFEFF), ' ')
          room = ROOM_find_by_title(title)
          if(!room)
            ygopro.stoc_die(client, '${invalid_password_not_found}')
            return
        else
          ygopro.stoc_die(client, '${invalid_password_action}')
          return
      
      if !room
        ygopro.stoc_die(client, "${server_full}")
      else if room.error
        ygopro.stoc_die(client, room.error)
      else if room.started
        if settings.modules.cloud_replay.enable_halfway_watch
          client.setTimeout(300000) #连接后超时5分钟
          client.rid = _.indexOf(ROOM_all, room)
          client.is_post_watcher = true
          ygopro.stoc_send_chat_to_room(room, "#{client.name} ${watch_join}")
          room.watchers.push client
          ygopro.stoc_send_chat(client, "${watch_watching}", ygopro.constants.COLORS.BABYBLUE)
          for buffer in room.watcher_buffers
            client.write buffer
        else
          ygopro.stoc_die(client, "${watch_denied}")
      else
        #client.room = room
        client.setTimeout(300000) #连接后超时5分钟
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
      baseUrl: settings.modules.mycard.auth_base_url,
      url: '/users/' + encodeURIComponent(client.name) + '.json',
      qs:
        api_key: settings.modules.mycard.auth_key,
        api_username: client.name,
        skip_track_visit: true
      json: true
    , (error, response, body)->
      if body and body.user
        users_cache[client.name] = body.user.id
        secret = body.user.id % 65535 + 1
        decrypted_buffer = new Buffer(6)
        for i in [0, 2, 4]
          decrypted_buffer.writeUInt16LE(buffer.readUInt16LE(i) ^ secret, i)
        if check(decrypted_buffer)
          buffer = decrypted_buffer

      # buffer != decrypted_buffer  ==> auth failed

      if !check(buffer)
        ygopro.stoc_die(client, '${invalid_password_checksum}')
        return
      
      finish(buffer)
  
  else if !client.name or client.name==""
    ygopro.stoc_die(client, "${bad_user_name}")

  else if ROOM_connected_ip[client.ip] > 5
    log.warn("MULTI LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${too_much_connection}" + client.ip)

  else if _.indexOf(settings.ban.banned_user, client.name) > -1 #账号被封
    settings.ban.banned_ip.push(client.ip)
    setting_save(settings)
    log.warn("BANNED USER LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${banned_user_login}")

  else if _.indexOf(settings.ban.banned_ip, client.ip) > -1 #IP被封
    log.warn("BANNED IP LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${banned_ip_login}")

  else if _.any(badwords.level3, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 3", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level3}")

  else if _.any(badwords.level2, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 2", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level2}")

  else if _.any(badwords.level1, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 1", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level1}")

  else if info.pass.length && !ROOM_validate(info.pass)
    ygopro.stoc_die(client, "${invalid_password_room}")
  
  else
    #if info.version >= 9020 and settings.version == 4927 #强行兼容23333版
    #  info.version = settings.version
    #  struct = ygopro.structs["CTOS_JoinGame"]
    #  struct._setBuff(buffer)
    #  struct.set("version", info.version)
    #  buffer = struct.buffer
    #  #ygopro.stoc_send_chat(client, "看起来你是YGOMobile的用户，请记得更新先行卡补丁，否则会看到白卡", ygopro.constants.COLORS.GREEN)
      
    #log.info 'join_game',info.pass, client.name
    room = ROOM_find_or_create_by_name(info.pass, client.ip)
    if !room
      ygopro.stoc_die(client, "${server_full}")
    else if room.error
      ygopro.stoc_die(client, room.error)
    else if room.started
      if settings.modules.cloud_replay.enable_halfway_watch
        client.setTimeout(300000) #连接后超时5分钟
        client.rid = _.indexOf(ROOM_all, room)
        client.is_post_watcher = true
        ygopro.stoc_send_chat_to_room(room, "#{client.name} ${watch_join}")
        room.watchers.push client
        ygopro.stoc_send_chat(client, "${watch_watching}", ygopro.constants.COLORS.BABYBLUE)
        for buffer in room.watcher_buffers
          client.write buffer
      else
        ygopro.stoc_die(client, "${watch_denied}")
    else
      client.setTimeout(300000) #连接后超时5分钟
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
  if settings.modules.arena_mode.enabled and !client.is_local #and not client.score_shown
    request
      url: settings.modules.arena_mode.get_score + encodeURIComponent(client.name),
      json: true
    , (error, response, body)->
      if error
        log.warn 'LOAD SCORE ERROR', client.name, error
      else if !body or _.isString body
        log.warn 'LOAD SCORE FAIL', client.name, response.statusCode, response.statusMessage, body
      else
        #log.info 'LOAD SCORE', client.name, body
        rank_txt = if body.arena_rank>0 then "${rank_arena}" + body.arena_rank else "${rank_blank}"
        ygopro.stoc_send_chat(client, "#{client.name}${exp_value_part1}#{body.exp}${exp_value_part2}${exp_value_part3}#{Math.round(body.pt)}#{rank_txt}${exp_value_part4}", ygopro.constants.COLORS.BABYBLUE)
        #client.score_shown = true
      return

  if !room.recorder
    room.recorder = recorder = net.connect room.port, ->
      ygopro.ctos_send recorder, 'PLAYER_INFO', {
        name: "Marshtomp"
      }
      ygopro.ctos_send recorder, 'JOIN_GAME', {
        version: settings.version,
        pass: "Marshtomp"
      }
      ygopro.ctos_send recorder, 'HS_TOOBSERVER'
      return

    recorder.on 'data', (data)->
      room=ROOM_all[client.rid]
      return unless room and settings.modules.cloud_replay.enabled
      room.recorder_buffers.push data
      return

    recorder.on 'error', (error)->
      return

  if settings.modules.cloud_replay.enable_halfway_watch and !room.watcher
    room.watcher = watcher = if settings.modules.test_mode.watch_public_hand then room.recorder else net.connect room.port, ->
      ygopro.ctos_send watcher, 'PLAYER_INFO', {
        name: "the Big Brother"
      }
      ygopro.ctos_send watcher, 'JOIN_GAME', {
        version: settings.version,
        pass: "the Big Brother"
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
    url: settings.modules.dialogues.get
    json: true
  , (error, response, body)->
    if _.isString body
      log.warn "dialogues bad json", body
    else if error or !body
      log.warn 'dialogues error', error, response
    else
      setting_change(dialogues, "dialogues", body)
      log.info "dialogues loaded", _.size dialogues.dialogues
    return
  return

if settings.modules.dialogues.get
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
    if client.pos == 0
      room.turn = 0
      room.duel_count = room.duel_count + 1
      if room.death and room.duel_count > 1
        if room.death == -1
          ygopro.stoc_send_chat_to_room(room, "${death_start_final}", ygopro.constants.COLORS.BABYBLUE)
        else
          ygopro.stoc_send_chat_to_room(room, "${death_start_extra}", ygopro.constants.COLORS.BABYBLUE)

  #ygopro.stoc_send_chat_to_room(room, "LP跟踪调试信息: #{client.name} 初始LP #{client.lp}")

  if ygopro.constants.MSG[msg] == 'NEW_TURN'
    if client.pos == 0
      room.turn = room.turn + 1
      if room.death
        if room.turn >= room.death
          if room.dueling_players[0].lp != room.dueling_players[1].lp and room.turn > 1
            ygopro.stoc_send_chat_to_room(room, "${death_finish_part1}" + (if room.dueling_players[0].lp > room.dueling_players[1].lp then room.dueling_players[0] else room.dueling_players[1]).name + "${death_finish_part2}", ygopro.constants.COLORS.BABYBLUE)
            ygopro.ctos_send((if room.dueling_players[0].lp > room.dueling_players[1].lp then room.dueling_players[1] else room.dueling_players[0]).server, 'SURRENDER')
          else
            room.death = -1
            ygopro.stoc_send_chat_to_room(room, "${death_remain_final}", ygopro.constants.COLORS.BABYBLUE)            
        else
          ygopro.stoc_send_chat_to_room(room, "${death_remain_part1}" + (room.death - room.turn) + "${death_remain_part2}", ygopro.constants.COLORS.BABYBLUE)
    if client.surrend_confirm
      client.surrend_confirm = false
      ygopro.stoc_send_chat(client, "${surrender_canceled}", ygopro.constants.COLORS.BABYBLUE)
  
  if ygopro.constants.MSG[msg] == 'WIN' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first or pos == 2
    reason = buffer.readUInt8(2)
    #log.info {winner: pos, reason: reason}
    #room.duels.push {winner: pos, reason: reason}
    room.winner = pos
    room.turn = 0
    if room and !room.finished and room.dueling_players[pos]
      room.winner_name = room.dueling_players[pos].name
      #log.info room.dueling_players, pos
      room.scores[room.winner_name] = room.scores[room.winner_name] + 1
    if room.death 
      if settings.modules.http.quick_death_rule
        room.death = -1
      else
        room.death = 5

  #lp跟踪
  if ygopro.constants.MSG[msg] == 'DAMAGE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "${lp_low_opponent}", ygopro.constants.COLORS.PINK)

  if ygopro.constants.MSG[msg] == 'RECOVER' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp += val

  if ygopro.constants.MSG[msg] == 'LPUPDATE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp = val

  if ygopro.constants.MSG[msg] == 'PAY_LPCOST' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "${lp_low_self}", ygopro.constants.COLORS.PINK)

  #登场台词
  if settings.modules.dialogues.enabled
    if ygopro.constants.MSG[msg] == 'SUMMONING' or ygopro.constants.MSG[msg] == 'SPSUMMONING'
      card = buffer.readUInt32LE(1)
      if dialogues.dialogues[card]
        for line in _.lines dialogues.dialogues[card][Math.floor(Math.random() * dialogues.dialogues[card].length)]
          ygopro.stoc_send_chat(client, line, ygopro.constants.COLORS.PINK)
  return

#房间管理
ygopro.ctos_follow 'HS_TOOBSERVER', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  if not room.arena or client.is_local
    return false
  for player in room.players
    if player == client
      ygopro.stoc_send_chat(client, "${cannot_to_observer}", ygopro.constants.COLORS.BABYBLUE)
      return true
  return false

ygopro.ctos_follow 'HS_KICK', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  for player in room.players
    if player and player.pos == info.pos and player != client
      if room.arena == "athletic"
        ygopro.stoc_send_chat_to_room(room, "#{client.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        client.destroy()
        return true
      client.kick_count = if client.kick_count then client.kick_count+1 else 1
      if client.kick_count>=5 and room.random_type
        ygopro.stoc_send_chat_to_room(room, "#{client.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        ROOM_ban_player(player.name, player.ip, "${random_ban_reason_zombie}")
        client.destroy()
        return true
      ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_player}", ygopro.constants.COLORS.RED)
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
    if room.arena
      room.ready_player_count = 0
      for player in room.players
        if player.pos == pos
          player.is_ready = is_ready
      p1 = room.players[0]
      p2 = room.players[1]
      if !p1 or !p2
        if room.waiting_for_player_interval
          clearInterval room.waiting_for_player_interval
          room.waiting_for_player_interval = null
        return
      room.waiting_for_player2 = room.waiting_for_player
      room.waiting_for_player = null
      if p1.is_ready and p2.is_ready
        room.waiting_for_player = if p1.is_host then p1 else p2
      if !p1.is_ready and p2.is_ready
        room.waiting_for_player = p1
      if !p2.is_ready and p1.is_ready
        room.waiting_for_player = p2
      if room.waiting_for_player != room.waiting_for_player2
        room.waiting_for_player2 = room.waiting_for_player
        room.waiting_for_player_time = 20
        room.waiting_for_player_interval = setInterval (()-> wait_room_start_arena(ROOM_all[client.rid]);return), 1000
      else if !room.waiting_for_player and room.waiting_for_player_interval
        clearInterval room.waiting_for_player_interval
        room.waiting_for_player_interval = null
        room.waiting_for_player_time = 20
    else
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
        ygopro.stoc_send_chat_to_room(room, "#{if time <= 9 then ' ' else ''}#{time}${kick_count_down}", if time <= 9 then ygopro.constants.COLORS.RED else ygopro.constants.COLORS.LIGHTBLUE)
      setTimeout (()-> wait_room_start(room, time);return), 1000
    else
      for player in room.players
        if player and player.is_host
          ROOM_ban_player(player.name, player.ip, "${random_ban_reason_zombie}")
          ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
          player.destroy()
  return

wait_room_start_arena = (room)->
  unless !room or room.started or !room.waiting_for_player
    room.waiting_for_player_time = room.waiting_for_player_time - 1
    if room.waiting_for_player_time > 0
      unless room.waiting_for_player_time % 5
        ygopro.stoc_send_chat_to_room(room, "#{if room.waiting_for_player_time <= 9 then ' ' else ''}#{room.waiting_for_player_time}${kick_count_down_arena_part1} #{room.waiting_for_player.name} ${kick_count_down_arena_part2}", if room.waiting_for_player_time <= 9 then ygopro.constants.COLORS.RED else ygopro.constants.COLORS.LIGHTBLUE)
    else
      ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
      room.waiting_for_player.destroy()
      if room.waiting_for_player_interval
        clearInterval room.waiting_for_player_interval
        room.waiting_for_player_interval = null
  return

#tip
ygopro.stoc_send_random_tip = (client)->
  if settings.modules.tips.enabled && tips.tips.length
    ygopro.stoc_send_chat(client, "Tip: " + tips.tips[Math.floor(Math.random() * tips.tips.length)])
  return
ygopro.stoc_send_random_tip_to_room = (room)->
  if settings.modules.tips.enabled && tips.tips.length
    ygopro.stoc_send_chat_to_room(room, "Tip: " + tips.tips[Math.floor(Math.random() * tips.tips.length)])
  return

load_tips = ()->
  request
    url: settings.modules.tips.get
    json: true
  , (error, response, body)->
    if _.isString body
      log.warn "tips bad json", body
    else if error or !body
      log.warn 'tips error', error, response
    else
      setting_change(tips, "tips", body)
      log.info "tips loaded", tips.tips.length
    return
  return

if settings.modules.tips.get
  load_tips()
  setInterval ()->
    for room in ROOM_all when room and room.established
      ygopro.stoc_send_random_tip_to_room(room) if !room.started or room.changing_side
    return
  , 30000

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  unless room.started #first start
    room.started = true
    room.start_time = moment().format()
    roomlist.start room if !room.windbot and settings.modules.http.websocket_roomlist
    #room.duels = []
    room.dueling_players = []
    for player in room.players when player.pos != 7
      room.dueling_players[player.pos] = player
      room.scores[player.name] = 0
      room.player_datas.push ip: player.ip, name: player.name
      if room.random_type == 'T'
        # 双打房不记录匹配过
        ROOM_players_oppentlist[player.ip] = null
  if settings.modules.tips.enabled
    ygopro.stoc_send_random_tip(client)
  if settings.modules.deck_log.enabled and client.main and client.main.length and not client.deck_saved and not room.windbot
    deck_text = '#ygopro-server deck log\n#main\n' + client.main.join('\n') + '\n!side\n' + client.side.join('\n') + '\n'
    deck_arena = settings.modules.deck_log.arena + '-'
    if room.arena
      deck_arena = deck_arena + room.arena
    else if room.hostinfo.mode == 2
      deck_arena = deck_arena + 'tag'
    else if room.random_type == 'S'
      deck_arena = deck_arena + 'entertain'
    else if room.random_type == 'M'
      deck_arena = deck_arena + 'athletic'
    else
      deck_arena = deck_arena + 'custom'
    #log.info "DECK LOG START", client.name, room.arena
    if settings.modules.deck_log.local
      deck_name = moment().format('YYYY-MM-DD HH-mm-ss') + ' ' + room.port + ' ' + client.pos + ' ' + client.ip.slice(7) + ' ' + client.name.replace(/[\/\\\?\*]/g, '_')
      fs.writeFile settings.modules.deck_log.local + deck_name + '.ydk', deck_text, 'utf-8', (err) ->
        if err
          log.warn 'DECK SAVE ERROR', err
    if settings.modules.deck_log.post
      request.post { url : settings.modules.deck_log.post , form : {
        accesskey: settings.modules.deck_log.accesskey,
        deck: deck_text,
        playername: client.name,
        arena: deck_arena
      }}, (error, response, body)->
        if error
          log.warn 'DECK POST ERROR', error
        else
          if response.statusCode != 200
            log.warn 'DECK POST FAIL', response.statusCode, client.name, body
          #else
            #log.info 'DECK POST OK', response.statusCode, client.name, body
        return
    client.deck_saved = true
  return

ygopro.ctos_follow 'SURRENDER', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  if !room.started or room.hostinfo.mode==2
    return true
  if room.random_type and room.turn < 3 and not client.flee_free
    ygopro.stoc_send_chat(client, "${surrender_denied}", ygopro.constants.COLORS.BABYBLUE)
    return true
  return false

report_to_big_brother = (roomname, sender, ip, level, content, match) ->
  return unless settings.modules.big_brother.enabled
  request.post { url : settings.modules.big_brother.post , form : {
    accesskey: settings.modules.big_brother.accesskey,
    roomname: roomname,
    sender: sender,
    ip: ip,
    level: level,
    content: content,
    match: match
  }}, (error, response, body)->
    if error
      log.warn 'BIG BROTHER ERROR', error
    else
      if response.statusCode != 200
        log.warn 'BIG BROTHER FAIL', response.statusCode, roomname, body
      #else
        #log.info 'BIG BROTHER OK', response.statusCode, roomname, body
    return
  return

ygopro.ctos_follow 'CHAT', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  msg = _.trim(info.msg)
  cancel = _.startsWith(msg, "/")
  room.last_active_time = moment() unless cancel or not (room.random_type or room.arena)
  cmd = msg.split(' ')
  switch cmd[0]
    when '/投降', '/surrender'
      if !room.started or room.hostinfo.mode==2
        return cancel
      if room.random_type and room.turn < 3
        ygopro.stoc_send_chat(client, "${surrender_denied}", ygopro.constants.COLORS.BABYBLUE)
        return cancel
      if client.surrend_confirm
        ygopro.ctos_send(client.server, 'SURRENDER')
      else
        ygopro.stoc_send_chat(client, "${surrender_confirm}", ygopro.constants.COLORS.BABYBLUE)
        client.surrend_confirm = true

    when '/help'
      ygopro.stoc_send_chat(client, "${chat_order_main}")
      ygopro.stoc_send_chat(client, "${chat_order_help}")
      ygopro.stoc_send_chat(client, "${chat_order_roomname}") if !settings.modules.mycard.enabled
      ygopro.stoc_send_chat(client, "${chat_order_windbot}") if settings.modules.windbot.enabled
      ygopro.stoc_send_chat(client, "${chat_order_tip}") if settings.modules.tips.enabled

    when '/tip'
      ygopro.stoc_send_random_tip(client) if settings.modules.tips.enabled

    when '/ai'
      if settings.modules.windbot.enabled
        if name = cmd[1]
          windbot = _.sample _.filter windbots, (w)->
            w.name == name or w.deck == name
          if !windbot
            ygopro.stoc_send_chat(client, "${windbot_deck_not_found}", ygopro.constants.COLORS.RED)
            return
        else
          windbot = _.sample windbots
        room.add_windbot(windbot)

    when '/roomname'
      ygopro.stoc_send_chat(client, "${room_name} " + room.name, ygopro.constants.COLORS.BABYBLUE) if room

    #when '/test'
    #  ygopro.stoc_send_hint_card_to_room(room, 2333365)
  if (msg.length>100)
    log.warn "SPAM WORD", client.name, client.ip, msg
    client.abuse_count=client.abuse_count+2 if client.abuse_count
    ygopro.stoc_send_chat(client, "${chat_warn_level0}", ygopro.constants.COLORS.RED)
    cancel = true
  if !(room and room.random_type)
    return cancel
  if client.abuse_count>=5
    log.warn "BANNED CHAT", client.name, client.ip, msg
    ygopro.stoc_send_chat(client, "${banned_chat_tip}", ygopro.constants.COLORS.RED)
    return true
  oldmsg = msg
  if (_.any(badwords.level3, (badword) ->
    regexp = new RegExp(badword, 'i')
    return msg.match(regexp)
  , msg))
    log.warn "BAD WORD LEVEL 3", client.name, client.ip, oldmsg, RegExp.$1
    report_to_big_brother room.name, client.name, client.ip, 3, oldmsg, RegExp.$1
    cancel = true
    if client.abuse_count>0
      ygopro.stoc_send_chat(client, "${banned_duel_tip}", ygopro.constants.COLORS.RED)
      ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}")
      ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}", 3)
      client.destroy()
      return true
    else
      client.abuse_count=client.abuse_count+4
      ygopro.stoc_send_chat(client, "${chat_warn_level2}", ygopro.constants.COLORS.RED)
  else if (client.rag and room.started)
    client.rag = false
    #ygopro.stoc_send_chat(client, "${chat_warn_level0}", ygopro.constants.COLORS.RED)
    cancel = true
  else if (_.any(settings.ban.spam_word, (badword) ->
    regexp = new RegExp(badword, 'i')
    return msg.match(regexp)
  , msg))
    #log.warn "SPAM WORD", client.name, client.ip, oldmsg
    client.abuse_count=client.abuse_count+2
    ygopro.stoc_send_chat(client, "${chat_warn_level0}", ygopro.constants.COLORS.RED)
    cancel = true
  else if (_.any(badwords.level2, (badword) ->
    regexp = new RegExp(badword, 'i')
    return msg.match(regexp)
  , msg))
    log.warn "BAD WORD LEVEL 2", client.name, client.ip, oldmsg, RegExp.$1
    report_to_big_brother room.name, client.name, client.ip, 2, oldmsg, RegExp.$1
    client.abuse_count=client.abuse_count+3
    ygopro.stoc_send_chat(client, "${chat_warn_level2}", ygopro.constants.COLORS.RED)
    cancel = true
  else
    _.each(badwords.level1, (badword) ->
      #log.info msg
      regexp = new RegExp(badword, "ig")
      msg = msg.replace(regexp, "**")
      return
    , msg)
    if oldmsg != msg
      log.warn "BAD WORD LEVEL 1", client.name, client.ip, oldmsg, RegExp.$1
      report_to_big_brother room.name, client.name, client.ip, 1, oldmsg, RegExp.$1
      client.abuse_count=client.abuse_count+1
      ygopro.stoc_send_chat(client, "${chat_warn_level1}")
      struct = ygopro.structs["chat"]
      struct._setBuff(buffer)
      struct.set("msg", msg)
      buffer = struct.buffer
    else if (_.any(badwords.level0, (badword) ->
      regexp = new RegExp(badword, 'i')
      return msg.match(regexp)
    , msg))
      log.info "BAD WORD LEVEL 0", client.name, client.ip, oldmsg, RegExp.$1
      report_to_big_brother room.name, client.name, client.ip, 0, oldmsg, RegExp.$1
  if client.abuse_count>=2
    ROOM_unwelcome(room, client, "${random_ban_reason_abuse}")
  if client.abuse_count>=5
    ygopro.stoc_send_chat_to_room(room, "#{client.name} ${chat_banned}", ygopro.constants.COLORS.RED)
    ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}")
  return cancel

ygopro.ctos_follow 'UPDATE_DECK', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return false unless room
  #log.info info
  buff_main = (info.deckbuf[i] for i in [0...info.mainc])
  buff_side = (info.deckbuf[i] for i in [info.mainc...info.mainc + info.sidec])
  client.main = buff_main
  client.side = buff_side
  if room.random_type or room.arena
    if client.pos == 0
      room.waiting_for_player = room.waiting_for_player2
    room.last_active_time = moment()
  else if !room.started and room.hostinfo.mode == 1 and settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.deck_check
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
        ygopro.stoc_send_chat(client, "${deck_correct_part1} #{found_deck} ${deck_correct_part2}", ygopro.constants.COLORS.BABYBLUE)
      else
        #log.info("bad deck: " + client.name + " / " + buff_main + " / " + buff_side)
        ygopro.stoc_send_chat(client, "${deck_incorrect_part1} #{found_deck} ${deck_incorrect_part2}", ygopro.constants.COLORS.RED)
    else
      #log.info("player deck not found: " + client.name)
      ygopro.stoc_send_chat(client, "#{client.name}${deck_not_found}", ygopro.constants.COLORS.RED)
  return false

ygopro.ctos_follow 'RESPONSE', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and (room.random_type or room.arena)
  room.last_active_time = moment()
  return

ygopro.ctos_follow 'HAND_RESULT', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and (room.random_type or room.arena)
  if client.pos == 0
    room.waiting_for_player = room.waiting_for_player2
  room.last_active_time = moment().subtract(settings.modules.random_duel.hang_timeout - 19, 's')
  return

ygopro.ctos_follow 'TP_RESULT', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and (room.random_type or room.arena)
  room.last_active_time = moment()
  return

ygopro.stoc_follow 'SELECT_HAND', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room and (room.random_type or room.arena)
  if client.pos == 0
    room.waiting_for_player = client
  else
    room.waiting_for_player2 = client
  room.last_active_time = moment().subtract(settings.modules.random_duel.hang_timeout - 19, 's')
  return

ygopro.stoc_follow 'SELECT_TP', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  room.changing_side = false
  if room.random_type or room.arena
    room.waiting_for_player = client
    room.last_active_time = moment()
  return

ygopro.stoc_follow 'CHANGE_SIDE', false, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return unless room
  room.changing_side = true
  if room.random_type or room.arena
    if client.pos == 0
      room.waiting_for_player = client
    else
      room.waiting_for_player2 = client
    room.last_active_time = moment()
  return

ygopro.stoc_follow 'REPLAY', true, (buffer, info, client, server)->
  room=ROOM_all[client.rid]
  return settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.replay_safe unless room
  if settings.modules.cloud_replay.enabled and room.random_type
    Cloud_replay_ids.push room.cloud_replay_id
  if settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.replay_safe
    if client.pos == 0
      dueltime=moment().format('YYYY-MM-DD HH:mm:ss')
      replay_filename=dueltime
      for player,i in room.dueling_players
        replay_filename=replay_filename + (if i > 0 then " VS " else " ") + player.name
      replay_filename=replay_filename.replace(/[\/\\\?\*]/g, '_')+".yrp"
      duellog = {
        time: dueltime,
        name: room.name + (if settings.modules.tournament_mode.show_info then (" (Duel:" + room.duel_count + ")") else ""),
        roomid: room.port.toString(),
        cloud_replay_id: "R#"+room.cloud_replay_id,
        replay_filename: replay_filename,
        players: (for player in room.dueling_players
          name: player.name + (if settings.modules.tournament_mode.show_ip and !player.is_local then (" (IP: " + player.ip.slice(7) + ")") else "") + (if settings.modules.tournament_mode.show_info and not (room.hostinfo.mode == 2 and player.pos > 1) then (" (Score:" + room.scores[player.name] + " LP:" + (if player.lp? then player.lp else room.hostinfo.start_lp) + ")") else ""),
          winner: player.pos == room.winner
        )
      }
      duel_log.duel_log.unshift duellog
      setting_save(duel_log)
      fs.writeFile(settings.modules.tournament_mode.replay_path + replay_filename, buffer, (err)->
        if err then log.warn "SAVE REPLAY ERROR", replay_filename, err
      )
    if settings.modules.cloud_replay.enabled
      ygopro.stoc_send_chat(client, "${cloud_replay_delay_part1}R##{room.cloud_replay_id}${cloud_replay_delay_part2}", ygopro.constants.COLORS.BABYBLUE)
    return true
  else
    return false

if settings.modules.random_duel.enabled
  setInterval ()->
    for room in ROOM_all when room and room.started and room.random_type and room.last_active_time and room.waiting_for_player
      time_passed = Math.floor((moment() - room.last_active_time) / 1000)
      #log.info time_passed
      if time_passed >= settings.modules.random_duel.hang_timeout
        room.last_active_time = moment()
        ROOM_ban_player(room.waiting_for_player.name, room.waiting_for_player.ip, "${random_ban_reason_AFK}")
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        room.waiting_for_player.server.destroy()
      else if time_passed >= (settings.modules.random_duel.hang_timeout - 20) and not (time_passed % 10)
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${afk_warn_part1}#{settings.modules.random_duel.hang_timeout - time_passed}${afk_warn_part2}", ygopro.constants.COLORS.RED)
        ROOM_unwelcome(room, room.waiting_for_player, "${random_ban_reason_AFK}")
    return
  , 1000

if settings.modules.mycard.enabled
  setInterval ()->
    for room in ROOM_all when room and room.started and room.arena and room.last_active_time and room.waiting_for_player
      time_passed = Math.floor((moment() - room.last_active_time) / 1000)
      #log.info time_passed
      if time_passed >= settings.modules.random_duel.hang_timeout
        room.last_active_time = moment()
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        room.scores[room.waiting_for_player.name] = -9
        #log.info room.waiting_for_player.name, room.scores[room.waiting_for_player.name]
        room.waiting_for_player.server.destroy()
      else if time_passed >= (settings.modules.random_duel.hang_timeout - 20) and not (time_passed % 10)
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${afk_warn_part1}#{settings.modules.random_duel.hang_timeout - time_passed}${afk_warn_part2}", ygopro.constants.COLORS.RED)
    return
  , 1000

# spawn windbot
if settings.modules.windbot.spawn
  if /^win/.test(process.platform)
    windbot_bin = 'WindBot.exe'
    windbot_parameters = []
  else
    windbot_bin = 'mono'
    windbot_parameters = ['WindBot.exe']
  windbot_parameters.push('ServerMode=true')
  windbot_parameters.push('ServerPort='+settings.modules.windbot.port)
  windbot_process = spawn windbot_bin, windbot_parameters, {cwd: 'windbot'}
  windbot_process.on 'error', (err)->
    log.warn 'WindBot ERROR', err
    return
  windbot_process.on 'exit', (code)->
    log.warn 'WindBot EXIT', code
    return
  windbot_process.stdout.setEncoding('utf8')
  windbot_process.stdout.on 'data', (data)->
    log.info 'WindBot:', data
    return
  windbot_process.stderr.setEncoding('utf8')
  windbot_process.stderr.on 'data', (data)->
    log.warn 'WindBot Error:', data
    return

#http
if settings.modules.http

  addCallback = (callback, text)->
    if not callback then return text
    return callback + "( " + text + " );"

  requestListener = (request, response)->
    parseQueryString = true
    u = url.parse(request.url, parseQueryString)
    pass_validated = u.query.pass == settings.modules.http.password

    if u.pathname == '/api/getrooms'
      if !pass_validated and !settings.modules.http.public_roomlist
        response.writeHead(200)
        response.end(addCallback(u.query.callback, '{"rooms":[{"roomid":"0","roomname":"密码错误","needpass":"true"}]}'))
      else
        response.writeHead(200)
        roomsjson = JSON.stringify rooms: (for room in ROOM_all when room and room.established
          pid: room.process.pid.toString(),
          roomid: room.port.toString(),
          roomname: if pass_validated then room.name else room.name.split('$', 2)[0],
          needpass: (room.name.indexOf('$') != -1).toString(),
          users: (for player in room.players when player.pos?
            id: (-1).toString(),
            name: player.name + (if settings.modules.http.show_ip and pass_validated and !player.is_local then (" (IP: " + player.ip.slice(7) + ")") else "") + (if settings.modules.http.show_info and room.started and not (room.hostinfo.mode == 2 and player.pos > 1) then (" (Score:" + room.scores[player.name] + " LP:" + (if player.lp? then player.lp else room.hostinfo.start_lp) + ")") else ""),
            pos: player.pos
          ),
          istart: if room.started then (if settings.modules.http.show_info then ("Duel:" + room.duel_count + " " + (if room.changing_side then "Siding" else "Turn:" + (if room.turn? then room.turn else 0) + (if room.death then "/" + (if room.death > 0 then room.death - 1 else "Death") else ""))) else 'start') else 'wait'
        ), null, 2
        response.end(addCallback(u.query.callback, roomsjson))

    else if u.pathname == '/api/duellog' and settings.modules.tournament_mode.enabled
      if !(u.query.pass == settings.modules.tournament_mode.password)
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "[{name:'密码错误'}]"))
        return
      else
        response.writeHead(200)
        duellog = JSON.stringify duel_log.duel_log, null, 2
        response.end(addCallback(u.query.callback, duellog))

    else if u.pathname == '/api/archive.zip' and settings.modules.tournament_mode.enabled
      if !(u.query.pass == settings.modules.tournament_mode.password)
        response.writeHead(403)
        response.end("Invalid password.")
        return
      else
        try
          archive_name = moment().format('YYYY-MM-DD HH:mm:ss') + ".zip"
          archive_args = ["a", "-mx0", "-y", archive_name]
          check = false
          for replay in duel_log.duel_log
            check = true
            archive_args.push(replay.replay_filename)
          if !check
            response.writeHead(403)
            response.end("Duel logs not found.")
            return
          archive_process = spawn settings.modules.tournament_mode.replay_archive_tool, archive_args, {cwd: settings.modules.tournament_mode.replay_path}
          archive_process.on 'error', (err)=>
            response.writeHead(403)
            response.end("Failed packing replays. " + err)
            return
          archive_process.on 'exit', (code)=>
            fs.readFile(settings.modules.tournament_mode.replay_path + archive_name, (error, buffer)->
              if error
                response.writeHead(403)
                response.end("Failed sending replays. " + error)
                return
              else
                response.writeHead(200, { "Content-Type": "application/octet-stream", "Content-Disposition": "attachment" })
                response.end(buffer)
                return
            )
          archive_process.stdout.setEncoding 'utf8'
          archive_process.stdout.on 'data', (data)=>
            log.info "archive process: " + data
          archive_process.stderr.setEncoding 'utf8'
          archive_process.stderr.on 'data', (data)=>
            log.warn "archive error: " + data
        catch error
          response.writeHead(403)
          response.end("Failed reading replays. " + error)

    else if u.pathname == '/api/clearlog' and settings.modules.tournament_mode.enabled
      if !(u.query.pass == settings.modules.tournament_mode.password)
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "[{name:'密码错误'}]"))
        return
      else
        response.writeHead(200)
        duel_log.duel_log = []
        setting_save(duel_log)
        response.end(addCallback(u.query.callback, "[{name:'Success'}]"))

    else if _.startsWith(u.pathname, '/api/replay') and settings.modules.tournament_mode.enabled
      if !(u.query.pass == settings.modules.tournament_mode.password)
        response.writeHead(403)
        response.end("密码错误")
        return
      else
        getpath=u.pathname.split("/")
        filename=decodeURIComponent(getpath.pop())
        fs.readFile(settings.modules.tournament_mode.replay_path + filename, (error, buffer)->
          if error
            response.writeHead(404)
            response.end("未找到文件 " + filename)
          else
            response.writeHead(200, { "Content-Type": "application/octet-stream", "Content-Disposition": "attachment" })
            response.end(buffer)
          return
        )

    else if u.pathname == '/api/message'
      if !pass_validated
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['密码错误', 0]"))
        return

      if u.query.shout
        for room in ROOM_all when room and room.established
          ygopro.stoc_send_chat_to_room(room, u.query.shout, ygopro.constants.COLORS.YELLOW)
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['shout ok', '" + u.query.shout + "']"))

      else if u.query.stop
        if u.query.stop == 'false'
          u.query.stop = false
        setting_change(settings, 'modules:stop', u.query.stop)
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['stop ok', '" + u.query.stop + "']"))

      else if u.query.welcome
        setting_change(settings, 'modules:welcome', u.query.welcome)
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['welcome ok', '" + u.query.welcome + "']"))

      else if u.query.getwelcome
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['get ok', '" + settings.modules.welcome + "']"))

      else if u.query.loadtips
        load_tips()
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['loading tip', '" + settings.modules.tips.get + "']"))

      else if u.query.loaddialogues
        load_dialogues()
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['loading dialogues', '" + settings.modules.dialogues.get + "']"))

      else if u.query.ban
        ban_user(u.query.ban)
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['ban ok', '" + u.query.ban + "']"))

      else if u.query.death
        death_room_found = false
        for room in ROOM_all when room and room.established and room.started and !room.death and (u.query.death == "all" or u.query.death == room.port.toString())
          death_room_found = true
          if !room.changing_side and (!room.duel_count or room.turn)
            room.death = (if room.turn then room.turn + 4 else 5)
            ygopro.stoc_send_chat_to_room(room, "${death_start}", ygopro.constants.COLORS.BABYBLUE)   
          else
            if settings.modules.http.quick_death_rule
              room.death = -1
              ygopro.stoc_send_chat_to_room(room, "${death_start_quick}", ygopro.constants.COLORS.BABYBLUE)
            else
              room.death = 5
              ygopro.stoc_send_chat_to_room(room, "${death_start_siding}", ygopro.constants.COLORS.BABYBLUE)              
        response.writeHead(200)
        if death_room_found
          response.end(addCallback(u.query.callback, "['death ok', '" + u.query.death + "']"))
        else
          response.end(addCallback(u.query.callback, "['room not found', '" + u.query.death + "']"))

      else if u.query.deathcancel
        death_room_found = false
        for room in ROOM_all when room and room.established and room.started and room.death and (u.query.deathcancel == "all" or u.query.deathcancel == room.port.toString())
          death_room_found = true
          room.death = 0
          ygopro.stoc_send_chat_to_room(room, "${death_cancel}", ygopro.constants.COLORS.BABYBLUE)         
        response.writeHead(200)
        if death_room_found
          response.end(addCallback(u.query.callback, "['death cancel ok', '" + u.query.deathcancel + "']"))
        else
          response.end(addCallback(u.query.callback, "['room not found', '" + u.query.deathcancel + "']"))

      else
        response.writeHead(400)
        response.end()

    else
      response.writeHead(400)
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
    roomlist.init https_server, ROOM_all
    https_server.listen settings.modules.http.ssl.port
