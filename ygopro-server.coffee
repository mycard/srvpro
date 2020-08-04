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
_async = require('async')

# 三方库
_ = global._ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports())

request = require 'request'
axios = require 'axios'
qs = require "querystring"

bunyan = require 'bunyan'
log = global.log = bunyan.createLogger name: "mycard"

moment = global.moment = require 'moment'
moment.updateLocale('zh-cn', {
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

import_datas = global.import_datas = [
  "abuse_count",
  "ban_mc",
  "vpass",
  "rag",
  "rid",
  "is_post_watcher",
  "retry_count",
  "name",
  "pass",
  "name_vpass",
  "is_first",
  "lp",
  "card_count",
  "is_host",
  "pos",
  "surrend_confirm",
  "kick_count",
  "deck_saved",
  "main",
  "side",
  "side_interval",
  "side_tcount",
  "selected_preduel",
  "last_game_msg",
  "last_game_msg_title",
  "last_hint_msg",
  "start_deckbuf",
  "challonge_info",
  "ready_trap",
  "join_time",
  "arena_quit_free",
  "replays_sent"
]

merge = require 'deepmerge'

loadJSON = require('load-json-file').sync

util = require("util")

#heapdump = require 'heapdump'

# 配置
# 导入旧配置
if not fs.existsSync('./config')
  fs.mkdirSync('./config')
try
  oldconfig=loadJSON('./config.user.json')
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
  if oldconfig.modules
    if oldconfig.modules.tournament_mode and oldconfig.modules.tournament_mode.duel_log
      oldduellog = {}
      oldduellog.file = './config/duel_log.json'
      oldduellog.duel_log = oldconfig.modules.tournament_mode.duel_log
      fs.writeFileSync(oldduellog.file, JSON.stringify(oldduellog, null, 2))
      delete oldconfig.oldduellog
  oldbadwords={}
  if oldconfig.ban
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
  log.info e unless e.code == 'ENOENT'

setting_save = global.setting_save = (settings, callback) ->
  if !callback
    callback = (err) ->
      if(err)
        log.warn("setting save fail", err.toString())
  fs.writeFile(settings.file, JSON.stringify(settings, null, 2), callback)
  return

setting_change = global.setting_change = (settings, path, val, callback) ->
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
  setting_save(settings, callback)
  return

# 读取配置
default_config = loadJSON('./data/default_config.json')
if fs.existsSync('./config/config.json')
  try
    config = loadJSON('./config/config.json')
  catch e
    console.error("Failed reading config: ", e.toString())
    process.exit(1)
else
  config = {}

settings = global.settings = merge(default_config, config, { arrayMerge: (destination, source) -> source })

auth = global.auth = require './ygopro-auth.js'

#import old configs
imported = false
#reset http.quick_death_rule from true to 1
if settings.modules.http.quick_death_rule == true
  settings.modules.http.quick_death_rule = 1
  imported = true
#import the old redis port
if settings.modules.cloud_replay.redis_port
  settings.modules.cloud_replay.redis.port = settings.modules.cloud_replay.redis_port
  delete settings.modules.cloud_replay.redis_port
  imported = true
#import the old passwords to new admin user system
if settings.modules.http.password
  auth.add_user("olduser", settings.modules.http.password, true, {
        "get_rooms": true,
        "shout": true,
        "stop": true,
        "change_settings": true,
        "ban_user": true,
        "kick_user": true,
        "start_death": true
  })
  delete settings.modules.http.password
  imported = true
if settings.modules.tournament_mode.password
  auth.add_user("tournament", settings.modules.tournament_mode.password, true, {
        "duel_log": true,
        "download_replay": true,
        "clear_duel_log": true,
        "deck_dashboard_read": true,
        "deck_dashboard_write": true,
  })
  delete settings.modules.tournament_mode.password
  imported = true
if settings.modules.pre_util.password
  auth.add_user("pre", settings.modules.pre_util.password, true, {
        "pre_dashboard": true
  })
  delete settings.modules.pre_util.password
  imported = true
if settings.modules.update_util.password
  auth.add_user("update", settings.modules.update_util.password, true, {
        "update_dashboard": true
  })
  delete settings.modules.update_util.password
  imported = true
#import the old enable_priority hostinfo
if settings.hostinfo.enable_priority or settings.hostinfo.enable_priority == false
  if settings.hostinfo.enable_priority
    settings.hostinfo.duel_rule = 3
  else
    settings.hostinfo.duel_rule = 5
  delete settings.hostinfo.enable_priority
  imported = true
#import the old Challonge api key option
if settings.modules.challonge.api_key
  settings.modules.challonge.options.apiKey = settings.modules.challonge.api_key
  delete settings.modules.challonge.api_key
  imported = true
#import the old random_duel.blank_pass_match option
if settings.modules.random_duel.blank_pass_match == true
  settings.modules.random_duel.blank_pass_modes = {"S":true,"M":true,"T":false}
  delete settings.modules.random_duel.blank_pass_match
  imported = true
if settings.modules.random_duel.blank_pass_match == false
  settings.modules.random_duel.blank_pass_modes = {"S":true,"M":false,"T":false}
  delete settings.modules.random_duel.blank_pass_match
  imported = true
#finish
if imported
  setting_save(settings)

# 读取数据
default_data = loadJSON('./data/default_data.json')
try
  tips = global.tips = loadJSON('./config/tips.json')
catch
  tips = global.tips = default_data.tips
  setting_save(tips)
try
  dialogues = global.dialogues = loadJSON('./config/dialogues.json')
catch
  dialogues = global.dialogues = default_data.dialogues
  setting_save(dialogues)
try
  badwords = global.badwords = loadJSON('./config/badwords.json')
catch
  badwords = global.badwords = default_data.badwords
  setting_save(badwords)
try
  duel_log = global.duel_log = loadJSON('./config/duel_log.json')
catch
  duel_log = global.duel_log = default_data.duel_log
  setting_save(duel_log)
try
  chat_color = global.chat_color = loadJSON('./config/chat_color.json')
catch
  chat_color = global.chat_color = default_data.chat_color
  setting_save(chat_color)

try
  cppversion = parseInt(fs.readFileSync('ygopro/gframe/game.cpp', 'utf8').match(/PRO_VERSION = ([x\dABCDEF]+)/)[1], '16')
  setting_change(settings, "version", cppversion)
  log.info "ygopro version 0x"+settings.version.toString(16), "(from source code)"
catch
  #settings.version = settings.version_default
  log.info "ygopro version 0x"+settings.version.toString(16), "(from config)"
# load the lflist of current date
lflists = global.lflists = []
# expansions/lflist
try
  for list in fs.readFileSync('ygopro/expansions/lflist.conf', 'utf8').match(/!.*/g)
    date=list.match(/!([\d\.]+)/)
    continue unless date
    lflists.push({date: moment(list.match(/!([\d\.]+)/)[1], 'YYYY.MM.DD').utcOffset("-08:00"), tcg: list.indexOf('TCG') != -1})
catch
# lflist
try
  for list in fs.readFileSync('ygopro/lflist.conf', 'utf8').match(/!.*/g)
    date=list.match(/!([\d\.]+)/)
    continue unless date
    lflists.push({date: moment(list.match(/!([\d\.]+)/)[1], 'YYYY.MM.DD').utcOffset("-08:00"), tcg: list.indexOf('TCG') != -1})
catch

if settings.modules.cloud_replay.enabled
  redis = require 'redis'
  zlib = require 'zlib'
  redisdb = global.redisdb = redis.createClient(settings.modules.cloud_replay.redis)
  redisdb.on 'error', (err)->
    log.warn err
    return

if settings.modules.windbot.enabled
  windbots = global.windbots = loadJSON(settings.modules.windbot.botlist).windbots
  real_windbot_server_ip = global.real_windbot_server_ip = settings.modules.windbot.server_ip
  if !settings.modules.windbot.server_ip.includes("127.0.0.1")
    dns = require('dns')
    dns.lookup(settings.modules.windbot.server_ip,(err,addr) ->
      if(!err)
        real_windbot_server_ip = global.real_windbot_server_ip = addr
    )


if settings.modules.heartbeat_detection.enabled
  long_resolve_cards = global.long_resolve_cards = loadJSON('./data/long_resolve_cards.json')

if settings.modules.tournament_mode.enable_recover
  ReplayParser = global.ReplayParser = require "./Replay.js"

# 组件
ygopro = global.ygopro = require './ygopro.js'
roomlist = global.roomlist = require './roomlist.js' if settings.modules.http.websocket_roomlist

if settings.modules.i18n.auto_pick
  geoip = require('geoip-country-lite')

# cache users of mycard login
users_cache = {}

if settings.modules.mycard.enabled
  pgClient = require('pg').Client
  pg_client = global.pg_client = new pgClient(settings.modules.mycard.auth_database)
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
  if settings.modules.arena_mode.enabled and settings.modules.arena_mode.init_post.enabled
    request.post { url : settings.modules.arena_mode.init_post.url , qs : {
      ak: settings.modules.arena_mode.init_post.accesskey,
      arena: settings.modules.arena_mode.mode
    }}, (error, response, body)=>
      if error
        log.warn 'ARENA INIT POST ERROR', error
      else
        if response.statusCode >= 400
          log.warn 'ARENA INIT POST FAIL', response.statusCode, response.statusMessage, body
        #else
        #  log.info 'ARENA INIT POST OK', response.statusCode, response.statusMessage
      return

class ResolveData
  constructor: (@func) ->
  resolved: false
  resolve: (err, data) ->
    if @resolved
      return false
    @resolved = true
    @func(err, data)
    return true

if settings.modules.challonge.enabled
  challonge_module_name = 'challonge'
  if settings.modules.challonge.use_custom_module
    challonge_module_name = settings.modules.challonge.use_custom_module
  challonge = global.challonge = require(challonge_module_name).createClient(settings.modules.challonge.options)
  if settings.modules.challonge.cache_ttl
    challonge_cache = {
      participants: null
      matches: null
    }
  challonge_queue_callbacks = {
    participants: []
    matches: []
  }
  is_challonge_requesting = {
    participants: null
    matches: null
  }
  get_callback = (challonge_type, resolve_data) ->
    return ((err, data) ->
      if settings.modules.challonge.cache_ttl and !err and data
        challonge_cache[challonge_type] = data
      is_challonge_requesting[challonge_type] = null
      resolve_data.resolve(err, data)
      while challonge_queue_callbacks[challonge_type].length
        cur_resolve_data = challonge_queue_callbacks[challonge_type].splice(0, 1)[0]
        cur_resolve_data.resolve(err, data)
      return
    )
  replaced_index = (challonge_type) ->
    return (_data) ->
      resolve_data = new ResolveData(_data.callback)
      if settings.modules.challonge.cache_ttl and !_data.no_cache and challonge_cache[challonge_type]
        resolve_data.resolve(null, challonge_cache[challonge_type])
      else if is_challonge_requesting[challonge_type] and moment() - is_challonge_requesting[challonge_type] <= 5000
        challonge_queue_callbacks[challonge_type].push(resolve_data)
      else
        _data.callback = get_callback(challonge_type, resolve_data)
        is_challonge_requesting[challonge_type] = moment()
        try
          challonge[challonge_type].index(_data)
        catch err
          _data.callback(err, null)
      return
  for challonge_type in ["participants", "matches"]
    challonge[challonge_type]._index = replaced_index(challonge_type)
  challonge.matches._update = (_data) ->
    try
      challonge.matches.update(_data)
    catch err
      log.warn("Errored pushing scores to Challonge.", err)
    return
  refresh_challonge_cache = global.refresh_challonge_cache = () ->
    if settings.modules.challonge.cache_ttl
      challonge_cache.participants = null
      challonge_cache.matches = null
    return
  refresh_challonge_cache()
  # challonge.participants._index({
  #   id: settings.modules.challonge.tournament_id,
  #   callback: (() ->
  #     challonge.matches._index({
  #       id: settings.modules.challonge.tournament_id,
  #       callback: (() ->
  #         return
  #       )
  #     })
  #     return
  #   )
  # })
  if settings.modules.challonge.cache_ttl
    setInterval(refresh_challonge_cache, settings.modules.challonge.cache_ttl)

# 获取可用内存
memory_usage = global.memory_usage = 0
get_memory_usage = get_memory_usage = ()->
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
    memory_usage = global.memory_usage = percentUsed
    return
  return
get_memory_usage()
setInterval(get_memory_usage, 3000)

Cloud_replay_ids = global.Cloud_replay_ids = []

ROOM_all = global.ROOM_all = []
ROOM_players_oppentlist = global.ROOM_players_oppentlist = {}
ROOM_players_banned = global.ROOM_players_banned = []
ROOM_players_scores = global.ROOM_players_scores = {}
ROOM_connected_ip = global.ROOM_connected_ip = {}
ROOM_bad_ip = global.ROOM_bad_ip = {}

# ban a user manually and permanently
ban_user = global.ban_user = (name, callback) ->
  settings.ban.banned_user.push(name)
  setting_save(settings)
  bad_ip = []
  _async.each(ROOM_all, (room, done)-> 
    if !(room and room.established)
      done()
      return
    _async.each(["players", "watchers"], (player_type, _done)->
      _async.each(room[player_type], (player, __done)->
        if player and (player.name == name or bad_ip.indexOf(player.ip) != -1)
          bad_ip.push(player.ip)
          ROOM_bad_ip[bad_ip]=99
          settings.ban.banned_ip.push(player.ip)
          ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
          CLIENT_send_replays(player, room)
          CLIENT_kick(player)
        __done()
      , _done)
    , done)
  , callback)
  return

# automatically ban user to use random duel
ROOM_ban_player = global.ROOM_ban_player = (name, ip, reason, countadd = 1)->
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

ROOM_kick = (name, callback)->
  found = false
  _async.each(ROOM_all, (room, done)->
    if !(room and room.established and (name == "all" or name == room.process_pid.toString() or name == room.name))
      done()
      return
    found = true
    room.termiate()
    done()
  , (err)->
    callback(null, found)
    return
  )


ROOM_player_win = global.ROOM_player_win = (name)->
  if !ROOM_players_scores[name]
    ROOM_players_scores[name]={win:0, lose:0, flee:0, combo:0}
  ROOM_players_scores[name].win = ROOM_players_scores[name].win + 1
  ROOM_players_scores[name].combo = ROOM_players_scores[name].combo + 1
  return

ROOM_player_lose = global.ROOM_player_lose = (name)->
  if !ROOM_players_scores[name]
    ROOM_players_scores[name]={win:0, lose:0, flee:0, combo:0}
  ROOM_players_scores[name].lose = ROOM_players_scores[name].lose + 1
  ROOM_players_scores[name].combo = 0
  return

ROOM_player_flee = global.ROOM_player_flee = (name)->
  if !ROOM_players_scores[name]
    ROOM_players_scores[name]={win:0, lose:0, flee:0, combo:0}
  ROOM_players_scores[name].flee = ROOM_players_scores[name].flee + 1
  ROOM_players_scores[name].combo = 0
  return

ROOM_player_get_score = global.ROOM_player_get_score = (player)->
  name = player.name_vpass
  score = ROOM_players_scores[name] 
  if !score
    return "#{player.name} ${random_score_blank}"
  total = score.win + score.lose
  if score.win < 2 and total < 3
    return "#{player.name} ${random_score_not_enough}"
  if score.combo >= 2
    return "${random_score_part1}#{player.name} ${random_score_part2} #{Math.ceil(score.win/total*100)}${random_score_part3} #{Math.ceil(score.flee/total*100)}${random_score_part4_combo}#{score.combo}${random_score_part5_combo}"
    #return player.name + " 的今日战绩：胜率" + Math.ceil(score.win/total*100) + "%，逃跑率" + Math.ceil(score.flee/total*100) + "%，" + score.combo + "连胜中！"
  else
    return "${random_score_part1}#{player.name} ${random_score_part2} #{Math.ceil(score.win/total*100)}${random_score_part3} #{Math.ceil(score.flee/total*100)}${random_score_part4}"
  return

if settings.modules.random_duel.post_match_scores
  setInterval(()->
    scores_pair = _.pairs ROOM_players_scores
    scores_by_lose = _.sortBy(scores_pair, (score)-> return score[1].lose).reverse() # 败场由高到低
    scores_by_win = _.sortBy(scores_by_lose, (score)-> return score[1].win).reverse() # 然后胜场由低到高，再逆转，就是先排胜场再排败场
    scores = _.first(scores_by_win, 10)
    #log.info scores
    request.post { url : settings.modules.random_duel.post_match_scores , form : {
      accesskey: settings.modules.random_duel.post_match_accesskey,
      rank: JSON.stringify(scores)
    }}, (error, response, body)=>
      if error
        log.warn 'RANDOM SCORE POST ERROR', error
      else
        if response.statusCode != 204 and response.statusCode != 200
          log.warn 'RANDOM SCORE POST FAIL', response.statusCode, response.statusMessage, body
        #else
        #  log.info 'RANDOM SCORE POST OK', response.statusCode, response.statusMessage
      return
    return
  , 60000)

ROOM_find_or_create_by_name = global.ROOM_find_or_create_by_name = (name, player_ip)->
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

ROOM_find_or_create_random = global.ROOM_find_or_create_random = (type, player_ip)->
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
    return room and room.random_type != '' and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and !room.windbot and
    ((type == '' and
      (room.random_type == settings.modules.random_duel.default_type or
        settings.modules.random_duel.blank_pass_modes[room.random_type])) or
      room.random_type == type) and
    room.get_playing_player().length < max_player and
    (settings.modules.random_duel.no_rematch_check or room.get_host() == null or
    room.get_host().ip != ROOM_players_oppentlist[player_ip]) and
    (playerbanned == room.deprecated or type == 'T')
  if result
    result.welcome = '${random_duel_enter_room_waiting}'
    #log.info 'found room', player_name
  else if memory_usage < 90
    type = if type then type else settings.modules.random_duel.default_type
    name = type + ',RANDOM#' + Math.floor(Math.random() * 100000)
    result = new Room(name)
    result.random_type = type
    result.max_player = max_player
    result.welcome = '${random_duel_enter_room_new}'
    result.deprecated = playerbanned
    #log.info 'create room', player_name, name
  else
    return null
  if result.random_type=='S' then result.welcome2 = '${random_duel_enter_room_single}'
  if result.random_type=='M' then result.welcome2 = '${random_duel_enter_room_match}'
  if result.random_type=='T' then result.welcome2 = '${random_duel_enter_room_tag}'
  return result

ROOM_find_or_create_ai = global.ROOM_find_or_create_ai = (name)->
  if name == ''
    name = 'AI'
  namea = name.split('#')
  uname = name.toUpperCase()
  if room = ROOM_find_by_name(name)
    return room
  else if uname == 'AI'
    windbot = _.sample _.filter windbots, (w)->
      !w.hidden
    name = 'AI#' + Math.floor(Math.random() * 100000)
  else if namea.length>1
    ainame = namea[namea.length-1]
    windbot = _.sample _.filter windbots, (w)->
      w.name == ainame or w.deck == ainame
    if !windbot
      return { "error": "${windbot_deck_not_found}" }
    name = namea[0].toUpperCase() + '#N' + Math.floor(Math.random() * 100000)
  else
    windbot = _.sample _.filter windbots, (w)->
      !w.hidden
    name = name + '#' + Math.floor(Math.random() * 10000)
  if name.replace(/[^\x00-\xff]/g,"00").length>20
    log.info "long ai name", name
    return { "error": "${windbot_name_too_long}" }
  result = new Room(name)
  result.windbot = windbot
  result.private = true
  return result

ROOM_find_by_name = global.ROOM_find_by_name = (name)->
  result = _.find ROOM_all, (room)->
    return room and room.name == name
  return result

ROOM_find_by_title = global.ROOM_find_by_title = (title)->
  result = _.find ROOM_all, (room)->
    return room and room.title == title
  return result

ROOM_find_by_port = global.ROOM_find_by_port = (port)->
  _.find ROOM_all, (room)->
    return room and room.port == port

ROOM_find_by_pid = global.ROOM_find_by_pid = (pid)->
  _.find ROOM_all, (room)->
    return room and room.process_pid == pid

ROOM_validate = global.ROOM_validate = (name)->
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

ROOM_unwelcome = global.ROOM_unwelcome = (room, bad_player, reason)->
  return unless room
  for player in room.players
    if player and player == bad_player
      ygopro.stoc_send_chat(player, "${unwelcome_warn_part1}#{reason}${unwelcome_warn_part2}", ygopro.constants.COLORS.RED)
    else if player and player.pos!=7 and player != bad_player
      player.flee_free=true
      ygopro.stoc_send_chat(player, "${unwelcome_tip_part1}#{reason}${unwelcome_tip_part2}", ygopro.constants.COLORS.BABYBLUE)
  return

CLIENT_kick = global.CLIENT_kick = (client) ->
  if !client
    return false
  client.system_kicked = true
  if settings.modules.reconnect.enabled and client.closed
    if client.server and !client.had_new_reconnection
      room = ROOM_all[client.rid]
      if room
        room.disconnect(client)
      else
        SERVER_kick(client.server)
  else
    client.destroy()
  return true

SERVER_kick = global.SERVER_kick = (server) ->
  if !server
    return false
  server.system_kicked = true
  server.destroy()
  return true

release_disconnect = global.release_disconnect = (dinfo, reconnected) ->
  if dinfo.old_client and !reconnected
    dinfo.old_client.destroy()
  if dinfo.old_server and !reconnected
    SERVER_kick(dinfo.old_server)
  clearTimeout(dinfo.timeout)
  return

CLIENT_get_authorize_key = global.CLIENT_get_authorize_key = (client) ->
  if !settings.modules.mycard.enabled and client.vpass
    return client.name_vpass
  else if settings.modules.mycard.enabled or settings.modules.tournament_mode.enabled or settings.modules.challonge.enabled or client.is_local
    return client.name
  else
    return client.ip + ":" + client.name

CLIENT_reconnect_unregister = global.CLIENT_reconnect_unregister = (client, reconnected, exact) ->
  if !settings.modules.reconnect.enabled
    return false
  if disconnect_list[CLIENT_get_authorize_key(client)]
    if exact and disconnect_list[CLIENT_get_authorize_key(client)].old_client != client
      return false
    release_disconnect(disconnect_list[CLIENT_get_authorize_key(client)], reconnected)
    delete disconnect_list[CLIENT_get_authorize_key(client)]
    return true
  return false

CLIENT_reconnect_register = global.CLIENT_reconnect_register = (client, room_id, error) ->
  room = ROOM_all[room_id]
  if client.had_new_reconnection
    return false
  if !settings.modules.reconnect.enabled or !room or client.system_kicked or client.flee_free or disconnect_list[CLIENT_get_authorize_key(client)] or client.is_post_watcher or !CLIENT_is_player(client, room) or room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or room.windbot or (settings.modules.reconnect.auto_surrender_after_disconnect and room.hostinfo.mode != 1) or (room.random_type and room.get_disconnected_count() > 1)
    return false
  # for player in room.players
  #   if player != client and CLIENT_get_authorize_key(player) == CLIENT_get_authorize_key(client)
  #     return false # some issues may occur in this case, so return false
  dinfo = {
    room_id: room_id,
    old_client: client,
    old_server: client.server,
    deckbuf: client.start_deckbuf
  }
  tmot = setTimeout(() ->
    room.disconnect(client, error)
    #SERVER_kick(dinfo.old_server)
    return
  , settings.modules.reconnect.wait_time)
  dinfo.timeout = tmot
  disconnect_list[CLIENT_get_authorize_key(client)] = dinfo
  #console.log("#{client.name} ${disconnect_from_game}")
  ygopro.stoc_send_chat_to_room(room, "#{client.name} ${disconnect_from_game}" + if error then ": #{error}" else '')
  if client.time_confirm_required
    client.time_confirm_required = false
    ygopro.ctos_send(client.server, 'TIME_CONFIRM')
  if settings.modules.reconnect.auto_surrender_after_disconnect and room.duel_stage == ygopro.constants.DUEL_STAGE.DUELING
    ygopro.ctos_send(client.server, 'SURRENDER')
  return true

CLIENT_import_data = global.CLIENT_import_data = (client, old_client, room) ->
  for player,index in room.players
    if player == old_client
      room.players[index] = client
      break
  room.dueling_players[old_client.pos] = client
  if room.waiting_for_player == old_client
    room.waiting_for_player = client
  if room.waiting_for_player2 == old_client
    room.waiting_for_player2 = client
  if room.selecting_tp == old_client
    room.selecting_tp = client
  if room.determine_firstgo == old_client
    room.determine_firstgo = client
  for key in import_datas
    client[key] = old_client[key]
  old_client.had_new_reconnection = true
  return

SERVER_clear_disconnect = global.SERVER_clear_disconnect = (server) ->
  return false unless settings.modules.reconnect.enabled
  for k,v of disconnect_list
    if v and server == v.old_server
      release_disconnect(v)
      delete disconnect_list[k]
      return true
  return false

ROOM_clear_disconnect = global.ROOM_clear_disconnect = (room_id) ->
  return false unless settings.modules.reconnect.enabled
  for k,v of disconnect_list
    if v and room_id == v.room_id
      release_disconnect(v)
      delete disconnect_list[k]
      return true
  return false

CLIENT_is_player = global.CLIENT_is_player = (client, room) ->
  is_player = false
  for player in room.players
    if client == player
      is_player = true
      break
  return is_player and client.pos <= 3

CLIENT_is_able_to_reconnect = global.CLIENT_is_able_to_reconnect = (client, deckbuf) ->
  unless settings.modules.reconnect.enabled
    return false
  if client.system_kicked
    return false
  disconnect_info = disconnect_list[CLIENT_get_authorize_key(client)]
  unless disconnect_info
    return false
  room = ROOM_all[disconnect_info.room_id]
  if !room
    CLIENT_reconnect_unregister(client)
    return false
  if deckbuf and !_.isEqual(deckbuf, disconnect_info.deckbuf)
    return false
  return true

CLIENT_get_kick_reconnect_target = global.CLIENT_get_kick_reconnect_target = (client, deckbuf) ->
  for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and !room.windbot
    for player in room.get_playing_player() when !player.closed and player.name == client.name and (settings.modules.challonge.enabled or player.pass == client.pass) and (settings.modules.mycard.enabled or settings.modules.tournament_mode.enabled or player.ip == client.ip or (client.vpass and client.vpass == player.vpass)) and (!deckbuf or _.isEqual(player.start_deckbuf, deckbuf))
      return player
  return null

CLIENT_is_able_to_kick_reconnect = global.CLIENT_is_able_to_kick_reconnect = (client, deckbuf) ->
  unless settings.modules.reconnect.enabled and settings.modules.reconnect.allow_kick_reconnect
    return false
  if !CLIENT_get_kick_reconnect_target(client, deckbuf)
    return false
  return true

CLIENT_send_pre_reconnect_info = global.CLIENT_send_pre_reconnect_info = (client, room, old_client) ->
  ygopro.stoc_send_chat(client, "${pre_reconnecting_to_room}", ygopro.constants.COLORS.BABYBLUE)
  ygopro.stoc_send(client, 'JOIN_GAME', room.join_game_buffer)
  req_pos = old_client.pos
  if old_client.is_host
    req_pos += 0x10
  ygopro.stoc_send(client, 'TYPE_CHANGE', {
    type: req_pos
  })
  for player in room.players
    ygopro.stoc_send(client, 'HS_PLAYER_ENTER', {
      name: player.name,
      pos: player.pos,
    })
  return

CLIENT_send_reconnect_info = global.CLIENT_send_reconnect_info = (client, server, room) ->
  client.reconnecting = true
  ygopro.stoc_send_chat(client, "${reconnecting_to_room}", ygopro.constants.COLORS.BABYBLUE)
  switch room.duel_stage
    when ygopro.constants.DUEL_STAGE.FINGER
      ygopro.stoc_send(client, 'DUEL_START')
      if (room.hostinfo.mode != 2 or client.pos == 0 or client.pos == 2) and !client.selected_preduel
        ygopro.stoc_send(client, 'SELECT_HAND')
      client.reconnecting = false
      break
    when ygopro.constants.DUEL_STAGE.FIRSTGO
      ygopro.stoc_send(client, 'DUEL_START')
      if client == room.selecting_tp # and !client.selected_preduel
        ygopro.stoc_send(client, 'SELECT_TP')
      client.reconnecting = false
      break
    when ygopro.constants.DUEL_STAGE.SIDING
      ygopro.stoc_send(client, 'DUEL_START')
      if !client.selected_preduel
        ygopro.stoc_send(client, 'CHANGE_SIDE')
      client.reconnecting = false
      break
    else
      ygopro.ctos_send(server, 'REQUEST_FIELD')
      break
  return

CLIENT_pre_reconnect = global.CLIENT_pre_reconnect = (client) ->
  if CLIENT_is_able_to_reconnect(client)
    dinfo = disconnect_list[CLIENT_get_authorize_key(client)]
    client.pre_reconnecting = true
    client.pos = dinfo.old_client.pos
    client.setTimeout(300000)
    CLIENT_send_pre_reconnect_info(client, ROOM_all[dinfo.room_id], dinfo.old_client)
  else if CLIENT_is_able_to_kick_reconnect(client)
    player = CLIENT_get_kick_reconnect_target(client)
    client.pre_reconnecting = true
    client.pos = player.pos
    client.setTimeout(300000)
    CLIENT_send_pre_reconnect_info(client, ROOM_all[player.rid], player)
  return

CLIENT_reconnect = global.CLIENT_reconnect = (client) ->
  if !CLIENT_is_able_to_reconnect(client)
    ygopro.stoc_send_chat(client, "${reconnect_failed}", ygopro.constants.COLORS.RED)
    CLIENT_kick(client)
    return
  client.pre_reconnecting = false
  dinfo = disconnect_list[CLIENT_get_authorize_key(client)]
  room = ROOM_all[dinfo.room_id]
  current_old_server = client.server
  client.server = dinfo.old_server
  client.server.client = client
  dinfo.old_client.server = null
  current_old_server.client = null
  current_old_server.had_new_reconnection = true
  SERVER_kick(current_old_server)
  client.established = true
  client.pre_establish_buffers = []
  if room.random_type or room.arena
    room.last_active_time = moment()
  CLIENT_import_data(client, dinfo.old_client, room)
  CLIENT_send_reconnect_info(client, client.server, room)
  #console.log("#{client.name} ${reconnect_to_game}")
  ygopro.stoc_send_chat_to_room(room, "#{client.name} ${reconnect_to_game}")
  CLIENT_reconnect_unregister(client, true)
  return

CLIENT_kick_reconnect = global.CLIENT_kick_reconnect = (client, deckbuf) ->
  if !CLIENT_is_able_to_kick_reconnect(client)
    ygopro.stoc_send_chat(client, "${reconnect_failed}", ygopro.constants.COLORS.RED)
    CLIENT_kick(client)
    return
  client.pre_reconnecting = false
  player = CLIENT_get_kick_reconnect_target(client, deckbuf)
  room = ROOM_all[player.rid]
  current_old_server = client.server
  client.server = player.server
  client.server.client = client
  ygopro.stoc_send_chat(player, "${reconnect_kicked}", ygopro.constants.COLORS.RED)
  player.server = null
  player.had_new_reconnection = true
  CLIENT_kick(player)
  current_old_server.client = null
  current_old_server.had_new_reconnection = true
  SERVER_kick(current_old_server)
  client.established = true
  client.pre_establish_buffers = []
  if room.random_type or room.arena
    room.last_active_time = moment()
  CLIENT_import_data(client, player, room)
  CLIENT_send_reconnect_info(client, client.server, room)
  #console.log("#{client.name} ${reconnect_to_game}")
  ygopro.stoc_send_chat_to_room(room, "#{client.name} ${reconnect_to_game}")
  CLIENT_reconnect_unregister(client, true)
  return

if settings.modules.reconnect.enabled
  disconnect_list = {} # {old_client, old_server, room_id, timeout, deckbuf}

CLIENT_heartbeat_unregister = global.CLIENT_heartbeat_unregister = (client) ->
  if !settings.modules.heartbeat_detection.enabled or !client.heartbeat_timeout
    return false
  clearTimeout(client.heartbeat_timeout)
  delete client.heartbeat_timeout
  #log.info(2, client.name)
  return true

CLIENT_heartbeat_register = global.CLIENT_heartbeat_register = (client, send) ->
  if !settings.modules.heartbeat_detection.enabled or client.closed or client.is_post_watcher or client.pre_reconnecting or client.reconnecting or client.waiting_for_last or client.pos > 3 or client.heartbeat_protected
    return false
  if client.heartbeat_timeout
    CLIENT_heartbeat_unregister(client)
  client.heartbeat_responsed = false
  if send
    ygopro.stoc_send(client, "TIME_LIMIT", {
      player: 0,
      left_time: 0
    })
    ygopro.stoc_send(client, "TIME_LIMIT", {
      player: 1,
      left_time: 0
    })
  client.heartbeat_timeout = setTimeout(() ->
    CLIENT_heartbeat_unregister(client)
    client.destroy() unless client.closed or client.heartbeat_responsed
    return
  , settings.modules.heartbeat_detection.wait_time)
  #log.info(1, client.name)
  return true

CLIENT_is_banned_by_mc = global.CLIENT_is_banned_by_mc = (client) ->
  return client.ban_mc and client.ban_mc.banned and moment().isBefore(client.ban_mc.until)

CLIENT_send_replays = global.CLIENT_send_replays = (client, room) ->
  return false unless settings.modules.replay_delay and not (settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.block_replay_to_player) and room.replays.length and room.hostinfo.mode == 1 and !client.replays_sent and !client.closed
  client.replays_sent = true
  i = 0
  for buffer in room.replays
    ++i
    if buffer
      ygopro.stoc_send_chat(client, "${replay_hint_part1}" + i + "${replay_hint_part2}", ygopro.constants.COLORS.BABYBLUE)
      ygopro.stoc_send(client, "REPLAY", buffer)
  return true

SOCKET_flush_data = global.SOCKET_flush_data = (sk, datas) ->
  if !sk or sk.closed
    return false
  for buffer in datas
    sk.write(buffer)
  datas.splice(0, datas.length)
  return true

getSeedTimet = global.getSeedTimet = (count) ->
  ret = []
  for i in [0...count]
    curTime = null
    while !curTime or _.any(ret, (time) ->
      return time == curTime.unix()
    )
      curTime = moment()
      offset = Math.floor(Math.random() * 240) - 120
      if offset > 0
        curTime = curTime.add(offset, "s")
      else if offset < 0
        curTime = curTime.subtract(-offset, "s")
    ret.push(curTime.unix())
  ret.sort((a, b) ->
    return a - b
  )
  return ret

class Room
  constructor: (name, @hostinfo) ->
    @name = name
    #@alive = true
    @players = []
    @player_datas = []
    @status = 'starting'
    #@started = false
    @established = false
    @watcher_buffers = []
    @recorder_buffers = []
    @cloud_replay_id = Math.floor(Math.random()*100000000)
    @watchers = []
    @random_type = ''
    @welcome = ''
    @scores = {}
    @decks = {}
    @duel_count = 0
    @death = 0
    @turn = 0
    @duel_stage = ygopro.constants.DUEL_STAGE.BEGIN
    @replays = []
    @first_list = []
    ROOM_all.push this

    @hostinfo ||= JSON.parse(JSON.stringify(settings.hostinfo))
    delete @hostinfo.comment
    if lflists.length
      if @hostinfo.rule == 1 and @hostinfo.lflist == 0
        @hostinfo.lflist = _.findIndex lflists, (list)-> list.tcg
    else
      @hostinfo.lflist =  -1

    if name[0...2] == 'M#'
      @hostinfo.mode = 1
    else if name[0...2] == 'T#'
      @hostinfo.mode = 2
      @hostinfo.start_lp = 16000
    else if name[0...3] == 'AI#'
      @hostinfo.rule = 2
      @hostinfo.lflist = -1
      @hostinfo.time_limit = 999

    else if (param = name.match /^(\d)(\d)(T|F)(T|F)(T|F)(\d+),(\d+),(\d+)/i)
      @hostinfo.rule = parseInt(param[1])
      @hostinfo.mode = parseInt(param[2])
      @hostinfo.duel_rule = (if param[3] == 'T' then 3 else 4)
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
        @hostinfo.lflist = 0

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

      if (rule.match /(^|，|,)(IGPRIORITY|PR)(，|,|$)/) # deprecated
        @hostinfo.duel_rule = 4

      if (param = rule.match /(^|，|,)(DUELRULE|MR)(\d+)(，|,|$)/)
        duel_rule = parseInt(param[3])
        if duel_rule and duel_rule > 0 and duel_rule <= 5
          @hostinfo.duel_rule = duel_rule

      if (rule.match /(^|，|,)(NOWATCH|NW)(，|,|$)/)
        @hostinfo.no_watch = true

      if (param = rule.match /(^|，|,)(DEATH|DH)(\d*)(，|,|$)/)
        death_time = parseInt(param[3])
        if death_time and death_time > 0
          @hostinfo.auto_death = death_time
        else
          @hostinfo.auto_death = 40

      if settings.modules.tournament_mode.enable_recover and (param = rule.match /(^|，|,)(RC|RECOVER)(\d*)T(\d*)(，|,|$)/)
        @recovered = true
        @recovering = true
        @recover_from_turn = parseInt(param[4])
        duel_log_id = parseInt(param[3])
        @recover_duel_log = _.find(duel_log.duel_log, (duel) ->
          return duel.id == duel_log_id and duel.roommode != 2 and duel.players[0].deck
        )
        if !@recover_duel_log || !fs.existsSync(settings.modules.tournament_mode.replay_path + @recover_duel_log.replay_filename)
          @error = "${cloud_replay_no}"
          return
        @recover_replay = ReplayParser.fromFile(settings.modules.tournament_mode.replay_path + @recover_duel_log.replay_filename)
        @recover_buffers = [[], [], [], []]
        @welcome = "${recover_hint}"

    @hostinfo.replay_mode = 0 # 0x1: Save the replays in file. 0x2: Block the replays to observers.

    if settings.modules.tournament_mode.enabled
      @hostinfo.replay_mode |= 0x1
    if (settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.block_replay_to_player) or (@hostinfo.mode == 1 and settings.modules.replay_delay)
      @hostinfo.replay_mode |= 0x2

    param = [0, @hostinfo.lflist, @hostinfo.rule, @hostinfo.mode, @hostinfo.duel_rule,
      (if @hostinfo.no_check_deck then 'T' else 'F'), (if @hostinfo.no_shuffle_deck then 'T' else 'F'),
      @hostinfo.start_lp, @hostinfo.start_hand, @hostinfo.draw_count, @hostinfo.time_limit, @hostinfo.replay_mode]

    if @recovered
      param.push(@recover_replay.header.seed)
      seeds = getSeedTimet(2)
      param.push(seeds[i]) for i in [0...2]
    else
      seeds = getSeedTimet(3)
      param.push(seeds[i]) for i in [0...3]

    try
      @process = spawn './ygopro', param, {cwd: 'ygopro'}
      @process_pid = @process.pid
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
          @send_replays()
          @process.kill()
        return
    catch
      @error = "${create_room_failed}"
  delete: ->
    return if @deleted
    #log.info 'room-delete', this.name, ROOM_all.length
    score_array=[]
    for name, score of @scores
      score_form = { name: name.split('$')[0], score: score, deck: null, name_vpass: name }
      if @decks[name]
        score_form.deck = @decks[name]
      score_array.push score_form
    if settings.modules.random_duel.record_match_scores and @random_type == 'M'
      if score_array.length == 2
        if score_array[0].score != score_array[1].score
          if score_array[0].score > score_array[1].score
            ROOM_player_win(score_array[0].name_vpass)
            ROOM_player_lose(score_array[1].name_vpass)
          else
            ROOM_player_win(score_array[1].name_vpass)
            ROOM_player_lose(score_array[0].name_vpass)
      if score_array.length == 1 # same name
          #log.info score_array[0].name
          ROOM_player_win(score_array[0].name_vpass)
          ROOM_player_lose(score_array[0].name_vpass)
    if settings.modules.arena_mode.enabled and @arena
      #log.info 'SCORE', score_array, @start_time
      end_time = moment().format()
      if !@start_time
        @start_time = end_time
      if score_array.length != 2
        if !score_array[0]
          score_array[0] = { name: null, score: -5, deck: null }
        if !score_array[1]
          score_array[1] = { name: null, score: -5, deck: null }
        score_array[0].score = -5
        score_array[1].score = -5
      formatted_replays = []
      for repbuf in @replays when repbuf
        formatted_replays.push(repbuf.toString("base64"))
      request.post { url : settings.modules.arena_mode.post_score , form : {
        accesskey: settings.modules.arena_mode.accesskey,
        usernameA: score_array[0].name,
        usernameB: score_array[1].name,
        userscoreA: score_array[0].score,
        userscoreB: score_array[1].score,
        userdeckA: score_array[0].deck,
        userdeckB: score_array[1].deck,
        first: JSON.stringify(@first_list),
        replays: JSON.stringify(formatted_replays),
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

    if settings.modules.challonge.enabled and @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and @hostinfo.mode != 2 and !@kicked
      room_name = @name
      challonge.matches._update({
        id: settings.modules.challonge.tournament_id,
        matchId: @challonge_info.id,
        match: @get_challonge_score(),
        callback: (err, data) ->
          if err
            log.warn("Errored pushing scores to Challonge.", room_name, err)
          else
            refresh_challonge_cache()
          return
      })
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
        player_ips.push(player.key)
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
        if !log_rep_id and !settings.modules.cloud_replay.never_expire
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
    if settings.modules.reconnect.enabled
      ROOM_clear_disconnect(index)
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

  get_disconnected_count: ->
    if !settings.modules.reconnect.enabled
      return 0
    found = 0
    for player in @get_playing_player() when player.closed
      found++
    return found

  get_challonge_score: ->
    if !settings.modules.challonge.enabled or @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or @hostinfo.mode == 2
      return null
    challonge_duel_log = {}
    if @scores[@dueling_players[0].name_vpass] > @scores[@dueling_players[1].name_vpass]
      challonge_duel_log.winnerId = @dueling_players[0].challonge_info.id
    else if @scores[@dueling_players[0].name_vpass] < @scores[@dueling_players[1].name_vpass]
      challonge_duel_log.winnerId = @dueling_players[1].challonge_info.id
    else
      challonge_duel_log.winnerId = "tie"
    if settings.modules.challonge.post_detailed_score
      if @dueling_players[0].challonge_info.id == @challonge_info.player1Id and @dueling_players[1].challonge_info.id == @challonge_info.player2Id
        challonge_duel_log.scoresCsv = @scores[@dueling_players[0].name_vpass] + "-" + @scores[@dueling_players[1].name_vpass]
      else if @dueling_players[1].challonge_info.id == @challonge_info.player1Id and @dueling_players[0].challonge_info.id == @challonge_info.player2Id
        challonge_duel_log.scoresCsv = @scores[@dueling_players[1].name_vpass] + "-" + @scores[@dueling_players[0].name_vpass]
      else
        challonge_duel_log.scoresCsv = "0-0"
        log.warn("Score mismatch.", @name)
    else
      if challonge_duel_log.winnerId == @challonge_info.player1Id
        challonge_duel_log.scoresCsv = "1-0"
      else if challonge_duel_log.winnerId == @challonge_info.player2Id
        challonge_duel_log.scoresCsv = "0-1"
      else
        challonge_duel_log.scoresCsv = "0-0"
    return challonge_duel_log

  get_old_hostinfo: () -> # Just for supporting websocket roomlist in old MyCard client....
    ret = _.clone(@hostinfo)
    ret.enable_priority = (@hostinfo.duel_rule != 5)
    return ret

  send_replays: () ->
    return false unless settings.modules.replay_delay and @replays.length and @hostinfo.mode == 1
    for player in @players when player
      CLIENT_send_replays(player, this)
    for player in @watchers when player
      CLIENT_send_replays(player, this)
    return true

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
    client.join_time = moment()
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
      roomlist.update(this) if !@windbot and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and settings.modules.http.websocket_roomlist
      client.server.connect @port, '127.0.0.1', ->
        client.server.write buffer for buffer in client.pre_establish_buffers
        client.established = true
        client.pre_establish_buffers = []
        return
    return

  disconnect: (client, error)->
    if client.had_new_reconnection
      return
    if client.is_post_watcher
      ygopro.stoc_send_chat_to_room this, "#{client.name} ${quit_watch}" + if error then ": #{error}" else ''
      index = _.indexOf(@watchers, client)
      @watchers.splice(index, 1) unless index == -1
      #client.room = null
      SERVER_kick(client.server)
    else
      #log.info(client.name, @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN, @disconnector, @random_type, @players.length)
      if @arena and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and @disconnector != 'server' and !@arena_score_handled
        if settings.modules.arena_mode.punish_quit_before_match and @players.length == 2 and !client.arena_quit_free
          for player in @players when player.pos != 7
            @scores[player.name_vpass] = 0
          @scores[client.name_vpass] = -9
        else
          for player in @players when player.pos != 7
            @scores[player.name_vpass] = -5
          if @players.length == 2 and !client.arena_quit_free
            @scores[client.name_vpass] = -9
        @arena_score_handled = true
      index = _.indexOf(@players, client)
      @players.splice(index, 1) unless index == -1
      if @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and @disconnector != 'server' and client.pos < 4
        @finished = true
        if !@finished_by_death
          @scores[client.name_vpass] = -9
          if @random_type and not client.flee_free and (!settings.modules.reconnect.enabled or @get_disconnected_count() == 0)
            ROOM_ban_player(client.name, client.ip, "${random_ban_reason_flee}")
            if settings.modules.random_duel.record_match_scores and @random_type == 'M'
              ROOM_player_flee(client.name_vpass)
      if @players.length and !(@windbot and client.is_host) and !(@arena and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and client.pos <= 3)
        left_name = (if settings.modules.hide_name and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN then "********" else client.name)
        ygopro.stoc_send_chat_to_room this, "#{left_name} ${left_game}" + if error then ": #{error}" else ''
        roomlist.update(this) if !@windbot and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and settings.modules.http.websocket_roomlist
        #client.room = null
      else
        @send_replays()
        @process.kill()
        #client.room = null
        this.delete()
      if !CLIENT_reconnect_unregister(client, false, true)
        SERVER_kick(client.server)
    return

  start_death: () ->
    if @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or @death
      return false
    oppo_pos = if @hostinfo.mode == 2 then 2 else 1
    if @duel_stage == ygopro.constants.DUEL_STAGE.DUELING
      switch settings.modules.http.quick_death_rule
        when 3
          @death = -2
          ygopro.stoc_send_chat_to_room(this, "${death_start_phase}", ygopro.constants.COLORS.BABYBLUE)
        else
          @death = (if @turn then @turn + 4 else 5)
          ygopro.stoc_send_chat_to_room(this, "${death_start}", ygopro.constants.COLORS.BABYBLUE)
    else                                           # Extra duel started in siding
      switch settings.modules.http.quick_death_rule
        when 2,3
          if @scores[@dueling_players[0].name_vpass] == @scores[@dueling_players[oppo_pos].name_vpass]
            if settings.modules.http.quick_death_rule == 3
              @death = -1
              ygopro.stoc_send_chat_to_room(this, "${death_start_quick}", ygopro.constants.COLORS.BABYBLUE)
            else
              @death = 5
              ygopro.stoc_send_chat_to_room(this, "${death_start_siding}", ygopro.constants.COLORS.BABYBLUE)
          else
            win_pos = if @scores[@dueling_players[0].name_vpass] > @scores[@dueling_players[oppo_pos].name_vpass] then 0 else oppo_pos
            @finished_by_death = true
            ygopro.stoc_send_chat_to_room(this, "${death2_finish_part1}" + @dueling_players[win_pos].name + "${death2_finish_part2}", ygopro.constants.COLORS.BABYBLUE)
            CLIENT_send_replays(@dueling_players[oppo_pos - win_pos], this) if @hostinfo.mode == 1
            ygopro.stoc_send(@dueling_players[oppo_pos - win_pos], 'DUEL_END')
            ygopro.stoc_send(@dueling_players[oppo_pos - win_pos + 1], 'DUEL_END') if @hostinfo.mode == 2
            @scores[@dueling_players[oppo_pos - win_pos].name_vpass] = -1
            CLIENT_kick(@dueling_players[oppo_pos - win_pos])
            CLIENT_kick(@dueling_players[oppo_pos - win_pos + 1]) if @hostinfo.mode == 2
        when 1
          @death = -1
          ygopro.stoc_send_chat_to_room(this, "${death_start_quick}", ygopro.constants.COLORS.BABYBLUE)
        else
          @death = 5
          ygopro.stoc_send_chat_to_room(this, "${death_start_siding}", ygopro.constants.COLORS.BABYBLUE)
    return true

  cancel_death: () ->
    if @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or !@death
      return false
    @death = 0
    ygopro.stoc_send_chat_to_room(this, "${death_cancel}", ygopro.constants.COLORS.BABYBLUE)
    return true
  
  termiate: ->
    if @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
      @scores[@dueling_players[0].name_vpass] = 0
      @scores[@dueling_players[1].name_vpass] = 0
    @kicked = true
    @send_replays()
    @process.kill()
    @delete()
  
  finish_recover: (fail) ->
    if fail
      ygopro.stoc_send_chat_to_room(this, "${recover_fail}", ygopro.constants.COLORS.RED)
      @termiate()
    else
      ygopro.stoc_send_chat_to_room(this, "${recover_success}", ygopro.constants.COLORS.BABYBLUE)
      @recovering = false
      for player in @get_playing_player()
        for buffer in @recover_buffers[player.pos]
          ygopro.stoc_send(player, "GAME_MSG", buffer)

# 网络连接
net.createServer (client) ->
  client.ip = client.remoteAddress
  client.is_local = client.ip and (client.ip.includes('127.0.0.1') or client.ip.includes(real_windbot_server_ip))

  connect_count = ROOM_connected_ip[client.ip] or 0
  if !settings.modules.test_mode.no_connect_count_limit and !client.is_local
    connect_count++
  ROOM_connected_ip[client.ip] = connect_count
  #log.info "connect", client.ip, ROOM_connected_ip[client.ip]

  # server stand for the connection to ygopro server process
  server = new net.Socket()
  client.server = server
  server.client = client

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
      if settings.modules.heartbeat_detection.enabled
        CLIENT_heartbeat_unregister(client)
      if room
        if !CLIENT_reconnect_register(client, client.rid)
          room.disconnect(client)
      else if !client.had_new_reconnection
        SERVER_kick(client.server)
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
      client.closed = true
      if room
        if !CLIENT_reconnect_register(client, client.rid, error)
          room.disconnect(client, error)
      else if !client.had_new_reconnection
        SERVER_kick(client.server)
    return

  client.on 'timeout', ()->
    unless settings.modules.reconnect.enabled and (disconnect_list[CLIENT_get_authorize_key(client)] or client.had_new_reconnection)
      client.destroy()
    return

  server.on 'close', (had_error) ->
    server.closed = true unless server.closed
    if !server.client
      return
    #log.info "server closed", server.client.name, had_error
    room=ROOM_all[server.client.rid]
    #log.info "server close", server.client.ip, ROOM_connected_ip[server.client.ip]
    room.disconnector = 'server' if room and !server.system_kicked and !server.had_new_reconnection
    unless server.client.closed
      ygopro.stoc_send_chat(server.client, "${server_closed}", ygopro.constants.COLORS.RED)
      #if room and settings.modules.replay_delay
      #  room.send_replays()
      CLIENT_kick(server.client)
      SERVER_clear_disconnect(server)
    return

  server.on 'error', (error)->
    server.closed = error
    if !server.client
      return
    #log.info "server error", client.name, error
    room=ROOM_all[server.client.rid]
    #log.info "server err close", client.ip, ROOM_connected_ip[client.ip]
    room.disconnector = 'server' if room and !server.system_kicked and !server.had_new_reconnection
    unless server.client.closed
      ygopro.stoc_send_chat(server.client, "${server_error}: #{error}", ygopro.constants.COLORS.RED)
      #if room and settings.modules.replay_delay
      #  room.send_replays()
      CLIENT_kick(server.client)
      SERVER_clear_disconnect(server)
    return

  if ROOM_bad_ip[client.ip] > 5 or ROOM_connected_ip[client.ip] > 10
    log.info 'BAD IP', client.ip
    CLIENT_kick(client)
    return

  if settings.modules.cloud_replay.enabled
    client.open_cloud_replay= (err, replay)->
      if err or !replay
        ygopro.stoc_die(client, "${cloud_replay_no}")
        return
      redisdb.expire("replay:"+replay.replay_id, 60*60*48)
      buffer=Buffer.from(replay.replay_buffer,'binary')
      zlib.unzip buffer, (err, replay_buffer) ->
        if err
          log.info "cloud replay unzip error: " + err
          ygopro.stoc_send_chat(client, "${cloud_replay_error}", ygopro.constants.COLORS.RED)
          CLIENT_kick(client)
          return
        ygopro.stoc_send_chat(client, "${cloud_replay_playing} R##{replay.replay_id} #{replay.player_names} #{replay.date_time}", ygopro.constants.COLORS.BABYBLUE)
        client.write replay_buffer, ()->
          CLIENT_kick(client)
          return
        return
      return

  # 需要重构
  # 客户端到服务端(ctos)协议分析

  client.pre_establish_buffers = new Array()

  client.on 'data', (ctos_buffer) ->
    if client.is_post_watcher
      room=ROOM_all[client.rid]
      if room
        handle_data = await ygopro.helper.handleBuffer(ctos_buffer, "CTOS", ["CHAT"], {
          client: client,
          server: client.server
        })
        if handle_data.feedback
          log.warn(handle_data.feedback.message, client.name, client.ip)
          if handle_data.feedback.type == "OVERSIZE" or ROOM_bad_ip[client.ip] > 5
            bad_ip_count = ROOM_bad_ip[client.ip]
            if bad_ip_count
              ROOM_bad_ip[client.ip] = bad_ip_count + 1
            else
              ROOM_bad_ip[client.ip] = 1
            CLIENT_kick(client)
            return
        room.watcher.write(buffer) for buffer in handle_data.datas
    else
      ctos_filter = if settings.modules.reconnect.enabled and client.pre_reconnecting then ["UPDATE_DECK"] else null
      handle_data = await ygopro.helper.handleBuffer(ctos_buffer, "CTOS", ctos_filter, {
        client: client,
        server: client.server
      })
      if handle_data.feedback
        log.warn(handle_data.feedback.message, client.name, client.ip)
        if handle_data.feedback.type == "OVERSIZE" or ROOM_bad_ip[client.ip] > 5
          bad_ip_count = ROOM_bad_ip[client.ip]
          if bad_ip_count
            ROOM_bad_ip[client.ip] = bad_ip_count + 1
          else
            ROOM_bad_ip[client.ip] = 1
          CLIENT_kick(client)
          return
      if !client.server
        return
      if client.established
        client.server.write buffer for buffer in handle_data.datas
      else
        client.pre_establish_buffers.push buffer for buffer in handle_data.datas

    return

  # 服务端到客户端(stoc)
  server.on 'data', (stoc_buffer)->
    handle_data = await ygopro.helper.handleBuffer(stoc_buffer, "STOC", null, {
      client: server.client,
      server: server
    })
    if handle_data.feedback
      log.warn(handle_data.feedback.message, server.client.name, server.client.ip)
      if handle_data.feedback.type == "OVERSIZE"
        server.destroy()
        return
    if server.client and !server.client.closed
      server.client.write buffer for buffer in handle_data.datas

    return
  return
.listen settings.port, ->
  log.info "server started", settings.port
  return

if settings.modules.stop
  log.info "NOTE: server not open due to config, ", settings.modules.stop

deck_name_match = global.deck_name_match = (deck_name, player_name) ->
  if deck_name == player_name or deck_name == player_name + ".ydk" or deck_name == player_name + ".ydk.ydk"
    return true
  parsed_deck_name = deck_name.match(/^([^\+ \uff0b]+)[\+ \uff0b](.+?)(\.ydk){0,2}$/)
  return parsed_deck_name and (player_name == parsed_deck_name[1] or player_name == parsed_deck_name[2])

# 功能模块
# return true to cancel a synchronous message

ygopro.ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server, datas)->
  # checkmate use username$password, but here don't
  # so remove the password
  name_full =info.name.split("$")
  name = name_full[0]
  vpass = name_full[1]
  if vpass and !vpass.length
    vpass = null
  if (_.any(settings.ban.illegal_id, (badid) ->
    regexp = new RegExp(badid, 'i')
    matchs = name.match(regexp)
    if matchs
      name = matchs[1]
      return true
    return false
  , name))
    client.rag = true
  if settings.modules.mycard.enabled and settings.modules.mycard.ban_get and !client.is_local
    try
      banMCRequest = await axios.get settings.modules.mycard.ban_get, 
        paramsSerializer: qs.stringify
        params:
          user: name
      if typeof(banMCRequest.data) == "object"
        client.ban_mc = banMCRequest.data
      else
        log.warn "ban get bad json", banMCRequest.data
    catch e
      log.warn 'ban get error', e.toString()
  struct = ygopro.structs.get("CTOS_PlayerInfo")
  struct._setBuff(buffer)
  struct.set("name", name)
  buffer = struct.buffer
  client.name = name
  client.vpass = vpass
  client.name_vpass = if vpass then name + "$" + vpass else name

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
  await return false

ygopro.ctos_follow 'JOIN_GAME', true, (buffer, info, client, server, datas)->
#log.info info
  info.pass=info.pass.trim()
  client.pass = info.pass
  if CLIENT_is_able_to_reconnect(client) or CLIENT_is_able_to_kick_reconnect(client)
    CLIENT_pre_reconnect(client)
    return
  else if settings.modules.stop
    ygopro.stoc_die(client, settings.modules.stop)
  else if info.pass == "Marshtomp" or info.pass == "the Big Brother"
    ygopro.stoc_die(client, "${bad_user_name}")

  else if info.pass.toUpperCase()=="R" and settings.modules.cloud_replay.enabled
    ygopro.stoc_send_chat(client,"${cloud_replay_hint}", ygopro.constants.COLORS.BABYBLUE)
    redisdb.lrange CLIENT_get_authorize_key(client)+":replays", 0, 2, (err, result)->
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
      CLIENT_kick(client)
      return), 500

  else if info.pass.toUpperCase()=="RC" and settings.modules.tournament_mode.enable_recover
    ygopro.stoc_send_chat(client,"${recover_replay_hint}", ygopro.constants.COLORS.BABYBLUE)
    available_logs = duel_log.duel_log.filter((duel) ->
      return duel.id and duel.players[0].deck and duel.roommode != 2 and _.any(duel.players, (player) ->
        return player.real_name == client.name_vpass
      )
    ).slice(0, 8)
    _.each(available_logs, (duel) ->
      player_names = duel.players[0].real_name.split("$")[0] + (if duel.players[2] then "+" + duel.players[2].real_name.split("$")[0] else "") +
                    " VS " +
                   (if duel.players[1] then duel.players[1].real_name.split("$")[0] else "AI") +
                   (if duel.players[3] then "+" + duel.players[3].real_name.split("$")[0] else "")
      ygopro.stoc_send_chat(client,"<#{duel.id}> #{player_names} #{duel.time}", ygopro.constants.COLORS.BABYBLUE)
    )
    # 强行等待异步执行完毕_(:з」∠)_
    setTimeout (()->
      ygopro.stoc_send client, 'ERROR_MSG',{
        msg: 1
        code: 9
      }
      CLIENT_kick(client)
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

  else if info.version != settings.version and !settings.alternative_versions.includes(info.version)
    ygopro.stoc_send_chat(client, settings.modules.update, ygopro.constants.COLORS.RED)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 4
      code: settings.version
    }
    CLIENT_kick(client)

  else if !info.pass.length and !settings.modules.random_duel.enabled and !settings.modules.windbot.enabled and !settings.modules.challonge.enabled
    ygopro.stoc_die(client, "${blank_room_name}")

  else if info.pass.length and settings.modules.mycard.enabled and info.pass[0...3] != 'AI#'
    ygopro.stoc_send_chat(client, '${loading_user_info}', ygopro.constants.COLORS.BABYBLUE)
    if info.pass.length <= 8
      ygopro.stoc_die(client, '${invalid_password_length}')
      return

    if info.version != settings.version and settings.alternative_versions.includes(info.version)
      info.version = settings.version
      struct = ygopro.structs.get("CTOS_JoinGame")
      struct._setBuff(buffer)
      struct.set("version", info.version)
      buffer = struct.buffer

    buffer = Buffer.from(info.pass[0...8], 'base64')

    if buffer.length != 6
      ygopro.stoc_die(client, '${invalid_password_payload}')
      return

    check_buffer_indentity = (buf)->
      checksum = 0
      for i in [0...buf.length]
        checksum += buf.readUInt8(i)
      (checksum & 0xFF) == 0

    create_room_with_action = (buffer, decrypted_buffer, match_permit)->
      if client.closed
        return
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
            lflist: settings.hostinfo.lflist
            time_limit: settings.hostinfo.time_limit
            rule: (opt1 >> 5) & 3
            mode: (opt1 >> 3) & 3
            duel_rule: (if !!((opt1 >> 2) & 1) then 4 else 5)
            no_check_deck: !!((opt1 >> 1) & 1)
            no_shuffle_deck: !!(opt1 & 1)
            start_lp: opt2
            start_hand: opt3 >> 4
            draw_count: opt3 & 0xF
            no_watch: settings.hostinfo.no_watch
            auto_death: settings.hostinfo.auto_death
          }
          options.lflist = _.findIndex lflists, (list)-> ((options.rule == 1) == list.tcg) and list.date.isBefore()
          room_title = info.pass.slice(8).replace(String.fromCharCode(0xFEFF), ' ')
          if _.any(badwords.level3, (badword) ->
            regexp = new RegExp(badword, 'i')
            return room_title.match(regexp)
          , room_title)
            log.warn("BAD ROOM NAME LEVEL 3", room_title, client.name, client.ip)
            ygopro.stoc_die(client, "${bad_roomname_level3}")
            return
          else if _.any(badwords.level2, (badword) ->
            regexp = new RegExp(badword, 'i')
            return room_title.match(regexp)
          , room_title)
            log.warn("BAD ROOM NAME LEVEL 2", room_title, client.name, client.ip)
            ygopro.stoc_die(client, "${bad_roomname_level2}")
            return
          else if _.any(badwords.level1, (badword) ->
            regexp = new RegExp(badword, 'i')
            return room_title.match(regexp)
          , room_title)
            log.warn("BAD ROOM NAME LEVEL 1", room_title, client.name, client.ip)
            ygopro.stoc_die(client, "${bad_roomname_level1}")
            return
          room = new Room(name, options)
          if room
            room.title = room_title
            room.private = action == 2
        when 3
          name = info.pass.slice(8)
          room = ROOM_find_by_name(name)
          if(!room)
            ygopro.stoc_die(client, '${invalid_password_not_found}')
            return
        when 4
          if match_permit and !match_permit.permit
            ygopro.stoc_die(client, '${invalid_password_unauthorized}')
            return
          room = ROOM_find_or_create_by_name('M#' + info.pass.slice(8))
          if room
            for player in room.get_playing_player() when player and player.name == client.name
              ygopro.stoc_die(client, '${invalid_password_unauthorized}')
              return
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
      else if room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
        if settings.modules.cloud_replay.enable_halfway_watch and !room.hostinfo.no_watch
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
      else if room.hostinfo.no_watch and room.players.length >= (if room.hostinfo.mode == 2 then 4 else 2)
        ygopro.stoc_die(client, "${watch_denied_room}")
      else
        #client.room = room
        client.setTimeout(300000) #连接后超时5分钟
        client.rid = _.indexOf(ROOM_all, room)
        room.connect(client)
      return

    _async.auto({
      match_permit: (done) ->
        if client.closed
          done()
          return
        if(!settings.modules.arena_mode.check_permit)
          done(null, null)
          return
        request
          url: settings.modules.arena_mode.check_permit,
          json: true,
          qs:
            username: client.name,
            password: info.pass,
            arena: settings.modules.arena_mode.mode
        , (error, response, body)->
          if client.closed
            done(null, null)
            return
          if !error and body
            done(null, body)
          else
            log.warn("Match permit request error", error)
            done(null, null)
          return
        return
      get_user: (done) ->
        if client.closed
          done()
          return
        if id = users_cache[client.name]
          secret = id % 65535 + 1
          decrypted_buffer = Buffer.allocUnsafe(6)
          for i in [0, 2, 4]
            decrypted_buffer.writeUInt16LE(buffer.readUInt16LE(i) ^ secret, i)
          if check_buffer_indentity(decrypted_buffer)
            done(null, {
              original: decrypted_buffer,
              decrypted: decrypted_buffer
            })
            return

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
          if !error and body and body.user
            users_cache[client.name] = body.user.id
            secret = body.user.id % 65535 + 1
            decrypted_buffer = Buffer.allocUnsafe(6)
            for i in [0, 2, 4]
              decrypted_buffer.writeUInt16LE(buffer.readUInt16LE(i) ^ secret, i)
            if check_buffer_indentity(decrypted_buffer)
              buffer = decrypted_buffer
          else
            log.warn("READ USER FAIL", error, body)
            done("${create_room_failed}")
            return

          # buffer != decrypted_buffer  ==> auth failed

          if !check_buffer_indentity(buffer)
            done('${invalid_password_checksum}')
            return
          done(null, {
            original: buffer,
            decrypted: decrypted_buffer
          })
          return
        return
    }, (err, data) ->
      if(client.closed)
        return
      if(err)
        ygopro.stoc_die(client, err)
        return
      create_room_with_action(data.get_user.original, data.get_user.decrypted, data.match_permit)
    )


  else if settings.modules.challonge.enabled
    if info.version != settings.version and settings.alternative_versions.includes(info.version)
      info.version = settings.version
      struct = ygopro.structs.get("CTOS_JoinGame")
      struct._setBuff(buffer)
      struct.set("version", info.version)
      buffer = struct.buffer
    pre_room = ROOM_find_by_name(info.pass)
    if pre_room and pre_room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and settings.modules.cloud_replay.enable_halfway_watch and !pre_room.hostinfo.no_watch
      room = pre_room
      client.setTimeout(300000) #连接后超时5分钟
      client.rid = _.indexOf(ROOM_all, room)
      client.is_post_watcher = true
      ygopro.stoc_send_chat_to_room(room, "#{client.name} ${watch_join}")
      room.watchers.push client
      ygopro.stoc_send_chat(client, "${watch_watching}", ygopro.constants.COLORS.BABYBLUE)
      for buffer in room.watcher_buffers
        client.write buffer
    else
      ygopro.stoc_send_chat(client, '${loading_user_info}', ygopro.constants.COLORS.BABYBLUE)
      client.setTimeout(300000) #连接后超时5分钟
      recover_match = info.pass.match(/^(RC|RECOVER)(\d*)T(\d*)$/)
      _async.auto({
        participant_data: (done) ->
          challonge.participants._index({
            id: settings.modules.challonge.tournament_id,
            callback: done
          })
          return
        ,
        match_data: (done) ->
          challonge.matches._index({
            id: settings.modules.challonge.tournament_id,
            callback: done,
            no_cache: !!recover_match
          })
          return
      }, (err, datas) ->
        if client.closed
          return
        if err or !datas.participant_data or !datas.match_data
          log.warn("Failed loading Challonge user info", err)
          ygopro.stoc_die(client, '${challonge_match_load_failed}')
          return
        found = false
        for k,user of datas.participant_data
          if user.participant and user.participant.name and deck_name_match(user.participant.name, client.name)
            found = user.participant
            break
        if !found
          ygopro.stoc_die(client, '${challonge_user_not_found}')
          return
        client.challonge_info = found
        found = false
        for k,match of datas.match_data
          if match and match.match and !match.match.winnerId and match.match.state != "complete" and match.match.player1Id and match.match.player2Id and (match.match.player1Id == client.challonge_info.id or match.match.player2Id == client.challonge_info.id)
            found = match.match
            break
        if !found
          ygopro.stoc_die(client, '${challonge_match_not_found}')
          return
        #if found.winnerId
        #  ygopro.stoc_die(client, '${challonge_match_already_finished}')
        #  return
        create_room_name = 'M#' + found.id
        if recover_match
          create_room_name = recover_match[0] + ',' + create_room_name
        room = ROOM_find_or_create_by_name(create_room_name)
        if room
          room.challonge_info = found
          # room.max_player = 2
          room.welcome = "${challonge_match_created}"
        if !room
          ygopro.stoc_die(client, "${server_full}")
        else if room.error
          ygopro.stoc_die(client, room.error)
        else if room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
          if settings.modules.cloud_replay.enable_halfway_watch and !room.hostinfo.no_watch
            #client.setTimeout(300000) #连接后超时5分钟
            client.rid = _.indexOf(ROOM_all, room)
            client.is_post_watcher = true
            ygopro.stoc_send_chat_to_room(room, "#{client.name} ${watch_join}")
            room.watchers.push client
            ygopro.stoc_send_chat(client, "${watch_watching}", ygopro.constants.COLORS.BABYBLUE)
            for buffer in room.watcher_buffers
              client.write buffer
          else
            ygopro.stoc_die(client, "${watch_denied}")
        else if room.hostinfo.no_watch and room.players.length >= (if room.hostinfo.mode == 2 then 4 else 2)
          ygopro.stoc_die(client, "${watch_denied_room}")
        else
          for player in room.get_playing_player() when player and player != client and player.challonge_info.id == client.challonge_info.id
            ygopro.stoc_die(client, "${challonge_player_already_in}")
            return
          #client.room = room
          #client.setTimeout(300000) #连接后超时5分钟
          client.rid = _.indexOf(ROOM_all, room)
          room.connect(client)
        return
      )

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

  else if !settings.modules.tournament_mode.enabled and !settings.modules.challonge.enabled and _.any(badwords.level3, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 3", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level3}")

  else if !settings.modules.tournament_mode.enabled and !settings.modules.challonge.enabled and _.any(badwords.level2, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 2", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level2}")

  else if !settings.modules.tournament_mode.enabled and !settings.modules.challonge.enabled and _.any(badwords.level1, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 1", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level1}")

  else if info.pass.length && !ROOM_validate(info.pass)
    ygopro.stoc_die(client, "${invalid_password_room}")

  else
    if info.version != settings.version and settings.alternative_versions.includes(info.version)
      info.version = settings.version
      struct = ygopro.structs.get("CTOS_JoinGame")
      struct._setBuff(buffer)
      struct.set("version", info.version)
      buffer = struct.buffer

    #log.info 'join_game',info.pass, client.name
    room = ROOM_find_or_create_by_name(info.pass, client.ip)
    if !room
      ygopro.stoc_die(client, "${server_full}")
    else if room.error
      ygopro.stoc_die(client, room.error)
    else if room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
      if settings.modules.cloud_replay.enable_halfway_watch and !room.hostinfo.no_watch
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
    else if room.hostinfo.no_watch and room.players.length >= (if room.hostinfo.mode == 2 then 4 else 2)
      ygopro.stoc_die(client, "${watch_denied_room}")
    else
      client.setTimeout(300000) #连接后超时5分钟
      client.rid = _.indexOf(ROOM_all, room)
      room.connect(client)
  await return

ygopro.stoc_follow 'JOIN_GAME', false, (buffer, info, client, server, datas)->
  #欢迎信息
  room=ROOM_all[client.rid]
  return unless room and !client.reconnecting
  if !room.join_game_buffer
    room.join_game_buffer = buffer
  if settings.modules.welcome
    ygopro.stoc_send_chat(client, settings.modules.welcome, ygopro.constants.COLORS.GREEN)
  if room.welcome
    ygopro.stoc_send_chat(client, room.welcome, ygopro.constants.COLORS.BABYBLUE)
  if room.welcome2
    ygopro.stoc_send_chat(client, room.welcome2, ygopro.constants.COLORS.PINK)
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
  if settings.modules.random_duel.record_match_scores and room.random_type == 'M'
    ygopro.stoc_send_chat_to_room(room, ROOM_player_get_score(client), ygopro.constants.COLORS.GREEN)
    for player in room.players when player.pos != 7 and player != client
      ygopro.stoc_send_chat(client, ROOM_player_get_score(player), ygopro.constants.COLORS.GREEN)
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

  if settings.modules.cloud_replay.enable_halfway_watch and !room.watcher and !room.hostinfo.no_watch
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
      log.error "watcher error", error
      return
  await return

# 登场台词
load_dialogues = global.load_dialogues = (callback) ->
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
    if callback
      callback(error, body)
    return
  await return

if settings.modules.dialogues.get
  load_dialogues()

ygopro.stoc_follow 'GAME_MSG', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and !client.reconnecting
  msg = buffer.readInt8(0)
  #console.log client.pos, "MSG", ygopro.constants.MSG[msg]
  if ygopro.constants.MSG[msg] == 'RETRY' and room.recovering
    room.finish_recover(true)
    return true
  if settings.modules.retry_handle.enabled
    if ygopro.constants.MSG[msg] == 'RETRY'
      if !client.retry_count?
        client.retry_count = 0
      client.retry_count++
      log.warn "MSG_RETRY detected", client.name, client.ip, msg, client.retry_count
      if settings.modules.retry_handle.max_retry_count and client.retry_count >= settings.modules.retry_handle.max_retry_count
        ygopro.stoc_send_chat_to_room(room, client.name + "${retry_too_much_room_part1}" + settings.modules.retry_handle.max_retry_count + "${retry_too_much_room_part2}", ygopro.constants.COLORS.BABYBLUE)
        ygopro.stoc_send_chat(client, "${retry_too_much_part1}" + settings.modules.retry_handle.max_retry_count + "${retry_too_much_part2}", ygopro.constants.COLORS.RED)
        CLIENT_send_replays(client, room)
        CLIENT_kick(client)
        return true
      if client.last_game_msg
        if settings.modules.retry_handle.max_retry_count
          ygopro.stoc_send_chat(client, "${retry_part1}" + client.retry_count + "${retry_part2}" + settings.modules.retry_handle.max_retry_count + "${retry_part3}", ygopro.constants.COLORS.RED)
        else
          ygopro.stoc_send_chat(client, "${retry_not_counted}", ygopro.constants.COLORS.BABYBLUE)
        if client.last_hint_msg
          ygopro.stoc_send(client, 'GAME_MSG', client.last_hint_msg)
        ygopro.stoc_send(client, 'GAME_MSG', client.last_game_msg)
        return true
    else
      client.last_game_msg = buffer
      client.last_game_msg_title = ygopro.constants.MSG[msg]
      # log.info(client.name, client.last_game_msg_title)
  else if ygopro.constants.MSG[msg] != 'RETRY'
    client.last_game_msg = buffer
    client.last_game_msg_title = ygopro.constants.MSG[msg]
    # log.info(client.name, client.last_game_msg_title)

  if (msg >= 10 and msg < 30) or msg == 132 or (msg >= 140 and msg <= 144) #SELECT和ANNOUNCE开头的消息
    if room.recovering
      ygopro.ctos_send(server, 'RESPONSE', room.recover_replay.responses.splice(0, 1)[0])
      if !room.recover_replay.responses.length
        room.finish_recover()
      return true
    else
      room.waiting_for_player = client
      room.last_active_time = moment()
  #log.info("#{ygopro.constants.MSG[msg]}等待#{room.waiting_for_player.name}")

  #log.info 'MSG', ygopro.constants.MSG[msg]
  if ygopro.constants.MSG[msg] == 'START'
    playertype = buffer.readUInt8(1)
    client.is_first = !(playertype & 0xf)
    client.lp = room.hostinfo.start_lp
    client.card_count = 0 if room.hostinfo.mode != 2
    room.duel_stage = ygopro.constants.DUEL_STAGE.DUELING
    if client.pos == 0
      room.turn = 0
      room.duel_count++
      if room.death and room.duel_count > 1
        if room.death == -1
          ygopro.stoc_send_chat_to_room(room, "${death_start_final}", ygopro.constants.COLORS.BABYBLUE)
        else
          ygopro.stoc_send_chat_to_room(room, "${death_start_extra}", ygopro.constants.COLORS.BABYBLUE)
      if room.recovering
        ygopro.stoc_send_chat_to_room(room, "${recover_start_hint}", ygopro.constants.COLORS.BABYBLUE)
    if client.is_first and (room.hostinfo.mode != 2 or client.pos == 0 or client.pos == 2)
      room.first_list.push(client.name_vpass)
    if settings.modules.retry_handle.enabled
      client.retry_count = 0
      client.last_game_msg = null

  #ygopro.stoc_send_chat_to_room(room, "LP跟踪调试信息: #{client.name} 初始LP #{client.lp}")

  if ygopro.constants.MSG[msg] == 'HINT'
    hint_type = buffer.readUInt8(1)
    if hint_type == 3
      client.last_hint_msg = buffer

  if ygopro.constants.MSG[msg] == 'NEW_TURN'
    if client.pos == 0
      room.turn++
      if room.recovering and room.recover_from_turn <= room.turn
        room.finish_recover()
      if room.death and room.death != -2
        if room.turn >= room.death
          oppo_pos = if room.hostinfo.mode == 2 then 2 else 1
          if room.dueling_players[0].lp != room.dueling_players[oppo_pos].lp and room.turn > 1
            win_pos = if room.dueling_players[0].lp > room.dueling_players[oppo_pos].lp then 0 else oppo_pos
            ygopro.stoc_send_chat_to_room(room, "${death_finish_part1}" + room.dueling_players[win_pos].name + "${death_finish_part2}", ygopro.constants.COLORS.BABYBLUE)
            if room.hostinfo.mode == 2
              room.finished_by_death = true
              ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos], 'DUEL_END')
              ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos + 1], 'DUEL_END')
              room.scores[room.dueling_players[oppo_pos - win_pos].name_vpass] = -1
              CLIENT_kick(room.dueling_players[oppo_pos - win_pos])
              CLIENT_kick(room.dueling_players[oppo_pos - win_pos + 1])
            else
              ygopro.ctos_send(room.dueling_players[oppo_pos - win_pos].server, 'SURRENDER')
          else
            room.death = -1
            ygopro.stoc_send_chat_to_room(room, "${death_remain_final}", ygopro.constants.COLORS.BABYBLUE)
        else
          ygopro.stoc_send_chat_to_room(room, "${death_remain_part1}" + (room.death - room.turn) + "${death_remain_part2}", ygopro.constants.COLORS.BABYBLUE)
    if client.surrend_confirm
      client.surrend_confirm = false
      ygopro.stoc_send_chat(client, "${surrender_canceled}", ygopro.constants.COLORS.BABYBLUE)

  if ygopro.constants.MSG[msg] == 'NEW_PHASE'
    phase = buffer.readInt16LE(1)
    oppo_pos = if room.hostinfo.mode == 2 then 2 else 1
    if client.pos == 0 and room.death == -2 and not (phase == 0x1 and room.turn < 2)
      if room.dueling_players[0].lp != room.dueling_players[oppo_pos].lp
        win_pos = if room.dueling_players[0].lp > room.dueling_players[oppo_pos].lp then 0 else oppo_pos
        ygopro.stoc_send_chat_to_room(room, "${death_finish_part1}" + room.dueling_players[win_pos].name + "${death_finish_part2}", ygopro.constants.COLORS.BABYBLUE)
        if room.hostinfo.mode == 2
          room.finished_by_death = true
          ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos], 'DUEL_END')
          ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos + 1], 'DUEL_END')
          room.scores[room.dueling_players[oppo_pos - win_pos].name_vpass] = -1
          CLIENT_kick(room.dueling_players[oppo_pos - win_pos])
          CLIENT_kick(room.dueling_players[oppo_pos - win_pos + 1])
        else
          ygopro.ctos_send(room.dueling_players[oppo_pos - win_pos].server, 'SURRENDER')
      else
        room.death = -1
        ygopro.stoc_send_chat_to_room(room, "${death_remain_final}", ygopro.constants.COLORS.BABYBLUE)

  if ygopro.constants.MSG[msg] == 'WIN' and client.pos == 0
    if room.recovering
      room.finish_recover(true)
      return true
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first or pos == 2 or room.duel_stage != ygopro.constants.DUEL_STAGE.DUELING
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    reason = buffer.readUInt8(2)
    #log.info {winner: pos, reason: reason}
    #room.duels.push {winner: pos, reason: reason}
    room.winner = pos
    room.turn = 0
    room.duel_stage = ygopro.constants.DUEL_STAGE.END
    if settings.modules.heartbeat_detection.enabled
      for player in room.players
        player.heartbeat_protected = false
      delete room.long_resolve_card
      delete room.long_resolve_chain
    if room and !room.finished and room.dueling_players[pos]
      room.winner_name = room.dueling_players[pos].name_vpass
      #log.info room.dueling_players, pos
      room.scores[room.winner_name] = room.scores[room.winner_name] + 1
      if room.match_kill
        room.match_kill = false
        room.scores[room.winner_name] = 99
    if room.death
      if settings.modules.http.quick_death_rule == 1 or settings.modules.http.quick_death_rule == 3
        room.death = -1
      else
        room.death = 5

  if ygopro.constants.MSG[msg] == 'MATCH_KILL' and client.pos == 0
    room.match_kill = true

  #lp跟踪
  if ygopro.constants.MSG[msg] == 'DAMAGE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    room.dueling_players[pos].lp = 0 if room.dueling_players[pos].lp < 0
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "${lp_low_opponent}", ygopro.constants.COLORS.PINK)

  if ygopro.constants.MSG[msg] == 'RECOVER' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp += val

  if ygopro.constants.MSG[msg] == 'LPUPDATE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp = val

  if ygopro.constants.MSG[msg] == 'PAY_LPCOST' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    room.dueling_players[pos].lp = 0 if room.dueling_players[pos].lp < 0
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "${lp_low_self}", ygopro.constants.COLORS.PINK)

  #track card count
  #todo: track card count in tag mode
  if ygopro.constants.MSG[msg] == 'MOVE' and room.hostinfo.mode != 2
    pos = buffer.readUInt8(5)
    pos = 1 - pos unless client.is_first
    loc = buffer.readUInt8(6)
    client.card_count-- if (loc & 0xe) and pos == 0
    pos = buffer.readUInt8(9)
    pos = 1 - pos unless client.is_first
    loc = buffer.readUInt8(10)
    client.card_count++ if (loc & 0xe) and pos == 0

  if ygopro.constants.MSG[msg] == 'DRAW' and room.hostinfo.mode != 2
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    if pos == 0
      count = buffer.readInt8(2)
      client.card_count += count

  # check panel confirming cards in heartbeat
  if settings.modules.heartbeat_detection.enabled and ygopro.constants.MSG[msg] == 'CONFIRM_CARDS'
    check = false
    count = buffer.readInt8(2)
    max_loop = 3 + (count - 1) * 7
    deck_found = 0
    limbo_found = 0 # support custom cards which may be in location 0 in KoishiPro or EdoPro
    for i in [3..max_loop] by 7
      loc = buffer.readInt8(i + 5)
      if (loc & 0x41) > 0
        deck_found++
      else if loc == 0
        limbo_found++
      if (deck_found > 0 and count > 1) or limbo_found > 0
        check = true
        break
    if check
      #console.log("Confirming cards:" + client.name)
      client.heartbeat_protected = true

  # chain detection
  if settings.modules.heartbeat_detection.enabled and client.pos == 0
    if ygopro.constants.MSG[msg] == 'CHAINING'
      card = buffer.readUInt32LE(1)
      found = false
      for id in long_resolve_cards when id == card
        found = true
        break
      if found
        room.long_resolve_card = card
        # console.log(0,card)
      else
        delete room.long_resolve_card
    else if ygopro.constants.MSG[msg] == 'CHAINED' and room.long_resolve_card
      chain = buffer.readInt8(1)
      if !room.long_resolve_chain
        room.long_resolve_chain = []
      room.long_resolve_chain[chain] = true
      # console.log(1,chain)
      delete room.long_resolve_card
    else if ygopro.constants.MSG[msg] == 'CHAIN_SOLVING' and room.long_resolve_chain
      chain = buffer.readInt8(1)
      # console.log(2,chain)
      if room.long_resolve_chain[chain]
        for player in room.get_playing_player()
          player.heartbeat_protected = true
    else if (ygopro.constants.MSG[msg] == 'CHAIN_NEGATED' or ygopro.constants.MSG[msg] == 'CHAIN_DISABLED') and room.long_resolve_chain
      chain = buffer.readInt8(1)
      # console.log(3,chain)
      delete room.long_resolve_chain[chain]
    else if ygopro.constants.MSG[msg] == 'CHAIN_END'
      # console.log(4,chain)
      delete room.long_resolve_card
      delete room.long_resolve_chain

  #登场台词
  if settings.modules.dialogues.enabled and !room.recovering
    if ygopro.constants.MSG[msg] == 'SUMMONING' or ygopro.constants.MSG[msg] == 'SPSUMMONING' or ygopro.constants.MSG[msg] == 'CHAINING'
      card = buffer.readUInt32LE(1)
      trigger_location = buffer.readUInt8(6)
      if dialogues.dialogues[card] and (ygopro.constants.MSG[msg] != 'CHAINING' or (trigger_location & 0x8) and client.ready_trap)
        for line in _.lines dialogues.dialogues[card][Math.floor(Math.random() * dialogues.dialogues[card].length)]
          ygopro.stoc_send_chat(client, line, ygopro.constants.COLORS.PINK)
    if ygopro.constants.MSG[msg] == 'POS_CHANGE'
      loc = buffer.readUInt8(6)
      ppos = buffer.readUInt8(8)
      cpos = buffer.readUInt8(9)
      client.ready_trap = !!(loc & 0x8) and !!(ppos & 0xa) and !!(cpos & 0x5)
    else if ygopro.constants.MSG[msg] != 'UPDATE_CARD' and ygopro.constants.MSG[msg] != 'WAITING'
      client.ready_trap = false

  if room.recovering and client.pos < 4
    if ygopro.constants.MSG[msg] != 'WAITING'
      room.recover_buffers[client.pos].push(buffer)
    return true

  await return false

#房间管理
ygopro.ctos_follow 'HS_TOOBSERVER', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if room.hostinfo.no_watch
    ygopro.stoc_send_chat(client, "${watch_denied_room}", ygopro.constants.COLORS.RED)
    return true
  if (!room.arena and !settings.modules.challonge.enabled) or client.is_local
    return false
  for player in room.players
    if player == client
      ygopro.stoc_send_chat(client, "${cannot_to_observer}", ygopro.constants.COLORS.BABYBLUE)
      return true
  await return false

ygopro.ctos_follow 'HS_KICK', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  for player in room.players
    if player and player.pos == info.pos and player != client
      if room.arena == "athletic" or settings.modules.challonge.enabled
        ygopro.stoc_send_chat_to_room(room, "#{client.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        CLIENT_kick(client)
        return true
      client.kick_count = if client.kick_count then client.kick_count+1 else 1
      if client.kick_count>=5 and room.random_type
        ygopro.stoc_send_chat_to_room(room, "#{client.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        ROOM_ban_player(player.name, player.ip, "${random_ban_reason_zombie}")
        CLIENT_kick(client)
        return true
      ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_player}", ygopro.constants.COLORS.RED)
  await return false

ygopro.stoc_follow 'TYPE_CHANGE', true, (buffer, info, client, server, datas)->
  selftype = info.type & 0xf
  is_host = ((info.type >> 4) & 0xf) != 0
  # if room and room.hostinfo.no_watch and selftype == 7
  #   ygopro.stoc_die(client, "${watch_denied_room}")
  #   return true
  client.is_host = is_host
  client.pos = selftype
  #console.log "TYPE_CHANGE to #{client.name}:", info, selftype, is_host
  await return false

ygopro.stoc_follow 'HS_PLAYER_ENTER', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return false unless room and settings.modules.hide_name and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN
  pos = info.pos
  if pos < 4 and pos != client.pos
    struct = ygopro.structs.get("STOC_HS_PlayerEnter")
    struct._setBuff(buffer)
    struct.set("name", "********")
    buffer = struct.buffer
  await return false

ygopro.stoc_follow 'HS_PLAYER_CHANGE', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and room.max_player and client.pos == 0
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
        room.waiting_for_player_time = settings.modules.arena_mode.ready_time
        room.waiting_for_player_interval = setInterval (()-> wait_room_start_arena(ROOM_all[client.rid]);return), 1000
      else if !room.waiting_for_player and room.waiting_for_player_interval
        clearInterval room.waiting_for_player_interval
        room.waiting_for_player_interval = null
        room.waiting_for_player_time = settings.modules.arena_mode.ready_time
    else
      room.ready_player_count_without_host = 0
      for player in room.players
        if player.pos == pos
          player.is_ready = is_ready
        unless player.is_host
          room.ready_player_count_without_host += player.is_ready
      if room.ready_player_count_without_host >= room.max_player - 1
        #log.info "all ready"
        setTimeout (()-> wait_room_start(ROOM_all[client.rid], settings.modules.random_duel.ready_time);return), 1000
  await return

ygopro.ctos_follow 'REQUEST_FIELD', true, (buffer, info, client, server, datas)->
  await return true

ygopro.stoc_follow 'FIELD_FINISH', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return true unless room and settings.modules.reconnect.enabled
  client.reconnecting = false
  if client.time_confirm_required # client did not send TIME_CONFIRM
    client.waiting_for_last = true
  else if client.last_game_msg and client.last_game_msg_title != 'WAITING' # client sent TIME_CONFIRM
    if client.last_hint_msg
      ygopro.stoc_send(client, 'GAME_MSG', client.last_hint_msg)
    ygopro.stoc_send(client, 'GAME_MSG', client.last_game_msg)
  await return true

ygopro.stoc_follow 'DUEL_END', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and settings.modules.replay_delay and room.hostinfo.mode == 1
  SOCKET_flush_data(client, datas)
  CLIENT_send_replays(client, room)
  if !room.replays_sent_to_watchers
    room.replays_sent_to_watchers = true
    for player in room.players when player and player.pos > 3
      CLIENT_send_replays(player, room)
    for player in room.watchers when player
      CLIENT_send_replays(player, room)
  await return

wait_room_start = (room, time)->
  if room and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and room.ready_player_count_without_host >= room.max_player - 1
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
          CLIENT_kick(player)
  await return

wait_room_start_arena = (room)->
  if room and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and room.waiting_for_player
    room.waiting_for_player_time = room.waiting_for_player_time - 1
    if room.waiting_for_player_time > 0
      unless room.waiting_for_player_time % 5
        for player in room.players when player
          display_name = (if settings.modules.hide_name and player != room.waiting_for_player then "********" else room.waiting_for_player.name)
          ygopro.stoc_send_chat(player, "#{if room.waiting_for_player_time <= 9 then ' ' else ''}#{room.waiting_for_player_time}${kick_count_down_arena_part1} #{display_name} ${kick_count_down_arena_part2}", if room.waiting_for_player_time <= 9 then ygopro.constants.COLORS.RED else ygopro.constants.COLORS.LIGHTBLUE)
    else
      ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
      CLIENT_kick(room.waiting_for_player)
      if room.waiting_for_player_interval
        clearInterval room.waiting_for_player_interval
        room.waiting_for_player_interval = null
  await return

#tip
ygopro.stoc_send_random_tip = (client)->
  if settings.modules.tips.enabled && tips.tips.length
    ygopro.stoc_send_chat(client, "Tip: " + tips.tips[Math.floor(Math.random() * tips.tips.length)])
  await return
ygopro.stoc_send_random_tip_to_room = (room)->
  if settings.modules.tips.enabled && tips.tips.length
    ygopro.stoc_send_chat_to_room(room, "Tip: " + tips.tips[Math.floor(Math.random() * tips.tips.length)])
  await return

load_tips = global.load_tips = (callback)->
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
    if callback
      callback(error, body)
    return
  await return

if settings.modules.tips.get
  load_tips()
  setInterval ()->
    for room in ROOM_all when room and room.established
      ygopro.stoc_send_random_tip_to_room(room) if room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING or room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN
    return
  , 30000

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and !client.reconnecting
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN #first start
    room.duel_stage = ygopro.constants.DUEL_STAGE.FINGER
    room.start_time = moment().format()
    room.turn = 0
    roomlist.start room if !room.windbot and settings.modules.http.websocket_roomlist
    #room.duels = []
    room.dueling_players = []
    for player in room.players when player.pos != 7
      room.dueling_players[player.pos] = player
      room.scores[player.name_vpass] = 0
      room.player_datas.push key: CLIENT_get_authorize_key(player), name: player.name
      if room.random_type == 'T'
        # 双打房不记录匹配过
        ROOM_players_oppentlist[player.ip] = null
    if room.hostinfo.auto_death
      ygopro.stoc_send_chat_to_room(room, "${auto_death_part1}#{room.hostinfo.auto_death}${auto_death_part2}", ygopro.constants.COLORS.BABYBLUE)
  else if room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING and client.pos < 4 # side deck verified
    client.selected_preduel = true
    if client.side_tcount
      clearInterval client.side_interval
      client.side_interval = null
      client.side_tcount = null
  if settings.modules.hide_name and room.duel_count == 0
    for player in room.get_playing_player() when player != client
      ygopro.stoc_send(client, 'HS_PLAYER_ENTER', {
        name: player.name,
        pos: player.pos
      })
  if settings.modules.tips.enabled
    ygopro.stoc_send_random_tip(client)
  deck_text = null
  if client.main and client.main.length
    deck_text = '#ygopro-server deck log\n#main\n' + client.main.join('\n') + '\n!side\n' + client.side.join('\n') + '\n'
    room.decks[client.name] = deck_text
  if settings.modules.deck_log.enabled and deck_text and not client.deck_saved and not room.windbot
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
      deck_name = moment().format('YYYY-MM-DD HH-mm-ss') + ' ' + room.process_pid + ' ' + client.pos + ' ' + client.ip.slice(7) + ' ' + client.name.replace(/[\/\\\?\*]/g, '_')
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
  await return

ygopro.ctos_follow 'SURRENDER', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or room.hostinfo.mode == 2
    return true
  if room.random_type and room.turn < 3 and not client.flee_free and not settings.modules.test_mode.surrender_anytime and not (room.random_type=='M' and settings.modules.random_duel.record_match_scores)
    ygopro.stoc_send_chat(client, "${surrender_denied}", ygopro.constants.COLORS.BABYBLUE)
    return true
  await return false

report_to_big_brother = global.report_to_big_brother = (roomname, sender, ip, level, content, match) ->
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
  await return

ygopro.ctos_follow 'CHAT', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  msg = _.trim(info.msg)
  cancel = _.startsWith(msg, "/")
  room.last_active_time = moment() unless cancel or not (room.random_type or room.arena) or room.duel_stage == ygopro.constants.DUEL_STAGE.FINGER or room.duel_stage == ygopro.constants.DUEL_STAGE.FIRSTGO or room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING
  cmd = msg.split(' ')
  switch cmd[0]
    when '/投降', '/surrender'
      if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or room.hostinfo.mode == 2
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
      ygopro.stoc_send_chat(client, "${chat_order_chatcolor_1}") if settings.modules.chat_color.enabled
      ygopro.stoc_send_chat(client, "${chat_order_chatcolor_2}") if settings.modules.chat_color.enabled

    when '/tip'
      ygopro.stoc_send_random_tip(client) if settings.modules.tips.enabled

    when '/ai'
      if settings.modules.windbot.enabled and client.is_host and !settings.modules.challonge.enabled and !room.arena and room.random_type != 'M'
        cmd.shift()
        if name = cmd.join(' ')
          windbot = _.sample _.filter windbots, (w)->
            w.name == name or w.deck == name
          if !windbot
            ygopro.stoc_send_chat(client, "${windbot_deck_not_found}", ygopro.constants.COLORS.RED)
            return
        else
          windbot = _.sample _.filter windbots, (w)->
            !w.hidden
        if room.random_type
          ygopro.stoc_send_chat(client, "${windbot_disable_random_room} " + room.name, ygopro.constants.COLORS.BABYBLUE)
        room.add_windbot(windbot)

    when '/roomname'
      ygopro.stoc_send_chat(client, "${room_name} " + room.name, ygopro.constants.COLORS.BABYBLUE) if room

    when '/color'
      if settings.modules.chat_color.enabled
        cip = CLIENT_get_authorize_key(client)
        if cmsg = cmd[1]
          if cmsg.toLowerCase() == "help"
            ygopro.stoc_send_chat(client, "${show_color_list}", ygopro.constants.COLORS.BABYBLUE)
            for cname,cvalue of ygopro.constants.COLORS when cvalue > 10
              ygopro.stoc_send_chat(client, cname, cvalue)
          else if cmsg.toLowerCase() == "default"
            chat_color.save_list[cip] = false
            setting_save(chat_color)
            ygopro.stoc_send_chat(client, "${set_chat_color_default}", ygopro.constants.COLORS.BABYBLUE)
          else
            ccolor = cmsg.toUpperCase()
            if ygopro.constants.COLORS[ccolor] and ygopro.constants.COLORS[ccolor] > 10 and ygopro.constants.COLORS[ccolor] < 20
              chat_color.save_list[cip] = ccolor
              setting_save(chat_color)
              ygopro.stoc_send_chat(client, "${set_chat_color_part1}" + ccolor + "${set_chat_color_part2}", ygopro.constants.COLORS.BABYBLUE)
            else
              ygopro.stoc_send_chat(client, "${color_not_found_part1}" + ccolor + "${color_not_found_part2}", ygopro.constants.COLORS.RED)
        else
          if color = chat_color.save_list[cip]
            ygopro.stoc_send_chat(client, "${get_chat_color_part1}" + color + "${get_chat_color_part2}", ygopro.constants.COLORS.BABYBLUE)
          else
            ygopro.stoc_send_chat(client, "${get_chat_color_default}", ygopro.constants.COLORS.BABYBLUE)

    #when '/test'
    #  ygopro.stoc_send_hint_card_to_room(room, 2333365)
  if (msg.length>100)
    log.warn "SPAM WORD", client.name, client.ip, msg
    client.abuse_count=client.abuse_count+2 if client.abuse_count
    ygopro.stoc_send_chat(client, "${chat_warn_level0}", ygopro.constants.COLORS.RED)
    cancel = true
  if !(room and (room.random_type or room.arena))
    if !cancel and settings.modules.display_watchers and client.is_post_watcher
      ygopro.stoc_send_chat_to_room(room, "#{client.name}: #{msg}", 9)
      return true
    return cancel
  if client.abuse_count>=5 or CLIENT_is_banned_by_mc(client)
    log.warn "BANNED CHAT", client.name, client.ip, msg
    ygopro.stoc_send_chat(client, "${banned_chat_tip}" + (if client.ban_mc and client.ban_mc.message then (": " + client.ban_mc.message) else ""), ygopro.constants.COLORS.RED)
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
      CLIENT_send_replays(client, room)
      CLIENT_kick(client)
      return true
    else
      client.abuse_count=client.abuse_count+4
      ygopro.stoc_send_chat(client, "${chat_warn_level2}", ygopro.constants.COLORS.RED)
  else if (client.rag and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN)
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
      struct = ygopro.structs.get("chat")
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
  if !cancel and settings.modules.display_watchers and client.is_post_watcher
    ygopro.stoc_send_chat_to_room(room, "#{client.name}: #{msg}", 9)
    return true
  await return cancel

ygopro.ctos_follow 'UPDATE_DECK', true, (buffer, info, client, server, datas)->
  if settings.modules.reconnect.enabled and client.pre_reconnecting
    if !CLIENT_is_able_to_reconnect(client) and !CLIENT_is_able_to_kick_reconnect(client)
      ygopro.stoc_send_chat(client, "${reconnect_failed}", ygopro.constants.COLORS.RED)
      CLIENT_kick(client)
    else if CLIENT_is_able_to_reconnect(client, buffer)
      CLIENT_reconnect(client)
    else if CLIENT_is_able_to_kick_reconnect(client, buffer)
      CLIENT_kick_reconnect(client, buffer)
    else
      ygopro.stoc_send_chat(client, "${deck_incorrect_reconnect}", ygopro.constants.COLORS.RED)
      ygopro.stoc_send(client, 'ERROR_MSG', {
        msg: 2,
        code: 0
      })
      ygopro.stoc_send(client, 'HS_PLAYER_CHANGE', {
        status: (client.pos << 4) | 0xa
      })
    return true
  room=ROOM_all[client.rid]
  return false unless room
  #log.info info
  if info.mainc > 256 or info.sidec > 256 # Prevent attack, see https://github.com/Fluorohydride/ygopro/issues/2174
    CLIENT_kick(client)
    return true
  buff_main = (info.deckbuf[i] for i in [0...info.mainc])
  buff_side = (info.deckbuf[i] for i in [info.mainc...info.mainc + info.sidec])
  client.main = buff_main
  client.side = buff_side
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN
    client.start_deckbuf = Buffer.from(buffer)
  oppo_pos = if room.hostinfo.mode == 2 then 2 else 1
  if settings.modules.http.quick_death_rule >= 2 and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.death and room.scores[room.dueling_players[0].name_vpass] != room.scores[room.dueling_players[oppo_pos].name_vpass]
    win_pos = if room.scores[room.dueling_players[0].name_vpass] > room.scores[room.dueling_players[oppo_pos].name_vpass] then 0 else oppo_pos
    room.finished_by_death = true
    ygopro.stoc_send_chat_to_room(room, "${death2_finish_part1}" + room.dueling_players[win_pos].name + "${death2_finish_part2}", ygopro.constants.COLORS.BABYBLUE)
    CLIENT_send_replays(room.dueling_players[oppo_pos - win_pos], room) if room.hostinfo.mode == 1
    ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos], 'DUEL_END')
    ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos + 1], 'DUEL_END') if room.hostinfo.mode == 2
    room.scores[room.dueling_players[oppo_pos - win_pos].name_vpass] = -1
    CLIENT_kick(room.dueling_players[oppo_pos - win_pos])
    CLIENT_kick(room.dueling_players[oppo_pos - win_pos + 1]) if room.hostinfo.mode == 2
    return true
  struct = ygopro.structs.get("deck")
  struct._setBuff(buffer)
  if room.random_type or room.arena
    if client.pos == 0
      room.waiting_for_player = room.waiting_for_player2
    room.last_active_time = moment()
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and room.recovering
    recover_player_data = _.find(room.recover_duel_log.players, (player) ->
      return player.real_name == client.name_vpass and _.isEqual(buffer, Buffer.from(player.deckbuf, "base64"))
    )
    if recover_player_data
      struct.set("mainc", recover_player_data.deck.main.length)
      struct.set("sidec", recover_player_data.deck.side.length)
      struct.set("deckbuf", recover_player_data.deck.main.concat(recover_player_data.deck.side))
      if recover_player_data.is_first
        room.determine_firstgo = client
    else
      struct.set("mainc", 1)
      struct.set("sidec", 1)
      struct.set("deckbuf", [4392470, 4392470])
      ygopro.stoc_send_chat(client, "${deck_incorrect_reconnect}", ygopro.constants.COLORS.RED)
  else if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and room.hostinfo.mode == 1 and settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.deck_check and fs.readdirSync(settings.modules.tournament_mode.deck_path).length
    struct.set("mainc", 1)
    struct.set("sidec", 1)
    struct.set("deckbuf", [4392470, 4392470])
    buffer = struct.buffer
    found_deck=false
    decks=fs.readdirSync(settings.modules.tournament_mode.deck_path)
    for deck in decks
      if deck_name_match(deck, client.name)
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
  await return false

ygopro.ctos_follow 'RESPONSE', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and (room.random_type or room.arena)
  room.last_active_time = moment()
  await return

ygopro.stoc_follow 'TIME_LIMIT', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  check = false
  if room.hostinfo.mode != 2
    check = (client.is_first and info.player == 0) or (!client.is_first and info.player == 1)
  else
    cur_players = []
    switch room.turn % 4
      when 1
        cur_players[0] = 0
        cur_players[1] = 3
      when 2
        cur_players[0] = 0
        cur_players[1] = 2
      when 3
        cur_players[0] = 1
        cur_players[1] = 2
      when 0
        cur_players[0] = 1
        cur_players[1] = 3
    if !room.dueling_players[0].is_first
      cur_players[0] = cur_players[0] + 2
      cur_players[1] = cur_players[1] - 2
    check = client.pos == cur_players[info.player]
  if room.recovering
    if check
      ygopro.ctos_send(server, 'TIME_CONFIRM')
    return true
  if settings.modules.reconnect.enabled
    if client.closed
      ygopro.ctos_send(server, 'TIME_CONFIRM')
      return true
    else
      client.time_confirm_required = true
  return unless settings.modules.heartbeat_detection.enabled and room.duel_stage == ygopro.constants.DUEL_STAGE.DUELING and !room.windbot
  if check
    CLIENT_heartbeat_register(client, false)
  await return false

ygopro.ctos_follow 'TIME_CONFIRM', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if room.recovered
    room.recovered = false
  if settings.modules.reconnect.enabled
    if client.waiting_for_last
      client.waiting_for_last = false
      if client.last_game_msg and client.last_game_msg_title != 'WAITING'
        if client.last_hint_msg
          ygopro.stoc_send(client, 'GAME_MSG', client.last_hint_msg)
        ygopro.stoc_send(client, 'GAME_MSG', client.last_game_msg)
    client.time_confirm_required = false
  if settings.modules.heartbeat_detection.enabled
    client.heartbeat_protected = false
    client.heartbeat_responsed = true
    CLIENT_heartbeat_unregister(client)
  await return

ygopro.ctos_follow 'HAND_RESULT', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  client.selected_preduel = true
  if room.random_type or room.arena
    if client.pos == 0
      room.waiting_for_player = room.waiting_for_player2
    room.last_active_time = moment().subtract(settings.modules.random_duel.hang_timeout - 19, 's')
  await return

ygopro.ctos_follow 'TP_RESULT', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  client.selected_preduel = true
  # room.selecting_tp = false
  return unless room.random_type or room.arena
  room.last_active_time = moment()
  await return

ygopro.stoc_follow 'CHAT', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  pid = info.player
  return unless room and pid < 4 and settings.modules.chat_color.enabled and (!settings.modules.hide_name or room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN)
  if room.duel_stage == ygopro.constants.DUEL_STAGE.DUELING and !room.dueling_players[0].is_first
    if room.hostinfo.mode == 2
      pid = {
        0: 2,
        1: 3,
        2: 0,
        3: 1
      }[pid]
    else
      pid = 1 - pid
  for player in room.players when player and player.pos == pid
    tplayer = player
  return unless tplayer
  tcolor = chat_color.save_list[CLIENT_get_authorize_key(tplayer)]
  if tcolor
    ygopro.stoc_send client, 'CHAT', {
        player: ygopro.constants.COLORS[tcolor]
        msg: tplayer.name + ": " + info.msg
      }
    return true
  await return

ygopro.stoc_follow 'SELECT_HAND', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return false unless room
  if client.pos == 0
    room.duel_stage = ygopro.constants.DUEL_STAGE.FINGER
  if room.random_type or room.arena
    if client.pos == 0
      room.waiting_for_player = client
    else
      room.waiting_for_player2 = client
    room.last_active_time = moment().subtract(settings.modules.random_duel.hang_timeout - 19, 's')
  if room.determine_firstgo
    ygopro.ctos_send(server, "HAND_RESULT", {
      res: if client.pos == 0 then 2 else 1
    })
    return true
  else
    client.selected_preduel = false
  await return false

ygopro.stoc_follow 'HAND_RESULT', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return false unless room
  await return room.determine_firstgo

ygopro.stoc_follow 'SELECT_TP', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return false unless room
  room.duel_stage = ygopro.constants.DUEL_STAGE.FIRSTGO
  if room.random_type or room.arena
    room.waiting_for_player = client
    room.last_active_time = moment()
  if room.determine_firstgo
    ygopro.ctos_send(server, "TP_RESULT", {
      res: if room.determine_firstgo == client then 1 else 0
    })
    return true
  else
    client.selected_preduel = false
    room.selecting_tp = client
  await return false

ygopro.stoc_follow 'CHANGE_SIDE', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if client.pos == 0
    room.duel_stage = ygopro.constants.DUEL_STAGE.SIDING
  client.selected_preduel = false
  if settings.modules.side_timeout
    client.side_tcount = settings.modules.side_timeout
    ygopro.stoc_send_chat(client, "${side_timeout_part1}#{settings.modules.side_timeout}${side_timeout_part2}", ygopro.constants.COLORS.BABYBLUE)
    sinterval = setInterval ()->
      if not (room and client and client.side_tcount and room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING)
        clearInterval sinterval
        return
      if client.side_tcount == 1
        ygopro.stoc_send_chat_to_room(room, client.name + "${side_overtime_room}", ygopro.constants.COLORS.BABYBLUE)
        ygopro.stoc_send_chat(client, "${side_overtime}", ygopro.constants.COLORS.RED)
        #room.scores[client.name_vpass] = -9
        CLIENT_send_replays(client, room)
        CLIENT_kick(client)
        clearInterval sinterval
      else
        client.side_tcount = client.side_tcount - 1
        ygopro.stoc_send_chat(client, "${side_remain_part1}#{client.side_tcount}${side_remain_part2}", ygopro.constants.COLORS.BABYBLUE)
    , 60000
    client.side_interval = sinterval
  if settings.modules.challonge.enabled and settings.modules.challonge.post_score_midduel and room.hostinfo.mode != 2 and client.pos == 0
    temp_log = JSON.parse(JSON.stringify(room.get_challonge_score()))
    delete temp_log.winnerId
    room_name = room.name
    challonge.matches._update({
      id: settings.modules.challonge.tournament_id,
      matchId: room.challonge_info.id,
      match: temp_log,
      callback: (err, data) ->
        if err
          log.warn("Errored pushing scores to Challonge.", room_name, err)
        else
          refresh_challonge_cache()
        return
    })
  if room.random_type or room.arena
    if client.pos == 0
      room.waiting_for_player = client
    else
      room.waiting_for_player2 = client
    room.last_active_time = moment()
  await return

ygopro.stoc_follow 'REPLAY', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.block_replay_to_player or settings.modules.replay_delay unless room
  if settings.modules.cloud_replay.enabled and room.random_type
    Cloud_replay_ids.push room.cloud_replay_id
  if !room.replays[room.duel_count - 1]
    # console.log("Replay saved: ", room.duel_count - 1, client.pos)
    room.replays[room.duel_count - 1] = buffer
  if settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.replay_safe or settings.modules.tournament_mode.enable_recover
    if client.pos == 0
      dueltime=moment().format('YYYY-MM-DD HH-mm-ss')
      replay_filename=dueltime
      if room.hostinfo.mode != 2
        for player,i in room.dueling_players
          replay_filename=replay_filename + (if i > 0 then " VS " else " ") + player.name
      else
        for player,i in room.dueling_players
          replay_filename=replay_filename + (if i > 0 then (if i == 2 then " VS " else " & ") else " ") + player.name
      replay_filename=replay_filename.replace(/[\/\\\?\*]/g, '_')+".yrp"
      duellog = {
        id: duel_log.duel_log.length + 1,
        time: dueltime,
        name: room.name + (if settings.modules.tournament_mode.show_info then (" (Duel:" + room.duel_count + ")") else ""),
        roomid: room.process_pid.toString(),
        cloud_replay_id: "R#"+room.cloud_replay_id,
        replay_filename: replay_filename,
        roommode: room.hostinfo.mode,
        players: (for player in room.dueling_players
          real_name: player.name_vpass,
          deckbuf: player.start_deckbuf.toString("base64"),
          deck: {
            main: player.main,
            side: player.side
          }
          pos: player.pos
          is_first: player.is_first
          name: player.name + (if settings.modules.tournament_mode.show_ip and !player.is_local then (" (IP: " + player.ip.slice(7) + ")") else "") + (if settings.modules.tournament_mode.show_info and not (room.hostinfo.mode == 2 and player.pos % 2 > 0) then (" (Score:" + room.scores[player.name_vpass] + " LP:" + (if player.lp? then player.lp else room.hostinfo.start_lp) + (if room.hostinfo.mode != 2 then (" Cards:" + (if player.card_count? then player.card_count else room.hostinfo.start_hand)) else "") + ")") else ""),
          winner: player.pos == room.winner
        )
      }
      duel_log.duel_log.unshift duellog
      setting_save(duel_log)
      fs.writeFile(settings.modules.tournament_mode.replay_path + replay_filename, buffer, (err)->
        if err then log.warn "SAVE REPLAY ERROR", replay_filename, err
      )
    if settings.modules.cloud_replay.enabled and settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.replay_safe
      ygopro.stoc_send_chat(client, "${cloud_replay_delay_part1}R##{room.cloud_replay_id}${cloud_replay_delay_part2}", ygopro.constants.COLORS.BABYBLUE)
    await return settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.block_replay_to_player or settings.modules.replay_delay and room.hostinfo.mode == 1
  else
    await return settings.modules.replay_delay and room.hostinfo.mode == 1

if settings.modules.random_duel.enabled
  setInterval ()->
    _async.each(ROOM_all, (room, done) ->
      if !(room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.random_type and room.last_active_time and room.waiting_for_player and room.get_disconnected_count() == 0 and (!settings.modules.side_timeout or room.duel_stage != ygopro.constants.DUEL_STAGE.SIDING) and !room.recovered)
        done()
        return
      time_passed = Math.floor((moment() - room.last_active_time) / 1000)
      #log.info time_passed
      if time_passed >= settings.modules.random_duel.hang_timeout
        room.last_active_time = moment()
        ROOM_ban_player(room.waiting_for_player.name, room.waiting_for_player.ip, "${random_ban_reason_AFK}")
        room.scores[room.waiting_for_player.name_vpass] = -9
        #log.info room.waiting_for_player.name, room.scores[room.waiting_for_player.name_vpass]
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        CLIENT_send_replays(room.waiting_for_player, room)
        CLIENT_kick(room.waiting_for_player)
      else if time_passed >= (settings.modules.random_duel.hang_timeout - 20) and not (time_passed % 10)
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${afk_warn_part1}#{settings.modules.random_duel.hang_timeout - time_passed}${afk_warn_part2}", ygopro.constants.COLORS.RED)
        ROOM_unwelcome(room, room.waiting_for_player, "${random_ban_reason_AFK}")
      done()
      return
    )
    return
  , 1000

if settings.modules.mycard.enabled
  setInterval ()->
    _async.each(ROOM_all, (room, done) ->
      if not (room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.arena and room.last_active_time and room.waiting_for_player and room.get_disconnected_count() == 0 and (!settings.modules.side_timeout or room.duel_stage != ygopro.constants.DUEL_STAGE.SIDING) and !room.recovered)
        done()
        return
      time_passed = Math.floor((moment() - room.last_active_time) / 1000)
      #log.info time_passed
      if time_passed >= settings.modules.random_duel.hang_timeout
        room.last_active_time = moment()
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        room.scores[room.waiting_for_player.name_vpass] = -9
        #log.info room.waiting_for_player.name, room.scores[room.waiting_for_player.name_vpass]
        CLIENT_send_replays(room.waiting_for_player, room)
        CLIENT_kick(room.waiting_for_player)
      else if time_passed >= (settings.modules.random_duel.hang_timeout - 20) and not (time_passed % 10)
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${afk_warn_part1}#{settings.modules.random_duel.hang_timeout - time_passed}${afk_warn_part2}", ygopro.constants.COLORS.RED)
      done()
      return
    )
    
    if true # settings.modules.arena_mode.punish_quit_before_match
      _async.each(ROOM_all, (room, done) ->
        if not (room and room.arena and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and room.get_playing_player().length < 2)
          done()
          return
        player = room.get_playing_player()[0]
        if player and player.join_time and !player.arena_quit_free
          waited_time = moment() - player.join_time
          if waited_time >= 30000
            ygopro.stoc_send_chat(player, "${arena_wait_timeout}", ygopro.constants.COLORS.BABYBLUE)
            player.arena_quit_free = true
          else if waited_time >= 5000 and waited_time < 6000
            ygopro.stoc_send_chat(player, "${arena_wait_hint}", ygopro.constants.COLORS.BABYBLUE)
        done()
        return
      )
    return
  , 1000

if settings.modules.heartbeat_detection.enabled
  setInterval ()->
    _async.each ROOM_all, (room, done)->
      if room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and (room.hostinfo.time_limit == 0 or room.duel_stage != ygopro.constants.DUEL_STAGE.DUELING) and !room.windbot
        _async.each(room.get_playing_player(), (player, _done)->
          if player and (room.duel_stage != ygopro.constants.DUEL_STAGE.SIDING or player.selected_preduel)
            CLIENT_heartbeat_register(player, true)
          _done()
        , done)
      else
        done()
    return
  , settings.modules.heartbeat_detection.interval

setInterval ()->
  current_time = moment()
  _async.each ROOM_all, (room, done)->
    if room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.hostinfo.auto_death and !room.auto_death_triggered and current_time - moment(room.start_time) > 60000 * room.hostinfo.auto_death
      room.auto_death_triggered = true
      room.start_death()
    done()

, 1000

# spawn windbot
windbot_looplimit = 0
windbot_process = global.windbot_process = null

spawn_windbot = global.spawn_windbot = () ->
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
    if windbot_looplimit < 1000 and !global.rebooted
      windbot_looplimit++
      spawn_windbot()
    return
  windbot_process.on 'exit', (code)->
    log.warn 'WindBot EXIT', code
    if windbot_looplimit < 1000 and !global.rebooted
      windbot_looplimit++
      spawn_windbot()
    return
  windbot_process.stdout.setEncoding('utf8')
  windbot_process.stdout.on 'data', (data)->
    log.info 'WindBot:', data
    return
  windbot_process.stderr.setEncoding('utf8')
  windbot_process.stderr.on 'data', (data)->
    log.warn 'WindBot Error:', data
    return
  return

if settings.modules.windbot.enabled and settings.modules.windbot.spawn
  spawn_windbot()

global.rebooted = false
#http
if settings.modules.http

  addCallback = (callback, text)->
    if not callback then return text
    return callback + "( " + text + " );"

  requestListener = (request, response)->
    parseQueryString = true
    u = url.parse(request.url, parseQueryString)
    #pass_validated = u.query.pass == settings.modules.http.password

    #console.log(u.query.username, u.query.pass)
    if u.pathname == '/api/getrooms'
      pass_validated = await auth.auth(u.query.username, u.query.pass, "get_rooms", "get_rooms", true)
      if !settings.modules.http.public_roomlist and !pass_validated
        response.writeHead(200)
        response.end(addCallback(u.query.callback, '{"rooms":[{"roomid":"0","roomname":"密码错误","needpass":"true"}]}'))
      else
        roomsjson = [];
        _async.each(ROOM_all, (room, done)->
          if !(room and room.established)
            done()
            return
          roomsjson.push({
            roomid: room.process_pid.toString(),
            roomname: if pass_validated then room.name else room.name.split('$', 2)[0],
            roommode: room.hostinfo.mode,
            needpass: (room.name.indexOf('$') != -1).toString(),
            users: _.sortBy((for player in room.players when player.pos?
              id: (-1).toString(),
              name: player.name,
              ip: if settings.modules.http.show_ip and pass_validated and !player.is_local then player.ip.slice(7) else null,
              status: if settings.modules.http.show_info and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and player.pos != 7 then (
                score: room.scores[player.name_vpass],
                lp: if player.lp? then player.lp else room.hostinfo.start_lp,
                cards: if room.hostinfo.mode != 2 then (if player.card_count? then player.card_count else room.hostinfo.start_hand) else null
              ) else null,
              pos: player.pos
            ), "pos"),
            istart: if room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN then (if settings.modules.http.show_info then ("Duel:" + room.duel_count + " " + (if room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING then "Siding" else "Turn:" + (if room.turn? then room.turn else 0) + (if room.death then "/" + (if room.death > 0 then room.death - 1 else "Death") else ""))) else 'start') else 'wait'
          })
          done()
        , ()->
          response.writeHead(200)
          response.end(addCallback(u.query.callback, JSON.stringify({rooms: roomsjson})))
        )


    else if u.pathname == '/api/duellog' and settings.modules.tournament_mode.enabled
      if !await auth.auth(u.query.username, u.query.pass, "duel_log", "duel_log")
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "[{name:'密码错误'}]"))
        return
      else
        response.writeHead(200)
        duellog = JSON.stringify duel_log.duel_log, null, 2
        response.end(addCallback(u.query.callback, duellog))

    else if u.pathname == '/api/archive.zip' and settings.modules.tournament_mode.enabled
      if !await auth.auth(u.query.username, u.query.pass, "download_replay", "download_replay_archive")
        response.writeHead(403)
        response.end("Invalid password.")
        return
      else
        try
          archive_name = moment().format('YYYY-MM-DD HH-mm-ss') + ".zip"
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
      if !await auth.auth(u.query.username, u.query.pass, "clear_duel_log", "clear_duel_log")
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "[{name:'密码错误'}]"))
        return
      else
        response.writeHead(200)
        if settings.modules.tournament_mode.log_save_path
          fs.writeFile(settings.modules.tournament_mode.log_save_path + 'duel_log.' + moment().format('YYYY-MM-DD HH-mm-ss') + '.json', JSON.stringify(duel_log, null, 2), (err) ->
            if err
              log.warn 'DUEL LOG SAVE ERROR', err
          )
        duel_log.duel_log = []
        setting_save(duel_log)
        response.end(addCallback(u.query.callback, "[{name:'Success'}]"))

    else if _.startsWith(u.pathname, '/api/replay') and settings.modules.tournament_mode.enabled
      if !await auth.auth(u.query.username, u.query.pass, "download_replay", "download_replay")
        response.writeHead(403)
        response.end("密码错误")
        return
      else
        getpath = null
        filename = null
        try
          getpath=u.pathname.split("/")
          filename=path.basename(decodeURIComponent(getpath.pop()))
        catch
          response.writeHead(404)
          response.end("bad filename")
          return
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
      #if !pass_validated
      #  response.writeHead(200)
      #  response.end(addCallback(u.query.callback, "['密码错误', 0]"))
      #  return

      if u.query.shout
        if !await auth.auth(u.query.username, u.query.pass, "shout", "shout")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        _async.each ROOM_all, (room)->
          if room and room.established
            ygopro.stoc_send_chat_to_room(room, u.query.shout, ygopro.constants.COLORS.YELLOW)
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['shout ok', '" + u.query.shout + "']"))

      else if u.query.stop
        if !await auth.auth(u.query.username, u.query.pass, "stop", "stop")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        if u.query.stop == 'false'
          u.query.stop = false
        response.writeHead(200)
        try
          await util.promisify(setting_change)(settings, 'modules:stop', u.query.stop)
          response.end(addCallback(u.query.callback, "['stop ok', '" + u.query.stop + "']"))
        catch err
          response.end(addCallback(u.query.callback, "['stop fail', '" + u.query.stop + "']"))

      else if u.query.welcome
        if !await auth.auth(u.query.username, u.query.pass, "change_settings", "change_welcome")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        try
          await util.promisify(setting_change)(settings, 'modules:welcome', u.query.welcome)
          response.end(addCallback(u.query.callback, "['welcome ok', '" + u.query.welcome + "']"))
        catch err
          response.end(addCallback(u.query.callback, "['welcome fail', '" + u.query.welcome + "']"))

      else if u.query.getwelcome
        if !await auth.auth(u.query.username, u.query.pass, "change_settings", "get_welcome")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['get ok', '" + settings.modules.welcome + "']"))

      else if u.query.loadtips
        if !await auth.auth(u.query.username, u.query.pass, "change_settings", "change_tips")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        load_tips((err)->
          response.writeHead(200)
          if(err)
            response.end(addCallback(u.query.callback, "['tip fail', '" + settings.modules.tips.get + "']"))
          else
            response.end(addCallback(u.query.callback, "['tip ok', '" +  settings.modules.tips.get + "']"))
        )

      else if u.query.loaddialogues
        if !await auth.auth(u.query.username, u.query.pass, "change_settings", "change_dialogues")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        load_dialogues((err)->
          response.writeHead(200)
          if(err)
            response.end(addCallback(u.query.callback, "['dialogues fail', '" + settings.modules.dialogues.get + "']"))
          else
            response.end(addCallback(u.query.callback, "['dialogues ok', '" +settings.modules.dialogues.get + "']"))
        )

      else if u.query.ban
        if !await auth.auth(u.query.username, u.query.pass, "ban_user", "ban_user")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        ban_user(u.query.ban, (err)->
          response.writeHead(200)
          if(err)
            response.end(addCallback(u.query.callback, "['ban fail', '" + u.query.ban + "']"))
          else
            response.end(addCallback(u.query.callback, "['ban ok', '" + u.query.ban + "']"))
        )

      else if u.query.kick
        if !await auth.auth(u.query.username, u.query.pass, "kick_user", "kick_user")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        ROOM_kick(u.query.kick, (err, found)->
          response.writeHead(200)
          if err
            response.end(addCallback(u.query.callback, "['kick fail', '" + u.query.kick + "']"))
          else if found
            response.end(addCallback(u.query.callback, "['kick ok', '" + u.query.kick + "']"))
          else
            response.end(addCallback(u.query.callback, "['room not found', '" + u.query.kick + "']"))
        )
        

      else if u.query.death
        if !await auth.auth(u.query.username, u.query.pass, "start_death", "start_death")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        death_room_found = false
        _async.each(ROOM_all, (room, done)->
          if !(room and (u.query.death == "all" or u.query.death == room.process_pid.toString() or u.query.death == room.name))
            done()
            return
          if room.start_death()
            death_room_found = true
          done()
          return
        , () ->
          response.writeHead(200)
          if death_room_found
            response.end(addCallback(u.query.callback, "['death ok', '" + u.query.death + "']"))
          else
            response.end(addCallback(u.query.callback, "['room not found', '" + u.query.death + "']"))
        )

      else if u.query.deathcancel
        if !await auth.auth(u.query.username, u.query.pass, "start_death", "cancel_death")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        death_room_found = false
        _async.each(rooms, (room, done)->
          if !(room and (u.query.deathcancel == "all" or u.query.deathcancel == room.process_pid.toString() or u.query.deathcancel == room.name))
            done()
            return
          if room.cancel_death()
            death_room_found = true
          done()
        , () ->
          response.writeHead(200)
          if death_room_found
            response.end(addCallback(u.query.callback, "['death cancel ok', '" + u.query.deathcancel + "']"))
          else
            response.end(addCallback(u.query.callback, "['room not found', '" + u.query.deathcancel + "']"))
        )

      else if u.query.reboot
        if !await auth.auth(u.query.username, u.query.pass, "stop", "reboot")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        ROOM_kick("all", (err, found)->
          global.rebooted = true
          if windbot_process
            windbot_process.kill()
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['reboot ok', '" + u.query.reboot + "']"))
          process.exit()
        )
        

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
    if settings.modules.http.websocket_roomlist and roomlist
      roomlist.init https_server, ROOM_all
    https_server.listen settings.modules.http.ssl.port

if not fs.existsSync('./plugins')
  fs.mkdirSync('./plugins')

plugin_list = fs.readdirSync("./plugins")
for plugin_filename in plugin_list
  plugin_path = process.cwd() + "/plugins/" + plugin_filename
  require(plugin_path)
  log.info("Plugin loaded:", plugin_filename)
