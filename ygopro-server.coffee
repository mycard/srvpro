# 标准库
net = require 'net'
http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'
exec = require('child_process').exec
spawn = require('child_process').spawn
util = require 'util'

# 三方库
_async = require('async')

_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports())

request = require 'request'

bunyan = require 'bunyan'
log = bunyan.createLogger name: "mycard"

moment = require 'moment'
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

merge = require 'deepmerge'

loadJSON = require('load-json-file').sync

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

setting_save = (settings, callback) ->
  if !callback
    callback = (err) ->
      if(err)
        log.warn("setting save fail", err.toString())
  fs.writeFile(settings.file, JSON.stringify(settings, null, 2), callback)
  return

setting_change = (settings, path, val, callback) ->
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
try
  config = loadJSON('./config/config.json')
catch
  config = {}
settings = merge(default_config, config, { arrayMerge: (destination, source) -> source })

auth = require './ygopro-auth.js'

#import old configs
imported = false
#import the old passwords to new admin user system
if settings.modules.http.password
  auth.add_user("olduser", settings.modules.http.password, true, {
        "get_rooms": true,
        "shout": true,
        "stop": true,
        "change_settings": true,
        "ban_user": true,
        "kick_user": true
  })
  delete settings.modules.http.password
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
  tips = loadJSON('./config/tips.json')
catch
  tips = default_data.tips
  setting_save(tips)
try
  dialogues = loadJSON('./config/dialogues.json')
catch
  dialogues = default_data.dialogues
  setting_save(dialogues)
try
  badwords = loadJSON('./config/badwords.json')
catch
  badwords = default_data.badwords
  setting_save(badwords)
try
  duel_log = loadJSON('./config/duel_log.json')
catch
  duel_log = default_data.duel_log
  setting_save(duel_log)

badwordR={}
badwordR.level0=new RegExp('(?:'+badwords.level0.join(')|(?:')+')','i');
badwordR.level1=new RegExp('(?:'+badwords.level1.join(')|(?:')+')','i');
badwordR.level1g=new RegExp('(?:'+badwords.level1.join(')|(?:')+')','ig');
badwordR.level2=new RegExp('(?:'+badwords.level2.join(')|(?:')+')','i');
badwordR.level3=new RegExp('(?:'+badwords.level3.join(')|(?:')+')','i');

moment_now = moment()
moment_now_string = moment_now.format()
moment_long_ago_string = moment().subtract(settings.modules.random_duel.hang_timeout - 19, 's')
setInterval ()->
  moment_now = moment()
  moment_now_string = moment_now.format()
  moment_long_ago_string = moment().subtract(settings.modules.random_duel.hang_timeout - 19, 's').format()
  return
, 500

try
  cppversion = parseInt(fs.readFileSync('ygopro/gframe/game.cpp', 'utf8').match(/PRO_VERSION = ([x\dABCDEF]+)/)[1], '16')
  setting_change(settings, "version", cppversion)
  log.info "ygopro version 0x"+settings.version.toString(16), "(from source code)"
catch
  #settings.version = settings.version_default
  log.info "ygopro version 0x"+settings.version.toString(16), "(from config)"
# load the lflist of current date
lflists = []
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

if settings.modules.windbot.enabled
  windbots = loadJSON(settings.modules.windbot.botlist).windbots
  real_windbot_server_ip = settings.modules.windbot.server_ip
  if !settings.modules.windbot.server_ip.includes("127.0.0.1")
    dns = require('dns')
    dns.lookup(settings.modules.windbot.server_ip,(err,addr) ->
      if(!err)
        real_windbot_server_ip = addr
    )

# 组件
ygopro = require './ygopro.js'

if settings.modules.i18n.auto_pick
  geoip = require('geoip-country-lite')

# 获取可用内存
memory_usage = 0
get_memory_usage = get_memory_usage = ()->
  prc_free = exec("free")
  if not prc_free
    log.warn 'get free failed!'
    return
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

ROOM_all = []
ROOM_players_oppentlist = {}
ROOM_players_banned = []
ROOM_players_scores = {}
ROOM_connected_ip = {}
ROOM_bad_ip = {}

# ban a user manually and permanently
ban_user = (name, callback) ->
  settings.ban.banned_user.push(name)
  setting_save(settings)
  bad_ip = []
  _async.eachSeries(ROOM_all, (room, done)-> 
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
        return
      , _done)
    , done)
  , callback)
  return

# automatically ban user to use random duel
ROOM_ban_player = (name, ip, reason, countadd = 1)->
  return if settings.modules.test_mode.no_ban_player
  bannedplayer = _.find ROOM_players_banned, (bannedplayer)->
    ip == bannedplayer.ip
  if bannedplayer
    bannedplayer.count = bannedplayer.count + countadd
    bantime = if bannedplayer.count > 3 then Math.pow(2, bannedplayer.count - 3) * 2 else 0
    bannedplayer.time = if moment_now < bannedplayer.time then moment(bannedplayer.time).add(bantime, 'm') else moment().add(bantime, 'm')
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
  _async.eachSeries(ROOM_all, (room, done)->
    if !(room and room.established and (name == "all" or name == room.process_pid.toString() or name == room.name))
      done()
      return
    found = true
    if room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
      room.scores[room.dueling_players[0].name_vpass] = 0
      room.scores[room.dueling_players[1].name_vpass] = 0
    room.kicked = true
    room.send_replays()
    room.process.kill()
    room.delete()
    done()
    return
  , (err)->
    callback(null, found)
    return
  )


ROOM_player_win = (name)->
  if !ROOM_players_scores[name]
    ROOM_players_scores[name]={win:0, lose:0, flee:0, combo:0}
  ROOM_players_scores[name].win = ROOM_players_scores[name].win + 1
  ROOM_players_scores[name].combo = ROOM_players_scores[name].combo + 1
  return

ROOM_player_lose = (name)->
  if !ROOM_players_scores[name]
    ROOM_players_scores[name]={win:0, lose:0, flee:0, combo:0}
  ROOM_players_scores[name].lose = ROOM_players_scores[name].lose + 1
  ROOM_players_scores[name].combo = 0
  return

ROOM_player_flee = (name)->
  if !ROOM_players_scores[name]
    ROOM_players_scores[name]={win:0, lose:0, flee:0, combo:0}
  ROOM_players_scores[name].flee = ROOM_players_scores[name].flee + 1
  ROOM_players_scores[name].combo = 0
  return

ROOM_player_get_score = (player)->
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

if settings.modules.max_rooms_count
  rooms_count=0
  get_rooms_count = ()->
    _rooms_count=0
    for room in ROOM_all when room and room.established
      _rooms_count++
    rooms_count=_rooms_count
    setTimeout get_rooms_count, 1000
    return
  setTimeout get_rooms_count, 1000

ROOM_find_or_create_by_name = (name, player_ip)->
  uname=name.toUpperCase()
  if settings.modules.windbot.enabled and (uname[0...2] == 'AI' or (!settings.modules.random_duel.enabled and uname == ''))
    return ROOM_find_or_create_ai(name)
  if settings.modules.random_duel.enabled and (uname == '' or uname == 'S' or uname == 'M' or uname == 'T')
    return ROOM_find_or_create_random(uname, player_ip)
  if room = ROOM_find_by_name(name)
    return room
  else if memory_usage >= 90 or (settings.modules.max_rooms_count and rooms_count >= settings.modules.max_rooms_count)
    return null
  else
    return new Room(name)

ROOM_find_or_create_random = (type, player_ip)->
  bannedplayer = _.find ROOM_players_banned, (bannedplayer)->
    return player_ip == bannedplayer.ip
  if bannedplayer
    if bannedplayer.count > 6 and moment_now < bannedplayer.time
      return {"error": "${random_banned_part1}#{bannedplayer.reasons.join('${random_ban_reason_separator}')}${random_banned_part2}#{moment(bannedplayer.time).fromNow(true)}${random_banned_part3}"}
    if bannedplayer.count > 3 and moment_now < bannedplayer.time and bannedplayer.need_tip and type != 'T'
      bannedplayer.need_tip = false
      return {"error": "${random_deprecated_part1}#{bannedplayer.reasons.join('${random_ban_reason_separator}')}${random_deprecated_part2}#{moment(bannedplayer.time).fromNow(true)}${random_deprecated_part3}"}
    else if bannedplayer.need_tip
      bannedplayer.need_tip = false
      return {"error": "${random_warn_part1}#{bannedplayer.reasons.join('${random_ban_reason_separator}')}${random_warn_part2}"}
    else if bannedplayer.count > 2
      bannedplayer.need_tip = true
  max_player = if type == 'T' then 4 else 2
  playerbanned = (bannedplayer and bannedplayer.count > 3 and moment_now < bannedplayer.time)
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
  else if memory_usage < 90 and not (settings.modules.max_rooms_count and rooms_count >= settings.modules.max_rooms_count)
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

ROOM_find_or_create_ai = (name)->
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

ROOM_find_by_name = (name)->
  result = _.find ROOM_all, (room)->
    return room and room.name == name
  return result

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

CLIENT_kick = (client) ->
  if !client
    return false
  client.system_kicked = true
  client.destroy()
  return true

SERVER_kick = (server) ->
  if !server
    return false
  server.system_kicked = true
  server.destroy()
  return true

CLIENT_send_replays = (client, room) ->
  return false unless settings.modules.replay_delay and room.replays.length and room.hostinfo.mode == 1 and !client.replays_sent and !client.closed
  client.replays_sent = true
  i = 0
  for buffer in room.replays
    ++i
    if buffer
      ygopro.stoc_send_chat(client, "${replay_hint_part1}" + i + "${replay_hint_part2}", ygopro.constants.COLORS.BABYBLUE)
      ygopro.stoc_send(client, "REPLAY", buffer)
  return true

SOCKET_flush_data = (sk, datas) ->
  if !sk or sk.closed
    return false
  for buffer in datas
    sk.write(buffer)
  datas.splice(0, datas.length)
  return true

class Room
  constructor: (name, @hostinfo) ->
    @name = name
    @players = []
    @established = false
    @watcher_buffers = []
    @watchers = []
    @random_type = ''
    @welcome = ''
    @scores = {}
    @decks = {}
    @duel_count = 0
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
      @hostinfo.rule = 5
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

      if (rule.match /(^|，|,)(SC|CCG)(，|,|$)/)
        @hostinfo.rule = 2
        @hostinfo.lflist = -1

      if (rule.match /(^|，|,)(OT|TCG)(，|,|$)/)
        @hostinfo.rule = 5

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
        @hostinfo.rule = 4

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

    @hostinfo.replay_mode = 0 # 0x1: Save the replays in file. 0x2: Block the replays to observers.

    if @hostinfo.mode == 1 and settings.modules.replay_delay
      @hostinfo.replay_mode |= 0x2

    param = [0, @hostinfo.lflist, @hostinfo.rule, @hostinfo.mode, @hostinfo.duel_rule,
      (if @hostinfo.no_check_deck then 'T' else 'F'), (if @hostinfo.no_shuffle_deck then 'T' else 'F'),
      @hostinfo.start_lp, @hostinfo.start_hand, @hostinfo.draw_count, @hostinfo.time_limit, @hostinfo.replay_mode]

    try
      @process = spawn './ygopro', param, {cwd: 'ygopro'}
      @process_pid = @process.pid
      @process.on 'error', (err)=>
        log.warn 'CREATE ROOM ERROR', err
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
    catch e
      log.warn 'CREATE ROOM FAIL', e
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

    @watcher_buffers = []
    @players = []
    @watcher.destroy() if @watcher
    @deleted = true
    index = _.indexOf(ROOM_all, this)
    ROOM_all[index] = null unless index == -1
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
      SERVER_kick(client.server)
    else
      #log.info(client.name, @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN, @disconnector, @random_type, @players.length)
      index = _.indexOf(@players, client)
      @players.splice(index, 1) unless index == -1
      if @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and @disconnector != 'server' and client.pos < 4
        @finished = true
        @scores[client.name_vpass] = -9
        if @random_type and not client.flee_free
          ROOM_ban_player(client.name, client.ip, "${random_ban_reason_flee}")
          if settings.modules.random_duel.record_match_scores and @random_type == 'M'
            ROOM_player_flee(client.name_vpass)
      if @players.length and !(@windbot and client.is_host)
        left_name = (if settings.modules.hide_name and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN then "********" else client.name)
        ygopro.stoc_send_chat_to_room this, "#{left_name} ${left_game}" + if error then ": #{error}" else ''
        #client.room = null
      else
        @send_replays()
        @process.kill()
        #client.room = null
        this.delete()
      SERVER_kick(client.server)
    return

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
      if room
        room.disconnect(client)
      else
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
        room.disconnect(client, error)
      else
        SERVER_kick(client.server)
    return

  client.on 'timeout', ()->
    client.destroy()
    return

  server.on 'close', (had_error) ->
    server.closed = true unless server.closed
    if !server.client
      return
    #log.info "server closed", server.client.name, had_error
    room=ROOM_all[server.client.rid]
    #log.info "server close", server.client.ip, ROOM_connected_ip[server.client.ip]
    room.disconnector = 'server' if room and !server.system_kicked
    unless server.client.closed
      ygopro.stoc_send_chat(server.client, "${server_closed}", ygopro.constants.COLORS.RED)
      #if room and settings.modules.replay_delay
      #  room.send_replays()
      CLIENT_kick(server.client)
    return

  server.on 'error', (error)->
    server.closed = error
    if !server.client
      return
    #log.info "server error", client.name, error
    room=ROOM_all[server.client.rid]
    #log.info "server err close", client.ip, ROOM_connected_ip[client.ip]
    room.disconnector = 'server' if room and !server.system_kicked
    unless server.client.closed
      ygopro.stoc_send_chat(server.client, "${server_error}: #{error}", ygopro.constants.COLORS.RED)
      #if room and settings.modules.replay_delay
      #  room.send_replays()
      CLIENT_kick(server.client)
    return

  if client.ip == undefined or ROOM_bad_ip[client.ip] > 5 or ROOM_connected_ip[client.ip] > 10
    log.info 'BAD IP', client.ip if client.ip
    CLIENT_kick(client)
    return

  # 需要重构
  # 客户端到服务端(ctos)协议分析

  client.pre_establish_buffers = new Array()

  client.on 'data', (ctos_buffer) ->
    if client.is_post_watcher
      room=ROOM_all[client.rid]
      room.watcher.write ctos_buffer if room
    else
      #ctos_buffer = Buffer.alloc(0)
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
            b = ctos_buffer.slice(3, ctos_message_length - 1 + 3)
            info = null
            struct = ygopro.structs[ygopro.proto_structs.CTOS[ygopro.constants.CTOS[ctos_proto]]]
            if struct
              struct._setBuff(b)
              info = _.clone(struct.fields)
            if ygopro.ctos_follows[ctos_proto]
              result = ygopro.ctos_follows[ctos_proto].callback b, info, client, client.server, datas
              if result and ygopro.ctos_follows[ctos_proto].synchronous
                cancel = true
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
          CLIENT_kick(client)
          break
      if !client.server
        return
      if client.established
        client.server.write buffer for buffer in datas
      else
        client.pre_establish_buffers.push buffer for buffer in datas

    return

  # 服务端到客户端(stoc)
  server.on 'data', (stoc_buffer)->
    #stoc_buffer = Buffer.alloc(0)
    stoc_message_length = 0
    stoc_proto = 0
    #stoc_buffer = Buffer.concat([stoc_buffer, data], stoc_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

    #unless ygopro.stoc_follows[stoc_proto] and ygopro.stoc_follows[stoc_proto].synchronous
    #server.client.write data
    datas = []

    looplimit = 0

    while true
      if stoc_message_length == 0
        if stoc_buffer.length >= 2
          stoc_message_length = stoc_buffer.readUInt16LE(0)
        else
          log.warn("bad stoc_buffer length", server.client.ip) unless stoc_buffer.length == 0
          break
      else if stoc_proto == 0
        if stoc_buffer.length >= 3
          stoc_proto = stoc_buffer.readUInt8(2)
        else
          log.warn("bad stoc_proto length", server.client.ip)
          break
      else
        if stoc_buffer.length >= 2 + stoc_message_length
          #console.log "STOC", ygopro.constants.STOC[stoc_proto]
          cancel = false
          b = stoc_buffer.slice(3, stoc_message_length - 1 + 3)
          info = null
          struct = ygopro.structs[ygopro.proto_structs.STOC[ygopro.constants.STOC[stoc_proto]]]
          if struct
            struct._setBuff(b)
            info = _.clone(struct.fields)
          if ygopro.stoc_follows[stoc_proto]
            result = ygopro.stoc_follows[stoc_proto].callback b, info, server.client, server, datas
            if result and ygopro.stoc_follows[stoc_proto].synchronous
              cancel = true
          datas.push stoc_buffer.slice(0, 2 + stoc_message_length) unless cancel
          stoc_buffer = stoc_buffer.slice(2 + stoc_message_length)
          stoc_message_length = 0
          stoc_proto = 0
        else
          log.warn("bad stoc_message length", server.client.ip)
          break

      looplimit++
      #log.info(looplimit)
      if looplimit > 800
        log.info("error stoc", server.client.name)
        server.destroy()
        break
    if server.client and !server.client.closed
      server.client.write buffer for buffer in datas

    return
  return
.listen settings.port, ->
  log.info "server started", settings.port
  return

if settings.modules.stop
  log.info "NOTE: server not open due to config, ", settings.modules.stop

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
  struct = ygopro.structs["CTOS_PlayerInfo"]
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
  return false

ygopro.ctos_follow 'JOIN_GAME', false, (buffer, info, client, server, datas)->
#log.info info
  info.pass=info.pass.trim()
  client.pass = info.pass
  if settings.modules.stop
    ygopro.stoc_die(client, settings.modules.stop)
  else if info.pass == "Marshtomp" or info.pass == "the Big Brother"
    ygopro.stoc_die(client, "${bad_user_name}")

  else if info.version != settings.version # and (info.version < 9020 or settings.version != 4927) #强行兼容23333版
    ygopro.stoc_send_chat(client, (if info.version < settings.version then settings.modules.update else settings.modules.wait_update), ygopro.constants.COLORS.RED)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 4
      code: settings.version
    }
    CLIENT_kick(client)

  else if !info.pass.length and !settings.modules.random_duel.enabled and !settings.modules.windbot.enabled
    ygopro.stoc_die(client, "${blank_room_name}")

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

  else if badwordR.level3.test(client.name)
    log.warn("BAD NAME LEVEL 3", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level3}")

  else if badwordR.level2.test(client.name)
    log.warn("BAD NAME LEVEL 2", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level2}")

  else if badwordR.level1.test(client.name)
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
      ygopro.stoc_die(client, settings.modules.full)
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
  return

ygopro.stoc_follow 'JOIN_GAME', false, (buffer, info, client, server, datas)->
  #欢迎信息
  room=ROOM_all[client.rid]
  return unless room
  if settings.modules.welcome
    ygopro.stoc_send_chat(client, settings.modules.welcome, ygopro.constants.COLORS.GREEN)
  if room.welcome
    ygopro.stoc_send_chat(client, room.welcome, ygopro.constants.COLORS.BABYBLUE)
  if room.welcome2
    ygopro.stoc_send_chat(client, room.welcome2, ygopro.constants.COLORS.PINK)
  if settings.modules.random_duel.record_match_scores and room.random_type == 'M'
    ygopro.stoc_send_chat_to_room(room, ROOM_player_get_score(client), ygopro.constants.COLORS.GREEN)
    for player in room.players when player.pos != 7 and player != client
      ygopro.stoc_send_chat(client, ROOM_player_get_score(player), ygopro.constants.COLORS.GREEN)

  if settings.modules.cloud_replay.enable_halfway_watch and !room.watcher and !room.hostinfo.no_watch
    room.watcher = watcher = net.connect room.port, ->
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
  return

# 登场台词
load_dialogues = (callback) ->
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
  return

if settings.modules.dialogues.get
  load_dialogues()

ygopro.stoc_follow 'GAME_MSG', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  msg = buffer.readInt8(0)
  msg_name = ygopro.constants.MSG[msg]

  if (msg >= 10 and msg < 30) or msg == 132 or (msg >= 140 and msg <= 144) #SELECT和ANNOUNCE开头的消息
    room.waiting_for_player = client
    room.last_active_time = moment_now_string
  #log.info("#{msg_name}等待#{room.waiting_for_player.name}")

  #log.info 'MSG', msg_name
  if msg_name == 'START'
    playertype = buffer.readUInt8(1)
    client.is_first = !(playertype & 0xf)
    client.lp = room.hostinfo.start_lp
    room.duel_stage = ygopro.constants.DUEL_STAGE.DUELING
    if client.pos == 0
      room.turn = 0
      room.duel_count++
    if client.is_first and (room.hostinfo.mode != 2 or client.pos == 0 or client.pos == 2)
      room.first_list.push(client.name_vpass)

  #ygopro.stoc_send_chat_to_room(room, "LP跟踪调试信息: #{client.name} 初始LP #{client.lp}")

  if msg_name == 'NEW_TURN'
    if client.pos == 0
      room.turn++
    if client.surrend_confirm
      client.surrend_confirm = false
      ygopro.stoc_send_chat(client, "${surrender_canceled}", ygopro.constants.COLORS.BABYBLUE)

  if msg_name == 'WIN' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first or pos == 2 or room.duel_stage != ygopro.constants.DUEL_STAGE.DUELING
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    reason = buffer.readUInt8(2)
    #log.info {winner: pos, reason: reason}
    #room.duels.push {winner: pos, reason: reason}
    room.winner = pos
    room.turn = 0
    room.duel_stage = ygopro.constants.DUEL_STAGE.END
    if room and !room.finished and room.dueling_players[pos]
      room.winner_name = room.dueling_players[pos].name_vpass
      #log.info room.dueling_players, pos
      room.scores[room.winner_name] = room.scores[room.winner_name] + 1
      if room.match_kill
        room.match_kill = false
        room.scores[room.winner_name] = 99

  if msg_name == 'MATCH_KILL' and client.pos == 0
    room.match_kill = true

  #lp跟踪
  if msg_name == 'DAMAGE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    room.dueling_players[pos].lp = 0 if room.dueling_players[pos].lp < 0
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "${lp_low_opponent}", ygopro.constants.COLORS.PINK)

  if msg_name == 'RECOVER' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp += val

  if msg_name == 'LPUPDATE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp = val

  if msg_name == 'PAY_LPCOST' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    room.dueling_players[pos].lp = 0 if room.dueling_players[pos].lp < 0
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "${lp_low_self}", ygopro.constants.COLORS.PINK)

  #登场台词
  if settings.modules.dialogues.enabled
    if msg_name == 'SUMMONING' or msg_name == 'SPSUMMONING' or msg_name == 'CHAINING'
      card = buffer.readUInt32LE(1)
      trigger_location = buffer.readUInt8(6)
      if dialogues.dialogues[card] and (msg_name != 'CHAINING' or (trigger_location & 0x8) and client.ready_trap)
        for line in _.lines dialogues.dialogues[card][Math.floor(Math.random() * dialogues.dialogues[card].length)]
          ygopro.stoc_send_chat(client, line, ygopro.constants.COLORS.PINK)
    if msg_name == 'POS_CHANGE'
      loc = buffer.readUInt8(6)
      ppos = buffer.readUInt8(8)
      cpos = buffer.readUInt8(9)
      client.ready_trap = !!(loc & 0x8) and !!(ppos & 0xa) and !!(cpos & 0x5)
    else if msg_name != 'UPDATE_CARD' and msg_name != 'WAITING'
      client.ready_trap = false
  return false

#房间管理
ygopro.ctos_follow 'HS_TOOBSERVER', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if room.hostinfo.no_watch
    ygopro.stoc_send_chat(client, "${watch_denied_room}", ygopro.constants.COLORS.RED)
    return true
  return false

ygopro.ctos_follow 'HS_KICK', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  for player in room.players
    if player and player.pos == info.pos and player != client
      client.kick_count = if client.kick_count then client.kick_count+1 else 1
      if client.kick_count>=5 and room.random_type
        ygopro.stoc_send_chat_to_room(room, "#{client.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        ROOM_ban_player(player.name, player.ip, "${random_ban_reason_zombie}")
        CLIENT_kick(client)
        return true
      ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_player}", ygopro.constants.COLORS.RED)
  return false

ygopro.stoc_follow 'TYPE_CHANGE', true, (buffer, info, client, server, datas)->
  selftype = info.type & 0xf
  is_host = ((info.type >> 4) & 0xf) != 0
  client.is_host = is_host
  client.pos = selftype
  #console.log "TYPE_CHANGE to #{client.name}:", info, selftype, is_host
  return false

ygopro.stoc_follow 'HS_PLAYER_ENTER', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return false unless room and settings.modules.hide_name and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN
  pos = info.pos
  if pos < 4 and pos != client.pos
    struct = ygopro.structs["STOC_HS_PlayerEnter"]
    struct._setBuff(buffer)
    struct.set("name", "********")
    buffer = struct.buffer
  return false

ygopro.stoc_follow 'HS_PLAYER_CHANGE', false, (buffer, info, client, server, datas)->
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
      setTimeout (()-> wait_room_start(ROOM_all[client.rid], settings.modules.random_duel.ready_time);return), 1000
  return

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

load_tips = (callback)->
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
  return

if settings.modules.tips.get
  load_tips()
  setInterval ()->
    for room in ROOM_all when room and room.established
      ygopro.stoc_send_random_tip_to_room(room) if room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING or room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN
    return
  , 30000

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN #first start
    room.duel_stage = ygopro.constants.DUEL_STAGE.FINGER
    room.start_time = moment().format()
    room.turn = 0
    room.dueling_players = []
    for player in room.players when player.pos != 7
      room.dueling_players[player.pos] = player
      room.scores[player.name_vpass] = 0
      if room.random_type == 'T'
        # 双打房不记录匹配过
        ROOM_players_oppentlist[player.ip] = null
  else if room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING and client.pos < 4 # side deck verified
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
      deck_name = moment_now.format('YYYY-MM-DD HH-mm-ss') + ' ' + room.process_pid + ' ' + client.pos + ' ' + client.ip.slice(7) + ' ' + client.name.replace(/[\/\\\?\*]/g, '_')
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

ygopro.ctos_follow 'SURRENDER', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or room.hostinfo.mode == 2
    return true
  if room.random_type and room.turn < 3 and not client.flee_free and not settings.modules.test_mode.surrender_anytime and not (room.random_type=='M' and settings.modules.random_duel.record_match_scores)
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

ygopro.ctos_follow 'CHAT', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  msg = _.trim(info.msg)
  cancel = _.startsWith(msg, "/")
  room.last_active_time = moment_now_string unless cancel or not room.random_type or room.duel_stage == ygopro.constants.DUEL_STAGE.FINGER or room.duel_stage == ygopro.constants.DUEL_STAGE.FIRSTGO or room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING
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
      ygopro.stoc_send_chat(client, "${chat_order_roomname}")
      ygopro.stoc_send_chat(client, "${chat_order_windbot}") if settings.modules.windbot.enabled
      ygopro.stoc_send_chat(client, "${chat_order_tip}") if settings.modules.tips.enabled

    when '/tip'
      ygopro.stoc_send_random_tip(client) if settings.modules.tips.enabled

    when '/ai'
      if settings.modules.windbot.enabled and client.is_host and room.random_type != 'M'
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
  if badwordR.level3.test(msg)
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
  else if badwordR.level2.test(msg)
    log.warn "BAD WORD LEVEL 2", client.name, client.ip, oldmsg, RegExp.$1
    report_to_big_brother room.name, client.name, client.ip, 2, oldmsg, RegExp.$1
    client.abuse_count=client.abuse_count+3
    ygopro.stoc_send_chat(client, "${chat_warn_level2}", ygopro.constants.COLORS.RED)
    cancel = true
  else
    msg = msg.replace(badwordR.level1g,'**')
    if oldmsg != msg
      log.warn "BAD WORD LEVEL 1", client.name, client.ip, oldmsg, RegExp.$1
      report_to_big_brother room.name, client.name, client.ip, 1, oldmsg, RegExp.$1
      client.abuse_count=client.abuse_count+1
      ygopro.stoc_send_chat(client, "${chat_warn_level1}")
      struct = ygopro.structs["chat"]
      struct._setBuff(buffer)
      struct.set("msg", msg)
      buffer = struct.buffer
    else if badwordR.level0.test(msg)
      log.info "BAD WORD LEVEL 0", client.name, client.ip, oldmsg, RegExp.$1
      report_to_big_brother room.name, client.name, client.ip, 0, oldmsg, RegExp.$1
  if client.abuse_count>=2
    ROOM_unwelcome(room, client, "${random_ban_reason_abuse}")
  if client.abuse_count>=5
    ygopro.stoc_send_chat_to_room(room, "#{client.name} ${chat_banned}", ygopro.constants.COLORS.RED)
    ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}")
  return cancel

ygopro.ctos_follow 'UPDATE_DECK', true, (buffer, info, client, server, datas)->
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
  if room.random_type
    if client.pos == 0
      room.waiting_for_player = room.waiting_for_player2
    room.last_active_time = moment_now_string
  return false

ygopro.ctos_follow 'RESPONSE', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and room.random_type
  room.last_active_time = moment_now_string
  return

ygopro.ctos_follow 'HAND_RESULT', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and room.random_type
  if client.pos == 0
    room.waiting_for_player = room.waiting_for_player2
  room.last_active_time = moment_long_ago_string
  return

ygopro.ctos_follow 'TP_RESULT', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and room.random_type
  room.last_active_time = moment_now_string
  return

ygopro.stoc_follow 'SELECT_HAND', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if client.pos == 0
    room.duel_stage = ygopro.constants.DUEL_STAGE.FINGER
  return unless room.random_type
  if client.pos == 0
    room.waiting_for_player = client
  else
    room.waiting_for_player2 = client
  room.last_active_time = moment_long_ago_string
  return

ygopro.stoc_follow 'SELECT_TP', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  room.duel_stage = ygopro.constants.DUEL_STAGE.FIRSTGO
  return unless room.random_type
  room.waiting_for_player = client
  room.last_active_time = moment_now_string
  return

ygopro.stoc_follow 'CHANGE_SIDE', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if client.pos == 0
    room.duel_stage = ygopro.constants.DUEL_STAGE.SIDING
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
  if room.random_type
    if client.pos == 0
      room.waiting_for_player = client
    else
      room.waiting_for_player2 = client
    room.last_active_time = moment_now_string
  return

ygopro.stoc_follow 'REPLAY', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return settings.modules.replay_delay unless room
  if !room.replays[room.duel_count - 1]
    # console.log("Replay saved: ", room.duel_count - 1, client.pos)
    room.replays[room.duel_count - 1] = buffer
  if room.has_ygopro_error
    if client.pos == 0
      dueltime=moment_now.format('YYYY-MM-DD HH-mm-ss')
      replay_filename=dueltime
      if room.hostinfo.mode != 2
        for player,i in room.dueling_players
          replay_filename=replay_filename + (if i > 0 then " VS " else " ") + player.name
      else
        for player,i in room.dueling_players
          replay_filename=replay_filename + (if i > 0 then (if i == 2 then " VS " else " & ") else " ") + player.name
      replay_filename=replay_filename.replace(/[\/\\\?\*]/g, '_')+".yrp"
      fs.writeFile(settings.modules.tournament_mode.replay_path + replay_filename, buffer, (err)->
        if err then log.warn "SAVE REPLAY ERROR", replay_filename, err
      )
  return settings.modules.replay_delay and room.hostinfo.mode == 1

if settings.modules.random_duel.enabled
  check_room_timeout = ()->
    _async.eachSeries(ROOM_all, (room, done) ->
      if !(room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.random_type and room.last_active_time and room.waiting_for_player and (!settings.modules.side_timeout or room.duel_stage != ygopro.constants.DUEL_STAGE.SIDING))
        done()
        return
      time_passed = Math.floor(moment_now.diff(room.last_active_time) / 1000)
      #log.info time_passed
      if time_passed >= settings.modules.random_duel.hang_timeout
        room.last_active_time = moment_now_string
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
    , ()->
      setTimeout check_room_timeout, 1000
      return
    )
    return
  setTimeout check_room_timeout, 1000

# spawn windbot
windbot_looplimit = 0
windbot_process = null

spawn_windbot = () ->
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
    if windbot_looplimit < 1000 and !rebooted
      windbot_looplimit++
      spawn_windbot()
    return
  windbot_process.on 'exit', (code)->
    log.warn 'WindBot EXIT', code
    if windbot_looplimit < 1000 and !rebooted
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

rebooted = false
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
        _async.eachSeries(ROOM_all, (room, done)->
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
                lp: if player.lp? then player.lp else room.hostinfo.start_lp
              ) else null,
              pos: player.pos
            ), "pos"),
            istart: if room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN then (if settings.modules.http.show_info then ("Duel:" + room.duel_count + " " + (if room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING then "Siding" else "Turn:" + (if room.turn? then room.turn else 0))) else 'start') else 'wait'
          })
          done()
          return
        , ()->
          response.writeHead(200)
          response.end(addCallback(u.query.callback, JSON.stringify({rooms: roomsjson})))
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
        _async.eachSeries ROOM_all, (room, done)->
          if room and room.established
            ygopro.stoc_send_chat_to_room(room, u.query.shout, ygopro.constants.COLORS.YELLOW)
          done()
          return
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

      else if u.query.reboot
        if !await auth.auth(u.query.username, u.query.pass, "stop", "reboot")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        ROOM_kick("all", (err, found)->
          rebooted = true
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
    https_server.listen settings.modules.http.ssl.port
