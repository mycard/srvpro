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
qs = require "querystring"
zlib = require 'zlib'
axios = require 'axios'
osu = require 'node-os-utils'

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

loadJSONAsync = require('load-json-file')

util = require("util")

Q = require("q")

#heapdump = require 'heapdump'

checkFileExists = (path) =>
  try
    await fs.promises.access(path)
    return true
  catch e
    return false

createDirectoryIfNotExists = (dirPath) =>
  try
    if dirPath and !await checkFileExists(dirPath)
      await fs.promises.mkdir(dirPath, {recursive: true})
  catch e
    log.warn("Failed to create directory #{path}: #{e.toString()}")

setting_save = global.setting_save = (settings) ->
  try
    await fs.promises.writeFile(settings.file, JSON.stringify(settings, null, 2))
  catch e
    log.warn("setting save fail", e.toString())
  return

setting_get = global.setting_get = (settings, path) ->
  path = path.split(':')
  if path.length == 0
    return settings[path[0]]
  else
    target = settings
    while path.length > 1
      key = path.shift()
      target = target[key]
    key = path.shift()
    return target[key]

setting_change = global.setting_change = (settings, path, val, noSave) ->
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
  if !noSave
    await setting_save(settings)
  return

importOldConfig = () ->
  try
    oldconfig=await loadJSONAsync('./config.user.json')
    if oldconfig.tips
      oldtips = {}
      oldtips.file = './config/tips.json'
      oldtips.tips = oldconfig.tips
      await fs.promises.writeFile(oldtips.file, JSON.stringify(oldtips, null, 2))
      delete oldconfig.tips
    if oldconfig.dialogues
      olddialogues = {}
      olddialogues.file = './config/dialogues.json'
      olddialogues.dialogues = oldconfig.dialogues
      await fs.promises.writeFile(olddialogues.file, JSON.stringify(olddialogues, null, 2))
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
      await fs.promises.writeFile(oldbadwords.file, JSON.stringify(oldbadwords, null, 2))
      delete oldconfig.ban.badword_level0
      delete oldconfig.ban.badword_level1
      delete oldconfig.ban.badword_level2
      delete oldconfig.ban.badword_level3
    if not _.isEmpty(oldconfig)
  # log.info oldconfig
      await fs.promises.writeFile('./config/config.json', JSON.stringify(oldconfig, null, 2))
      log.info 'imported old config from config.user.json'
    await fs.promises.rename('./config.user.json', './config.user.bak')
  catch e
    log.info e unless e.code == 'ENOENT'

auth = global.auth = require './ygopro-auth.js'
ygopro = global.ygopro = require './ygopro.js'
roomlist = null

settings = {}
tips = null
dialogues = null
badwords = null
badwordR = null
lflists = global.lflists = []
real_windbot_server_ip = null
long_resolve_cards = []
ReplayParser = null
athleticChecker = null
users_cache = {}
geoip = null
dataManager = null
windbots = []
disconnect_list = {} # {old_client, old_server, room_id, timeout, deckbuf}

moment_now = global.moment_now = null
moment_now_string = global.moment_now_string = null
moment_long_ago_string = global.moment_long_ago_string = null

rooms_count = 0

challonge = null

class ResolveData
  constructor: (@func) ->
  resolved: false
  resolve: (err, data) ->
    if @resolved
      return false
    @resolved = true
    @func(err, data)
    return true


loadLFList = (path) ->
  try
    for list in (await fs.promises.readFile(path, 'utf8')).match(/!.*/g)
      date=list.match(/!([\d\.]+)/)
      continue unless date
      lflists.push({date: moment(list.match(/!([\d\.]+)/)[1], 'YYYY.MM.DD').utcOffset("-08:00"), tcg: list.indexOf('TCG') != -1})
  catch

init = () ->
  log.info('Reading config.')
  await createDirectoryIfNotExists("./config")
  await importOldConfig()
  defaultConfig = await loadJSONAsync('./data/default_config.json')
  if await checkFileExists("./config/config.json")
    try
      config = await loadJSONAsync('./config/config.json')
    catch e
      console.error("Failed reading config: ", e.toString())
      process.exit(1)
  else
    config = {}
  settings = global.settings = merge(defaultConfig, config, { arrayMerge: (destination, source) -> source })
  #import old configs
  imported = false
  #reset http.quick_death_rule from true to 1
  if settings.modules.http.quick_death_rule == true
    settings.modules.http.quick_death_rule = 1
    imported = true
  else if settings.modules.http.quick_death_rule == false
    settings.modules.http.quick_death_rule = 2
    imported = true
  #import the old passwords to new admin user system
  if settings.modules.http.password
    log.info('Migrating http user.')
    await auth.add_user("olduser", settings.modules.http.password, true, {
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
    log.info('Migrating tournament user.')
    await auth.add_user("tournament", settings.modules.tournament_mode.password, true, {
      "duel_log": true,
      "download_replay": true,
      "clear_duel_log": true,
      "deck_dashboard_read": true,
      "deck_dashboard_write": true,
    })
    delete settings.modules.tournament_mode.password
    imported = true
  if settings.modules.pre_util.password
    log.info('Migrating pre-dash user.')
    await auth.add_user("pre", settings.modules.pre_util.password, true, {
      "pre_dashboard": true
    })
    delete settings.modules.pre_util.password
    imported = true
  if settings.modules.update_util.password
    log.info('Migrating update-dash user.')
    await auth.add_user("update", settings.modules.update_util.password, true, {
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
  if settings.modules.challonge.options
    settings.modules.challonge.api_key = settings.modules.challonge.options.apiKey
    delete settings.modules.challonge.options
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
  keysFromEnv = Object.keys(process.env).filter((key) => key.startsWith('SRVPRO_'))
  if keysFromEnv.length > 0
    log.info('Migrating settings from environment variables.')
    for key in keysFromEnv
      settingKey = key.slice(7).replace(/__/g, ':')
      val = process.env[key]
      valFromDefault = setting_get(defaultConfig, settingKey)
      if Array.isArray(valFromDefault)
        val = val.split(',')
        valFromDefault = valFromDefault[0]
      if typeof valFromDefault == 'number'
        val = parseFloat(val)
      if typeof valFromDefault == 'boolean'
        val = (val != 'false') && (val != '0')
      setting_change(settings, settingKey, val, true)
    imported = true

  if imported
    log.info('Saving migrated settings.')
    await setting_save(settings)
  if settings.modules.mysql.enabled
    global.PrimaryKeyType = if settings.modules.mysql.db.type == 'sqlite' then 'integer' else 'bigint'
    DataManager = require('./data-manager/DataManager.js').DataManager
    dataManager = global.dataManager = new DataManager(settings.modules.mysql.db, log)
    log.info('Connecting to database.')
    await dataManager.init()
  else
    log.warn("Some functions may be limited without MySQL .")
    if settings.modules.cloud_replay.enabled
      settings.modules.cloud_replay.enabled = false
      await setting_save(settings)
      log.warn("Cloud replay cannot be enabled because no MySQL.")
    if settings.modules.tournament_mode.enable_recover
      settings.modules.tournament_mode.enable_recover = false
      await setting_save(settings)
      log.warn("Recover mode cannot be enabled because no MySQL.")
    if settings.modules.chat_color.enabled
      settings.modules.chat_color.enabled = false
      await setting_save(settings)
      log.warn("Chat color cannot be enabled because no MySQL.")
    if settings.modules.random_duel.record_match_scores
      settings.modules.random_duel.record_match_scores = false
      await setting_save(settings)
      log.warn("Cannot record random match scores because no MySQL.")

  # 读取数据
  log.info('Loading data.')
  default_data = await loadJSONAsync('./data/default_data.json')
  try
    tips = global.tips = await loadJSONAsync('./config/tips.json')
  catch
    tips = global.tips = default_data.tips
    await setting_save(tips)
  try
    dialogues = global.dialogues = await loadJSONAsync('./config/dialogues.json')
  catch
    dialogues = global.dialogues = default_data.dialogues
    await setting_save(dialogues)
  try
    badwords = global.badwords = await loadJSONAsync('./config/badwords.json')
  catch
    badwords = global.badwords = default_data.badwords
    await setting_save(badwords)
  if settings.modules.chat_color.enabled and await checkFileExists('./config/chat_color.json')
    try
      chat_color = await loadJSONAsync('./config/chat_color.json')
      if chat_color
        log.info("Migrating chat color.")
        await dataManager.migrateChatColors(chat_color.save_list);
        await fs.promises.rename('./config/chat_color.json', './config/chat_color.json.bak')
        log.info("Chat color migrated.")
    catch
  try
    log.info("Reading YGOPro version.")
    cppversion = parseInt((await fs.promises.readFile('ygopro/gframe/game.cpp', 'utf8')).match(/PRO_VERSION = ([x\dABCDEF]+)/)[1], '16')
    await setting_change(settings, "version", cppversion)
    log.info "ygopro version 0x"+settings.version.toString(16), "(from source code)"
  catch
  #settings.version = settings.version_default
    log.info "ygopro version 0x"+settings.version.toString(16), "(from config)"
  # load the lflist of current date
  log.info("Reading banlists.")
  await loadLFList('ygopro/expansions/lflist.conf')
  await loadLFList('ygopro/lflist.conf')

  badwordR = global.badwordR = {}
  badwordR.level0=new RegExp('(?:'+badwords.level0.join(')|(?:')+')','i');
  badwordR.level1=new RegExp('(?:'+badwords.level1.join(')|(?:')+')','i');
  badwordR.level1g=new RegExp('(?:'+badwords.level1.join(')|(?:')+')','ig');
  badwordR.level2=new RegExp('(?:'+badwords.level2.join(')|(?:')+')','i');
  badwordR.level3=new RegExp('(?:'+badwords.level3.join(')|(?:')+')','i');

  setInterval ()->
    moment_now = global.moment_now = moment()
    moment_now_string = global.moment_now_string = moment_now.format()
    moment_long_ago_string = global.moment_long_ago_string = moment().subtract(settings.modules.random_duel.hang_timeout - 19, 's').format()
    return
  , 500
  
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

  if settings.modules.windbot.enabled
    log.info("Reading bot list.")
    windbots = global.windbots = (await loadJSONAsync(settings.modules.windbot.botlist)).windbots
    real_windbot_server_ip = global.real_windbot_server_ip = settings.modules.windbot.server_ip
    if !settings.modules.windbot.server_ip.includes("127.0.0.1")
      dns = require('dns')
      real_windbot_server_ip = global.real_windbot_server_ip = await util.promisify(dns.lookup)(settings.modules.windbot.server_ip)
  if settings.modules.heartbeat_detection.enabled
    long_resolve_cards = global.long_resolve_cards = await loadJSONAsync('./data/long_resolve_cards.json')

  if settings.modules.tournament_mode.enable_recover
    ReplayParser = global.ReplayParser = require "./Replay.js"

  if settings.modules.athletic_check.enabled
    AthleticChecker = require("./athletic-check.js").AthleticChecker
    athleticChecker = global.athleticChecker = new AthleticChecker(settings.modules.athletic_check)

  if settings.modules.http.websocket_roomlist
    roomlist = global.roomlist = require './roomlist.js'
  if settings.modules.i18n.auto_pick
    geoip = require('geoip-country-lite')

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
      postData = qs.stringify({
        ak: settings.modules.arena_mode.init_post.accesskey,
        arena: settings.modules.arena_mode.mode
      })
      try
        log.info("Sending arena init post.")
        await axios.post(settings.modules.arena_mode.init_post.url + "?" + postData)
      catch e
        log.warn 'ARENA INIT POST ERROR', e

  if settings.modules.challonge.enabled
    Challonge = require('./challonge').Challonge
    challonge = new Challonge(settings.modules.challonge)

  if settings.modules.tips.get
    load_tips()

  if settings.modules.tips.enabled
    if settings.modules.tips.interval
      setInterval ()->
        for room in ROOM_all when room and room.established and room.duel_stage != ygopro.constants.END
          ygopro.stoc_send_random_tip_to_room(room) if room.duel_stage != ygopro.constants.DUEL_STAGE.DUELING
        return
      , settings.modules.tips.interval
    if settings.modules.tips.interval_ingame
      setInterval ()->
        for room in ROOM_all when room and room.established and room.duel_stage != ygopro.constants.END
          ygopro.stoc_send_random_tip_to_room(room) if room.duel_stage == ygopro.constants.DUEL_STAGE.DUELING
        return
      , settings.modules.tips.interval_ingame
  
  if settings.modules.dialogues.get
    load_dialogues()

  if settings.modules.random_duel.post_match_scores and settings.modules.mysql.enabled
    setInterval(()->
      scores = await dataManager.getRandomScoreTop10()

      try
        await axios.post(settings.modules.random_duel.post_match_scores, qs.stringify({
          accesskey: settings.modules.random_duel.post_match_accesskey,
          rank: JSON.stringify(scores)
        }))
      catch e
        log.warn 'RANDOM SCORE POST ERROR', e.toString()

      return
    , 60000)

  if settings.modules.random_duel.enabled
    setInterval ()->
      for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.random_type and room.last_active_time and room.waiting_for_player and room.get_disconnected_count() == 0 and (!settings.modules.side_timeout or room.duel_stage != ygopro.constants.DUEL_STAGE.SIDING) and !room.recovered
        time_passed = Math.floor(moment_now.diff(room.last_active_time) / 1000)
        #log.info time_passed, moment_now_string
        if time_passed >= settings.modules.random_duel.hang_timeout
          room.refreshLastActiveTime()
          await ROOM_ban_player(room.waiting_for_player.name, room.waiting_for_player.ip, "${random_ban_reason_AFK}")
          room.scores[room.waiting_for_player.name_vpass] = -9
          #log.info room.waiting_for_player.name, room.scores[room.waiting_for_player.name_vpass]
          ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
          CLIENT_send_replays_and_kick(room.waiting_for_player, room)
        else if time_passed >= (settings.modules.random_duel.hang_timeout - 20) and not (time_passed % 10)
          ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${afk_warn_part1}#{settings.modules.random_duel.hang_timeout - time_passed}${afk_warn_part2}", ygopro.constants.COLORS.RED)
          ROOM_unwelcome(room, room.waiting_for_player, "${random_ban_reason_AFK}")
      return
    , 1000

  if settings.modules.mycard.enabled
    setInterval ()->
      for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.arena and room.last_active_time and room.waiting_for_player and room.get_disconnected_count() == 0 and (!settings.modules.side_timeout or room.duel_stage != ygopro.constants.DUEL_STAGE.SIDING) and !room.recovered
        time_passed = Math.floor(moment_now.diff(room.last_active_time) / 1000)
        #log.info time_passed
        if time_passed >= settings.modules.random_duel.hang_timeout
          room.refreshLastActiveTime()
          ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
          room.scores[room.waiting_for_player.name_vpass] = -9
          #log.info room.waiting_for_player.name, room.scores[room.waiting_for_player.name_vpass]
          CLIENT_send_replays_and_kick(room.waiting_for_player, room)
        else if time_passed >= (settings.modules.random_duel.hang_timeout - 20) and not (time_passed % 10)
          ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${afk_warn_part1}#{settings.modules.random_duel.hang_timeout - time_passed}${afk_warn_part2}", ygopro.constants.COLORS.RED)
      
      if true # settings.modules.arena_mode.punish_quit_before_match
        for room in ROOM_all when room and room.arena and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and room.get_playing_player().length < 2
          player = room.get_playing_player()[0]
          if player and player.join_time and !player.arena_quit_free
            waited_time = moment_now.diff(player.join_time)
            if waited_time >= 30000
              ygopro.stoc_send_chat(player, "${arena_wait_timeout}", ygopro.constants.COLORS.BABYBLUE)
              player.arena_quit_free = true
            else if waited_time >= 5000 and waited_time < 6000
              ygopro.stoc_send_chat(player, "${arena_wait_hint}", ygopro.constants.COLORS.BABYBLUE)
      return
    , 1000

  if settings.modules.heartbeat_detection.enabled
    setInterval ()->
      for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and (room.hostinfo.time_limit == 0 or room.duel_stage != ygopro.constants.DUEL_STAGE.DUELING) and !room.windbot
        for player in room.get_playing_player() when player and (room.duel_stage != ygopro.constants.DUEL_STAGE.SIDING or player.selected_preduel)
          CLIENT_heartbeat_register(player, true)
      return
    , settings.modules.heartbeat_detection.interval

  if settings.modules.windbot.enabled and settings.modules.windbot.spawn
    spawn_windbot()

  setInterval ()->
    for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.hostinfo.auto_death and !room.auto_death_triggered and moment_now.diff(room.start_time) > 60000 * room.hostinfo.auto_death
      room.auto_death_triggered = true
      room.start_death()

  , 1000

  log.info("Starting server.")
  net.createServer(netRequestHandler).listen settings.port, ->
    log.info "server started", settings.port
    return

  if settings.modules.stop
    log.info "NOTE: server not open due to config, ", settings.modules.stop

  http_server = http.createServer(httpRequestListener)
  main_http_server = http_server

  if settings.modules.http.ssl.enabled
    https = require 'https'
    httpsOptions =
      cert: await fs.promises.readFile(settings.modules.http.ssl.cert)
      key: await fs.promises.readFile(settings.modules.http.ssl.key)
    https_server = https.createServer(httpsOptions, httpRequestListener)
    https_server.listen settings.modules.http.ssl.port
    main_http_server = https_server
  
  if settings.modules.http.websocket_roomlist and roomlist
    roomlist.init main_http_server, ROOM_all
  http_server.listen settings.modules.http.port

  if settings.modules.neos.enabled
    ws = require 'ws'
    neosHttpServer = null
    if settings.modules.http.ssl.enabled
      neosHttpServer = https.createServer(httpsOptions)
    else
      neosHttpServer = http.createServer()
    neosWsServer = new ws.WebSocketServer({server: neosHttpServer})
    neosWsServer.on 'connection', neosRequestListener
    neosHttpServer.listen settings.modules.neos.port

  mkdirList = [
    "./plugins",
    settings.modules.tournament_mode.deck_path,
    settings.modules.tournament_mode.replay_path,
    settings.modules.tournament_mode.log_save_path,
    settings.modules.deck_log.local
  ]
  
  for dirPath in mkdirList
    await createDirectoryIfNotExists(dirPath)

  plugin_list = await fs.promises.readdir("./plugins")
  for plugin_filename in plugin_list
    plugin_path = process.cwd() + "/plugins/" + plugin_filename
    require(plugin_path)
    log.info("Plugin loaded:", plugin_filename)

  return

# 获取可用内存
memory_usage = global.memory_usage = 0
get_memory_usage = global.get_memory_usage = ()->
  memoryInfo = await osu.mem.info()
  percentUsed = 100 - memoryInfo.freeMemPercentage
  # console.log(percentUsed)
  memory_usage = global.memory_usage = percentUsed
  return
get_memory_usage()
setInterval(get_memory_usage, 3000)

ROOM_all = global.ROOM_all = []
ROOM_players_oppentlist = global.ROOM_players_oppentlist = {}
ROOM_connected_ip = global.ROOM_connected_ip = {}
ROOM_bad_ip = global.ROOM_bad_ip = {}

# ban a user manually and permanently
ban_user = global.ban_user = (name) ->
  if !settings.modules.mysql.enabled
    throw "MySQL is not enabled"
  bans = [dataManager.getBan(name, null)]
  for room in ROOM_all when room and room.established
    for playerType in ["players", "watchers"]
      for player in room[playerType] when player.name == name or bans.find((ban) => player.ip == ban.ip)
        bans.push(dataManager.getBan(name, player.ip))
        ROOM_bad_ip[player.ip]=99
        ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        CLIENT_send_replays_and_kick(player, room)
  for ban in bans
    await dataManager.banPlayer(ban)
  return

# automatically ban user to use random duel
ROOM_ban_player = global.ROOM_ban_player = (name, ip, reason, countadd = 1)->
  return if settings.modules.test_mode.no_ban_player or !settings.modules.mysql.enabled
  await dataManager.randomDuelBanPlayer(ip, reason, countadd)
  return

ROOM_kick = (name, callback)->
  found = false
  _async.each(ROOM_all, (room, done)->
    if !(room and room.established and (name == "all" or name == room.process_pid.toString() or name == room.name))
      done()
      return
    found = true
    room.terminate()
    done()
  , (err)->
    callback(null, found)
    return
  )


ROOM_player_win = global.ROOM_player_win = (name)->
  if !settings.modules.mysql.enabled
    return
  await dataManager.randomDuelPlayerWin(name)
  return

ROOM_player_lose = global.ROOM_player_lose = (name)->
  if !settings.modules.mysql.enabled
    return
  await dataManager.randomDuelPlayerLose(name)
  return

ROOM_player_flee = global.ROOM_player_flee = (name)->
  if !settings.modules.mysql.enabled
    return
  await dataManager.randomDuelPlayerFlee(name)
  return

ROOM_player_get_score = global.ROOM_player_get_score = (player)->
  if !settings.modules.mysql.enabled
    return ""
  return await dataManager.getRandomDuelScoreDisplay(player.name_vpass)

ROOM_find_or_create_by_name = global.ROOM_find_or_create_by_name = (name, player_ip)->
  uname=name.toUpperCase()
  if settings.modules.windbot.enabled and (uname[0...2] == 'AI' or (!settings.modules.random_duel.enabled and uname == ''))
    return ROOM_find_or_create_ai(name)
  if settings.modules.random_duel.enabled and (uname == '' or uname == 'S' or uname == 'M' or uname == 'T')
    return await ROOM_find_or_create_random(uname, player_ip)
  if room = ROOM_find_by_name(name)
    return room
  else if memory_usage >= 90 or (settings.modules.max_rooms_count and rooms_count >= settings.modules.max_rooms_count)
    return null
  else
    room = new Room(name)
    if room.recover_duel_log_id
      success = await room.initialize_recover()
      if !success
        return {"error": "${cloud_replay_no}"}
    return room

ROOM_find_or_create_random = global.ROOM_find_or_create_random = (type, player_ip)->
  if settings.modules.mysql.enabled
    randomDuelBanRecord = await dataManager.getRandomDuelBan(player_ip)
    if randomDuelBanRecord
      if randomDuelBanRecord.count > 6 and moment_now.isBefore(randomDuelBanRecord.time)
        return {"error": "${random_banned_part1}#{randomDuelBanRecord.reasons.join('${random_ban_reason_separator}')}${random_banned_part2}#{moment(randomDuelBanRecord.time).fromNow(true)}${random_banned_part3}"}
      if randomDuelBanRecord.count > 3 and moment_now.isBefore(randomDuelBanRecord.time) and randomDuelBanRecord.getNeedTip() and type != 'T'
        randomDuelBanRecord.setNeedTip(false)
        await dataManager.updateRandomDuelBan(randomDuelBanRecord)
        return {"error": "${random_deprecated_part1}#{randomDuelBanRecord.reasons.join('${random_ban_reason_separator}')}${random_deprecated_part2}#{moment(randomDuelBanRecord.time).fromNow(true)}${random_deprecated_part3}"}
      else if randomDuelBanRecord.getNeedTip()
        randomDuelBanRecord.setNeedTip(false)
        await dataManager.updateRandomDuelBan(randomDuelBanRecord)
        return {"error": "${random_warn_part1}#{randomDuelBanRecord.reasons.join('${random_ban_reason_separator}')}${random_warn_part2}"}
      else if randomDuelBanRecord.count > 2
        randomDuelBanRecord.setNeedTip(true)
        await dataManager.updateRandomDuelBan(randomDuelBanRecord)
  max_player = if type == 'T' then 4 else 2
  playerbanned = (randomDuelBanRecord and randomDuelBanRecord.count > 3 and moment_now < randomDuelBanRecord.time)
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
  if settings.modules.reconnect.enabled and client.isClosed
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
  unless disconnect_info and disconnect_info.deckbuf
    return false
  room = ROOM_all[disconnect_info.room_id]
  if !room
    CLIENT_reconnect_unregister(client)
    return false
  if deckbuf and deckbuf.compare(disconnect_info.deckbuf) != 0
    return false
  return true

CLIENT_get_kick_reconnect_target = global.CLIENT_get_kick_reconnect_target = (client, deckbuf) ->
  for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and !room.windbot
    for player in room.get_playing_player() when !player.isClosed and player.name == client.name and (settings.modules.challonge.enabled or player.pass == client.pass) and (settings.modules.mycard.enabled or settings.modules.tournament_mode.enabled or player.ip == client.ip or (client.vpass and client.vpass == player.vpass)) and (!deckbuf or deckbuf.compare(player.start_deckbuf) == 0)
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
    room.refreshLastActiveTime()
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
    room.refreshLastActiveTime()
  CLIENT_import_data(client, player, room)
  CLIENT_send_reconnect_info(client, client.server, room)
  #console.log("#{client.name} ${reconnect_to_game}")
  ygopro.stoc_send_chat_to_room(room, "#{client.name} ${reconnect_to_game}")
  CLIENT_reconnect_unregister(client, true)
  return

CLIENT_heartbeat_unregister = global.CLIENT_heartbeat_unregister = (client) ->
  if !settings.modules.heartbeat_detection.enabled or !client.heartbeat_timeout
    return false
  clearTimeout(client.heartbeat_timeout)
  delete client.heartbeat_timeout
  #log.info(2, client.name)
  return true

CLIENT_heartbeat_register = global.CLIENT_heartbeat_register = (client, send) ->
  if !settings.modules.heartbeat_detection.enabled or client.isClosed or client.is_post_watcher or client.pre_reconnecting or client.reconnecting or client.waiting_for_last or client.pos > 3 or client.heartbeat_protected
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
    client.destroy() unless client.isClosed or client.heartbeat_responsed
    return
  , settings.modules.heartbeat_detection.wait_time)
  #log.info(1, client.name)
  return true

CLIENT_is_banned_by_mc = global.CLIENT_is_banned_by_mc = (client) ->
  return client.ban_mc and client.ban_mc.banned and moment_now.isBefore(client.ban_mc.until)

CLIENT_send_replays = global.CLIENT_send_replays = (client, room) ->
  return false unless settings.modules.replay_delay and not (settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.block_replay_to_player) and room.replays.length and room.hostinfo.mode == 1 and !client.replays_sent and !client.isClosed
  client.replays_sent = true
  i = 0
  for buffer in room.replays
    ++i
    if buffer
      await ygopro.stoc_send_chat(client, "${replay_hint_part1}" + i + "${replay_hint_part2}", ygopro.constants.COLORS.BABYBLUE)
      await ygopro.stoc_send(client, "REPLAY", buffer)
  return true

CLIENT_send_replays_and_kick = global.CLIENT_send_replays_and_kick = (client, room) ->
  await CLIENT_send_replays(client, room)
  CLIENT_kick(client)
  return

SOCKET_flush_data = global.SOCKET_flush_data = (sk, datas) ->
  if !sk or sk.isClosed
    return false
  while datas.length
    buffer = datas.shift()
    await ygopro.helper.send(sk, buffer)
  return true

getSeedTimet = global.getSeedTimet = (count) ->
  return _.range(count).map(() => 0)

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
    @cloud_replay_id = Math.floor(Math.random()*Number.MAX_SAFE_INTEGER)
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
      @hostinfo.rule = 5
      @hostinfo.lflist = -1
      @hostinfo.time_limit = 999

    else if (param = name.match /^(\d)(\d)([12345TF])(T|F)(T|F)(\d+),(\d+),(\d+)/i)
      @hostinfo.rule = parseInt(param[1])
      @hostinfo.mode = parseInt(param[2])
      @hostinfo.duel_rule = (if parseInt(param[3]) then parseInt(param[3]) else (if param[3] == 'T' then 3 else 5))
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
        @hostinfo.rule = 5

      if (rule.match /(^|，|,)(SC|CN|CCG|CHINESE)(，|,|$)/)
        @hostinfo.rule = 2
        @hostinfo.lflist = -1

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

      if (rule.match /(^|，|,)(CUSTOM|DIY)(，|,|$)/)
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
        @recover_duel_log_id = parseInt(param[3])
        @recover_buffers = [[], [], [], []]
        @welcome = "${recover_hint}"

    @hostinfo.replay_mode = 0

    if settings.modules.tournament_mode.enabled # 0x1: Save the replays in file
      @hostinfo.replay_mode |= 0x1
    if (settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.block_replay_to_player) or (@hostinfo.mode == 1 and settings.modules.replay_delay) # 0x2: Block the replays to observers
      @hostinfo.replay_mode |= 0x2
    if settings.modules.tournament_mode.enabled or @arena # 0x4: Save chat in cloud replay
      @hostinfo.replay_mode |= 0x4

    if !@recovered
      @spawn()

  spawn: (firstSeed) ->
    param = [0, @hostinfo.lflist, @hostinfo.rule, @hostinfo.mode, @hostinfo.duel_rule,
      (if @hostinfo.no_check_deck then 'T' else 'F'), (if @hostinfo.no_shuffle_deck then 'T' else 'F'),
      @hostinfo.start_lp, @hostinfo.start_hand, @hostinfo.draw_count, @hostinfo.time_limit, @hostinfo.replay_mode]

    if firstSeed
      param.push(firstSeed)
      seeds = getSeedTimet(2)
      param.push(seeds[i]) for i in [0...2]
    else
      seeds = getSeedTimet(3)
      param.push(seeds[i]) for i in [0...3]

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
        roomlist.create(this) if !@windbot and settings.modules.http.websocket_roomlist
        @port = parseInt data
        _.each @players, (player)=>
          player.server.connect @port, '127.0.0.1', ->
            await ygopro.helper.send(player.server, buffer) for buffer in player.pre_establish_buffers
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
          await @send_replays()
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
    if settings.modules.arena_mode.enabled and @arena
      #log.info 'SCORE', score_array, @start_time
      end_time = moment_now_string
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
          if response.statusCode >= 300
            log.warn 'SCORE POST FAIL', response.statusCode, response.statusMessage, @name, body
          #else
          #  log.info 'SCORE POST OK', response.statusCode, response.statusMessage, @name, body
        return

    if settings.modules.challonge.enabled and @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and @hostinfo.mode != 2 and !@kicked
      room_name = @name
      @post_challonge_score()
    if @player_datas.length and settings.modules.cloud_replay.enabled
      replay_id = @cloud_replay_id
      if @has_ygopro_error
        log_rep_id = true
      recorder_buffer=Buffer.concat(@recorder_buffers)
      player_datas = @player_datas
      zlib.deflate recorder_buffer, (err, replay_buffer) ->
        dataManager.saveCloudReplay(replay_id, replay_buffer, player_datas).catch((err) ->
          log.warn("Replay save error: R##{replay_id} #{err.toString()}")
        )
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

  initialize_recover: ->
    @recover_duel_log = await dataManager.getDuelLogFromId(@recover_duel_log_id)
    #console.log(@recover_duel_log, fs.existsSync(settings.modules.tournament_mode.replay_path + @recover_duel_log.replayFileName))
    if !@recover_duel_log || !fs.existsSync(settings.modules.tournament_mode.replay_path + @recover_duel_log.replayFileName)
      @terminate()
      return false
    try
      @recover_replay = await ReplayParser.fromFile(settings.modules.tournament_mode.replay_path + @recover_duel_log.replayFileName)
      @spawn(@recover_replay.header.seed)
      return true
    catch e
      log.warn("LOAD RECOVER REPLAY FAIL", e.toString())
      @terminate()
      return false



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
    for player in @get_playing_player() when player.isClosed
      found++
    return found

  get_challonge_score: ->
    if !settings.modules.challonge.enabled or @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or @hostinfo.mode == 2
      return null
    challonge_duel_log = {}
    if @scores[@dueling_players[0].name_vpass] > @scores[@dueling_players[1].name_vpass]
      challonge_duel_log.winner_id = @dueling_players[0].challonge_info.id
    else if @scores[@dueling_players[0].name_vpass] < @scores[@dueling_players[1].name_vpass]
      challonge_duel_log.winner_id = @dueling_players[1].challonge_info.id
    else
      challonge_duel_log.winner_id = "tie"
    if settings.modules.challonge.post_detailed_score
      if @dueling_players[0].challonge_info.id == @challonge_info.player1_id and @dueling_players[1].challonge_info.id == @challonge_info.player2_id
        challonge_duel_log.scores_csv = @scores[@dueling_players[0].name_vpass] + "-" + @scores[@dueling_players[1].name_vpass]
      else if @dueling_players[1].challonge_info.id == @challonge_info.player1_id and @dueling_players[0].challonge_info.id == @challonge_info.player2_id
        challonge_duel_log.scores_csv = @scores[@dueling_players[1].name_vpass] + "-" + @scores[@dueling_players[0].name_vpass]
      else
        challonge_duel_log.scores_csv = "0-0"
        log.warn("Score mismatch.", @name)
    else
      if challonge_duel_log.winner_id == @challonge_info.player1_id
        challonge_duel_log.scores_csv = "1-0"
      else if challonge_duel_log.winner_id == @challonge_info.player2_id
        challonge_duel_log.scores_csv = "0-1"
      else
        challonge_duel_log.scores_csv = "0-0"
    return challonge_duel_log

  post_challonge_score: (noWinner) ->
    matchResult = @get_challonge_score()
    if noWinner
      delete matchResult.winner_id
    challonge.putScore(@challonge_info.id, matchResult)

  get_roomlist_hostinfo: () -> # Just for supporting websocket roomlist in old MyCard client....
    #ret = _.clone(@hostinfo)
    #ret.enable_priority = (@hostinfo.duel_rule != 5)
    #return ret
    return @hostinfo

  send_replays: () ->
    return false unless settings.modules.replay_delay and @replays.length and @hostinfo.mode == 1
    send_tasks = []
    for player in @players when player
      send_tasks.push CLIENT_send_replays(player, this)
    for player in @watchers when player
      send_tasks.push CLIENT_send_replays(player, this)
    await Promise.all send_tasks
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
    client.join_time = moment_now_string
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
        await ygopro.helper.send(client.server, buffer) for buffer in client.pre_establish_buffers
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
          if @players.length == 2 and @arena == 'athletic' and !client.arena_quit_free
            @scores[client.name_vpass] = -9
        @arena_score_handled = true
      index = _.indexOf(@players, client)
      @players.splice(index, 1) unless index == -1
      if @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and @disconnector != 'server' and client.pos < 4
        @finished = true
        if !@finished_by_death
          @scores[client.name_vpass] = -9
          if @random_type and not client.flee_free and (!settings.modules.reconnect.enabled or @get_disconnected_count() == 0) and not client.kicked_by_system and not client.kicked_by_player
            ROOM_ban_player(client.name, client.ip, "${random_ban_reason_flee}")
            if settings.modules.random_duel.record_match_scores and @random_type == 'M'
              ROOM_player_flee(client.name_vpass)
      if @players.length and !(@windbot and client.is_host) and !(@arena and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and client.pos <= 3)
        left_name = (if settings.modules.hide_name and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN then "********" else client.name)
        ygopro.stoc_send_chat_to_room this, "#{left_name} ${left_game}" + if error then ": #{error}" else ''
        roomlist.update(this) if !@windbot and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and settings.modules.http.websocket_roomlist
        #client.room = null
      else
        await @send_replays()
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
            await CLIENT_send_replays(@dueling_players[oppo_pos - win_pos], this) if @hostinfo.mode == 1
            await ygopro.stoc_send(@dueling_players[oppo_pos - win_pos], 'DUEL_END')
            await ygopro.stoc_send(@dueling_players[oppo_pos - win_pos + 1], 'DUEL_END') if @hostinfo.mode == 2
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
  
  terminate: ->
    if @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
      @scores[@dueling_players[0].name_vpass] = 0
      @scores[@dueling_players[1].name_vpass] = 0
    @kicked = true
    await @send_replays()
    if @process
      try
        @process.kill()
      catch e
    @delete()
  
  finish_recover: (fail) ->
    if fail
      ygopro.stoc_send_chat_to_room(this, "${recover_fail}", ygopro.constants.COLORS.RED)
      @terminate()
    else
      ygopro.stoc_send_chat_to_room(this, "${recover_success}", ygopro.constants.COLORS.BABYBLUE)
      @recovering = false
      for player in @get_playing_player()
        for buffer in @recover_buffers[player.pos]
          ygopro.stoc_send(player, "GAME_MSG", buffer)

  check_athletic: ->
    players = @get_playing_player()
    room = this
    await Promise.all(players.map((player) ->
      main = _.clone(player.main)
      side = _.clone(player.side)
      using_athletic = await athleticChecker.checkAthletic({main: main, side: side})
      if !using_athletic.success
        log.warn("GET ATHLETIC FAIL", player.name, using_athletic.message)
      else if using_athletic.athletic
        ygopro.stoc_send_chat_to_room(room, "#{player.name}${using_athletic_deck}", ygopro.constants.COLORS.BABYBLUE)
      return
    ))
    await return
  
  join_post_watch: (client) ->
    if @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
      if settings.modules.cloud_replay.enable_halfway_watch and !@hostinfo.no_watch
        client.setTimeout(300000) #连接后超时5分钟
        client.rid = _.indexOf(ROOM_all, this)
        client.is_post_watcher = true
        ygopro.stoc_send_chat_to_room(this, "#{client.name} ${watch_join}")
        @watchers.push client
        ygopro.stoc_send_chat(client, "${watch_watching}", ygopro.constants.COLORS.BABYBLUE)
        for buffer in @watcher_buffers
          await ygopro.helper.send(client, buffer)
        return true
      else
        ygopro.stoc_die(client, "${watch_denied}")
        return false
    else
      return false

  join_player: (client) ->
    if @error
      ygopro.stoc_die(client, @error)
      return false
    if @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
      return @join_post_watch(client)
    if @hostinfo.no_watch and @players.length >= (if @hostinfo.mode == 2 then 4 else 2)
      ygopro.stoc_die(client, "${watch_denied_room}")
      return true
    if @challonge_info
      for player in @get_playing_player() when player and player != client and player.challonge_info.id == client.challonge_info.id
        ygopro.stoc_die(client, "${challonge_player_already_in}")
        return false
    client.setTimeout(300000) #连接后超时5分钟
    client.rid = _.indexOf(ROOM_all, this)
    @connect(client)
    return true

  refreshLastActiveTime: (longAgo) ->
    if longAgo
      @last_active_time = moment_long_ago_string
    else
      @last_active_time = moment_now_string

  addRecorderBuffer: (buffer) ->
    if settings.modules.cloud_replay.enabled
      @recorder_buffers.push buffer
    return
  
  recordChatMessage: (msg, player) ->
    for line in ygopro.split_chat_lines(msg, player, settings.modules.i18n.default)
      chat_buf = ygopro.helper.prepareMessage("STOC_CHAT", {
        player: player
        msg: line
      })
      if settings.modules.cloud_replay.enabled and (@arena or settings.modules.tournament_mode.enabled)
        @addRecorderBuffer(chat_buf)
      @watcher_buffers.push chat_buf
    return

# 网络连接
netRequestHandler = (client) ->
  if !client.isWs
    client.ip = client.remoteAddress
  client.is_local = client.ip and (client.ip.includes('127.0.0.1') or client.ip.includes(real_windbot_server_ip))

  connect_count = ROOM_connected_ip[client.ip] or 0
  if !settings.modules.test_mode.no_connect_count_limit and !client.is_local
    connect_count++
  ROOM_connected_ip[client.ip] = connect_count
  #log.info "connect", client.ip, ROOM_connected_ip[client.ip]

  if ROOM_bad_ip[client.ip] > 5 or ROOM_connected_ip[client.ip] > 10
    log.info 'BAD IP', client.ip
    client.destroy()
    return

  # server stand for the connection to ygopro server process
  server = new net.Socket()
  client.server = server
  server.client = client

  client.setTimeout(2000) #连接前超时2秒

  # 释放处理
  closeHandler = (error) ->
    #log.info "client closed", client.name, error, client.isClosed
    #log.info "disconnect", client.ip, ROOM_connected_ip[client.ip]
    if client.isClosed
      return
    room=ROOM_all[client.rid]
    connect_count = ROOM_connected_ip[client.ip]
    if connect_count > 0
      connect_count--
    ROOM_connected_ip[client.ip] = connect_count
    client.isClosed = true
    if settings.modules.heartbeat_detection.enabled
      CLIENT_heartbeat_unregister(client)
    if room
      if !CLIENT_reconnect_register(client, client.rid, error)
        room.disconnect(client, error)
    else if !client.had_new_reconnection
      SERVER_kick(client.server)
    return
  
  if client.isWs
    client.on 'close', (code, reason) ->
      closeHandler()
  else
    client.on 'close', (had_error) ->
      closeHandler(had_error ? 'unknown' : undefined)
    client.on 'timeout', ()->
      unless settings.modules.reconnect.enabled and (disconnect_list[CLIENT_get_authorize_key(client)] or client.had_new_reconnection)
        client.destroy()
      return
  client.on 'error', closeHandler


  server.on 'close', (had_error) ->
    server.isClosed = true unless server.isClosed
    if !server.client
      return
    #log.info "server isClosed", server.client.name, had_error
    room=ROOM_all[server.client.rid]
    #log.info "server close", server.client.ip, ROOM_connected_ip[server.client.ip]
    room.disconnector = 'server' if room and !server.system_kicked and !server.had_new_reconnection
    unless server.client.isClosed
      ygopro.stoc_send_chat(server.client, "${server_closed}", ygopro.constants.COLORS.RED)
      #if room and settings.modules.replay_delay
      #  room.send_replays()
      CLIENT_kick(server.client)
      SERVER_clear_disconnect(server)
    return

  server.on 'error', (error)->
    server.isClosed = error
    if !server.client
      return
    #log.info "server error", client.name, error
    room=ROOM_all[server.client.rid]
    #log.info "server err close", client.ip, ROOM_connected_ip[client.ip]
    room.disconnector = 'server' if room and !server.system_kicked and !server.had_new_reconnection
    unless server.client.isClosed
      ygopro.stoc_send_chat(server.client, "${server_error}: #{error}", ygopro.constants.COLORS.RED)
      #if room and settings.modules.replay_delay
      #  room.send_replays()
      CLIENT_kick(server.client)
      SERVER_clear_disconnect(server)
    return

  if settings.modules.cloud_replay.enabled
    client.open_cloud_replay = (replay)->
      if !replay
        ygopro.stoc_die(client, "${cloud_replay_no}")
        return
      buffer=replay.toBuffer()
      replay_buffer = null
      try
        replay_buffer = await util.promisify(zlib.unzip)(buffer)
      catch e
        log.info "cloud replay unzip error: " + err
        ygopro.stoc_die(client, "${cloud_replay_error}")
        return
      ygopro.stoc_send_chat(client, "${cloud_replay_playing} #{replay.getDisplayString()}", ygopro.constants.COLORS.BABYBLUE)
      await ygopro.helper.send(client, replay_buffer)
      CLIENT_kick(client)
      return

  # 需要重构
  # 客户端到服务端(ctos)协议分析

  client.pre_establish_buffers = new Array()

  dataHandler = (ctos_buffer) ->
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
        await ygopro.helper.send(room.watcher, buffer) for buffer in handle_data.datas
    else
      ctos_filter = null
      preconnect = false
      if settings.modules.reconnect.enabled and client.pre_reconnecting_to_room
        ctos_filter = ["UPDATE_DECK"]
      if client.name == null
        ctos_filter = ["JOIN_GAME", "PLAYER_INFO"]
        preconnect = true
      handle_data = await ygopro.helper.handleBuffer(ctos_buffer, "CTOS", ctos_filter, {
        client: client,
        server: client.server
      }, preconnect)
      if handle_data.feedback
        log.warn(handle_data.feedback.message, client.name, client.ip)
        if handle_data.feedback.type == "OVERSIZE" or handle_data.feedback.type == "INVALID_PACKET" or ROOM_bad_ip[client.ip] > 5
          bad_ip_count = ROOM_bad_ip[client.ip]
          if bad_ip_count
            ROOM_bad_ip[client.ip] = bad_ip_count + 1
          else
            ROOM_bad_ip[client.ip] = 1
          CLIENT_kick(client)
          return
      if client.isClosed || !client.server
        return
      if client.established
        await ygopro.helper.send(client.server, buffer) for buffer in handle_data.datas
      else
        client.pre_establish_buffers = client.pre_establish_buffers.concat(handle_data.datas) 

    return

  if client.isWs
    client.on 'message', dataHandler
  else
    client.on 'data', dataHandler

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
    if server.client and !server.client.isClosed
      await ygopro.helper.send(server.client, buffer) for buffer in handle_data.datas

    return
  return

deck_name_match = global.deck_name_match = (deck_name, player_name) ->
  if deck_name == player_name or deck_name == player_name + ".ydk" or deck_name == player_name + ".ydk.ydk"
    return true
  parsed_deck_name = deck_name.match(/^([^\+ \uff0b]+)[\+ \uff0b](.+?)(\.ydk){0,2}$/)
  return parsed_deck_name and (player_name == parsed_deck_name[1] or player_name == parsed_deck_name[2])

# 功能模块
# return true to cancel a synchronous message

ygopro.ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server, datas)->
  # second PLAYER_INFO = attack
  if client.name
    log.info 'DUP PLAYER_INFO', client.ip
    CLIENT_kick client
    return '_cancel'
  # checkmate use username$password, but here don't
  # so remove the password
  name_full =info.name.replace(/\\/g, "").split("$")
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
    replays = await dataManager.getCloudReplaysFromKey(CLIENT_get_authorize_key(client))
    for replay,index in replays
      ygopro.stoc_send_chat(client,"<#{index + 1}> #{replay.getDisplayString()}", ygopro.constants.COLORS.BABYBLUE)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 1
      code: 9
    }
    CLIENT_kick(client)

  else if info.pass.toUpperCase()=="RC" and settings.modules.tournament_mode.enable_recover
    ygopro.stoc_send_chat(client,"${recover_replay_hint}", ygopro.constants.COLORS.BABYBLUE)
    available_logs = await dataManager.getDuelLogFromRecoverSearch(client.name_vpass)
    for duelLog in available_logs
      ygopro.stoc_send_chat(client, duelLog.getViewString(), ygopro.constants.COLORS.BABYBLUE)
    ygopro.stoc_send client, 'ERROR_MSG',{
      msg: 1
      code: 9
    }
    CLIENT_kick(client)

  else if info.pass[0...2].toUpperCase()=="R#" and settings.modules.cloud_replay.enabled
    replay_id=info.pass.split("#")[1]
    replay = await dataManager.getCloudReplayFromId(replay_id)
    await client.open_cloud_replay(replay)

  else if info.pass.toUpperCase()=="W" and settings.modules.cloud_replay.enabled
    replay = await dataManager.getRandomCloudReplay()
    await client.open_cloud_replay(replay)

  else if info.version != settings.version and !settings.alternative_versions.includes(info.version)
    ygopro.stoc_send_chat(client, (if info.version < settings.version then settings.modules.update else settings.modules.wait_update), ygopro.constants.COLORS.RED)
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 4
      code: settings.version
    }
    CLIENT_kick(client)

  else if !info.pass.length and !settings.modules.random_duel.enabled and !settings.modules.windbot.enabled and !settings.modules.challonge.enabled
    ygopro.stoc_die(client, "${blank_room_name}")


  else if settings.modules.mysql.enabled and await dataManager.checkBan("name", client.name) #账号被封
    exactBan = await dataManager.checkBanWithNameAndIP(client.name, client.ip)
    if !exactBan
      exactBan = dataManager.getBan(client.name, client.ip)
      await dataManager.banPlayer(exactBan)
    log.warn("BANNED USER LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${banned_user_login}")

  else if settings.modules.mysql.enabled and await dataManager.checkBan("ip", client.ip) #IP被封
    log.warn("BANNED IP LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${banned_ip_login}")

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
    
    if settings.modules.mycard.enabled and settings.modules.mycard.ban_get and !client.is_local
      axios.get settings.modules.mycard.ban_get, 
        paramsSerializer: qs.stringify
        params:
          user: client.name
      .then (banMCRequest) ->
        if typeof(banMCRequest.data) == "object"
          client.ban_mc = banMCRequest.data
        else
          log.warn "ban get bad json", banMCRequest.data
      .catch (e) ->
        log.warn 'ban get error', e.toString()

    check_buffer_indentity = (buf)->
      checksum = 0
      for i in [0...buf.length]
        checksum += buf.readUInt8(i)
      (checksum & 0xFF) == 0

    create_room_with_action = (buffer, decrypted_buffer)->
      if client.isClosed
        return
      firstByte = buffer.readUInt8(1)
      action = firstByte >> 4
      opt0 = firstByte & 0xf
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
            rule: (opt1 >> 5) & 0x7 # 0 1 2 3 4 5
            mode: (opt1 >> 3) & 0x3 # 0 1 2
            duel_rule: (opt0 >> 1) || 5 # 1 2 3 4 5
            no_check_deck: !!((opt1 >> 1) & 1)
            no_shuffle_deck: !!(opt1 & 1)
            start_lp: opt2
            start_hand: opt3 >> 4
            draw_count: opt3 & 0xF
            no_watch: settings.hostinfo.no_watch
            auto_death: !!(opt0 & 0x1) ? 40 : false
          }
          #console.log(options)
          if options.rule == 2
            options.lflist = -1
          else if options.rule != 3
            options.lflist = _.findIndex lflists, (list)-> ((options.rule == 1) == list.tcg) and list.date.isBefore()
          room_title = info.pass.slice(8).replace(String.fromCharCode(0xFEFF), ' ')
          if badwordR.level3.test(room_title)
            log.warn("BAD ROOM NAME LEVEL 3", room_title, client.name, client.ip)
            ygopro.stoc_die(client, "${bad_roomname_level3}")
            return
          else if badwordR.level2.test(room_title)
            log.warn("BAD ROOM NAME LEVEL 2", room_title, client.name, client.ip)
            ygopro.stoc_die(client, "${bad_roomname_level2}")
            return
          else if badwordR.level1.test(room_title)
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
          if settings.modules.arena_mode.check_permit
            try
              matchPermitRes = await axios.get settings.modules.arena_mode.check_permit,
                responseType: 'json'
                timeout: 3000
                params:
                  username: client.name,
                  password: info.pass,
                  arena: settings.modules.arena_mode.mode
              match_permit = matchPermitRes.data
            catch e
              log.warn "match permit fail #{e.toString()}"
            if client.isClosed
              return
            if match_permit and match_permit.permit == false
              ygopro.stoc_die(client, '${invalid_password_unauthorized}')
              return
          room = await ROOM_find_or_create_by_name('M#' + info.pass.slice(8))
          if room
            for player in room.get_playing_player() when player and player.name == client.name
              ygopro.stoc_die(client, '${invalid_password_unauthorized}')
              return
            room.private = true
            room.arena = settings.modules.arena_mode.mode
            room.max_player = 2
            if room.arena == "athletic"
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
        ygopro.stoc_die(client, settings.modules.full)
      else if room.error
        ygopro.stoc_die(client, room.error)
      else 
        room.join_player(client)
      return

    decrypted_buffer = null

    if id = users_cache[client.name]
      secret = id % 65535 + 1
      decrypted_buffer = Buffer.allocUnsafe(6)
      for i in [0, 2, 4]
        decrypted_buffer.writeUInt16LE(buffer.readUInt16LE(i) ^ secret, i)
      if check_buffer_indentity(decrypted_buffer)
        return create_room_with_action(decrypted_buffer, decrypted_buffer)

    try
      userUrl = "#{settings.modules.mycard.auth_base_url}/users/#{encodeURIComponent(client.name)}.json"
      #console.log(userUrl)
      userDataRes = await axios.get userUrl,
        responseType: 'json'
        timeout: 4000
        params:
          api_key: settings.modules.mycard.auth_key,
          api_username: client.name,
          skip_track_visit: true
      userData = userDataRes.data
      #console.log userData
    catch e
      log.warn("READ USER FAIL", client.name, e.toString())
      if !client.isClosed
        ygopro.stoc_die(client, '${load_user_info_fail}')
      return
    if client.isClosed
      return
    users_cache[client.name] = userData.user.id
    secret = userData.user.id % 65535 + 1
    decrypted_buffer = Buffer.allocUnsafe(6)
    for i in [0, 2, 4]
      decrypted_buffer.writeUInt16LE(buffer.readUInt16LE(i) ^ secret, i)
    if check_buffer_indentity(decrypted_buffer)
      buffer = decrypted_buffer
    if !check_buffer_indentity(buffer)
      ygopro.stoc_die(client, '${invalid_password_checksum}')
      return
    return create_room_with_action(buffer, decrypted_buffer)

  else if settings.modules.challonge.enabled
    if info.version != settings.version and settings.alternative_versions.includes(info.version)
      info.version = settings.version
      struct = ygopro.structs.get("CTOS_JoinGame")
      struct._setBuff(buffer)
      struct.set("version", info.version)
      buffer = struct.buffer
    pre_room = ROOM_find_by_name(info.pass)
    if pre_room and pre_room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and settings.modules.cloud_replay.enable_halfway_watch and !pre_room.hostinfo.no_watch
      pre_room.join_post_watch(client)
      return
    else
      ygopro.stoc_send_chat(client, '${loading_user_info}', ygopro.constants.COLORS.BABYBLUE)
      client.setTimeout(300000) #连接后超时5分钟
      recover_match = info.pass.match(/^(RC|RECOVER)(\d*)T(\d*)$/)
      tournament_data = await challonge.getTournament(!!recover_match)
      if !tournament_data
        if !client.isClosed
          ygopro.stoc_die(client, '${challonge_match_load_failed}')
        return
      matching_participant = tournament_data.participants.find((p) => p.participant.name and deck_name_match(p.participant.name, client.name))
      unless matching_participant
        if !client.isClosed
          ygopro.stoc_die(client, '${challonge_user_not_found}')
        return
      client.challonge_info = matching_participant.participant
      matching_match = tournament_data.matches.find((match) => match.match and !match.match.winner_id and match.match.state != "complete" and match.match.player1_id and match.match.player2_id and (match.match.player1_id == client.challonge_info.id or match.match.player2_id == client.challonge_info.id))
      unless matching_match
        if !client.isClosed
          ygopro.stoc_die(client, '${challonge_match_not_found}')
        return
      create_room_name = matching_match.match.id.toString()
      if !settings.modules.challonge.no_match_mode
        create_room_name = 'M#' + create_room_name 
        if recover_match
          create_room_name = recover_match[0] + ',' + create_room_name
      else if recover_match
        create_room_name = recover_match[0] + '#' + create_room_name
      room = await ROOM_find_or_create_by_name(create_room_name)
      if room
        room.challonge_info = matching_match.match
        # room.max_player = 2
        room.welcome = "${challonge_match_created}"
      if !room
        ygopro.stoc_die(client, settings.modules.full)
      else if room.error
        ygopro.stoc_die(client, room.error)
      else
        room.join_player(client)

  else if !client.name or client.name==""
    ygopro.stoc_die(client, "${bad_user_name}")

  else if ROOM_connected_ip[client.ip] > 5
    log.warn("MULTI LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${too_much_connection}" + client.ip)

  else if !settings.modules.tournament_mode.enabled and !settings.modules.challonge.enabled and badwordR.level3.test(client.name)
    log.warn("BAD NAME LEVEL 3", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level3}")

  else if !settings.modules.tournament_mode.enabled and !settings.modules.challonge.enabled and badwordR.level2.test(client.name)
    log.warn("BAD NAME LEVEL 2", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level2}")

  else if !settings.modules.tournament_mode.enabled and !settings.modules.challonge.enabled and badwordR.level1.test(client.name)
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
    room = await ROOM_find_or_create_by_name(info.pass, client.ip)
    if !room
      ygopro.stoc_die(client, settings.modules.full)
    else if room.error
      ygopro.stoc_die(client, room.error)
    else
      room.join_player(client)
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
    ygopro.stoc_send_chat_to_room(room, await ROOM_player_get_score(client), ygopro.constants.COLORS.GREEN)
    for player in room.players when player.pos != 7 and player != client
      ygopro.stoc_send_chat(client, await ROOM_player_get_score(player), ygopro.constants.COLORS.GREEN)
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
      return unless room
      room.addRecorderBuffer(data)
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
        ygopro.helper.send(w, data) if w #a WTF fix
      return

    watcher.on 'error', (error)->
      log.error "watcher error", error
      return
  await return

# 登场台词
load_dialogues = global.load_dialogues = () ->
  return await loadRemoteData(dialogues, "dialogues", settings.modules.dialogues.get)

ygopro.stoc_follow 'GAME_MSG', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and !client.reconnecting
  msg = buffer.readInt8(0)
  msg_name = ygopro.constants.MSG[msg]
  #console.log client.pos, "MSG", msg_name
  if msg_name == 'RETRY' and room.recovering
    room.finish_recover(true)
    return true
  if settings.modules.retry_handle.enabled
    if msg_name == 'RETRY'
      if !client.retry_count?
        client.retry_count = 0
      client.retry_count++
      log.warn "MSG_RETRY detected", client.name, client.ip, msg, client.retry_count
      if settings.modules.retry_handle.max_retry_count and client.retry_count >= settings.modules.retry_handle.max_retry_count
        ygopro.stoc_send_chat_to_room(room, client.name + "${retry_too_much_room_part1}" + settings.modules.retry_handle.max_retry_count + "${retry_too_much_room_part2}", ygopro.constants.COLORS.BABYBLUE)
        ygopro.stoc_send_chat(client, "${retry_too_much_part1}" + settings.modules.retry_handle.max_retry_count + "${retry_too_much_part2}", ygopro.constants.COLORS.RED)
        CLIENT_send_replays_and_kick(client, room)
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
      client.last_game_msg_title = msg_name
      # log.info(client.name, client.last_game_msg_title)
  else if msg_name != 'RETRY'
    client.last_game_msg = buffer
    client.last_game_msg_title = msg_name
    # log.info(client.name, client.last_game_msg_title)

  if (msg >= 10 and msg < 30) or msg == 132 or (msg >= 140 and msg <= 144) #SELECT和ANNOUNCE开头的消息
    if room.recovering
      ygopro.ctos_send(server, 'RESPONSE', room.recover_replay.responses.splice(0, 1)[0])
      if !room.recover_replay.responses.length
        room.finish_recover()
      return true
    else
      room.waiting_for_player = client
      room.refreshLastActiveTime()
      #log.info("#{msg_name}等待#{room.waiting_for_player.name}")

  #log.info 'MSG', msg_name
  if msg_name == 'START'
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

  if msg_name == 'HINT'
    hint_type = buffer.readUInt8(1)
    if hint_type == 3
      client.last_hint_msg = buffer

  if msg_name == 'NEW_TURN'
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

  if msg_name == 'NEW_PHASE'
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

  if msg_name == 'WIN' and client.pos == 0
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

  if msg_name == 'MATCH_KILL' and client.pos == 0
    room.match_kill = true

  #lp跟踪
  if msg_name == 'DAMAGE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    if room.dueling_players[pos]
      room.dueling_players[pos].lp -= val
      room.dueling_players[pos].lp = 0 if room.dueling_players[pos].lp < 0
      if 0 < room.dueling_players[pos].lp <= 100
        ygopro.stoc_send_chat_to_room(room, "${lp_low_opponent}", ygopro.constants.COLORS.PINK)

  if msg_name == 'RECOVER' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    if room.dueling_players[pos]
      room.dueling_players[pos].lp += val

  if msg_name == 'LPUPDATE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    if room.dueling_players[pos]
      room.dueling_players[pos].lp = val

  if msg_name == 'PAY_LPCOST' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    if room.dueling_players[pos]
      room.dueling_players[pos].lp -= val
      room.dueling_players[pos].lp = 0 if room.dueling_players[pos].lp < 0
      if 0 < room.dueling_players[pos].lp <= 100
        ygopro.stoc_send_chat_to_room(room, "${lp_low_self}", ygopro.constants.COLORS.PINK)

  #track card count
  #todo: track card count in tag mode
  if msg_name == 'MOVE' and room.hostinfo.mode != 2
    pos = buffer.readUInt8(5)
    pos = 1 - pos unless client.is_first
    loc = buffer.readUInt8(6)
    client.card_count-- if (loc & 0xe) and pos == 0
    pos = buffer.readUInt8(9)
    pos = 1 - pos unless client.is_first
    loc = buffer.readUInt8(10)
    client.card_count++ if (loc & 0xe) and pos == 0

  if msg_name == 'DRAW' and room.hostinfo.mode != 2
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    if pos == 0
      count = buffer.readInt8(2)
      client.card_count += count

  # check panel confirming cards in heartbeat
  if settings.modules.heartbeat_detection.enabled and msg_name == 'CONFIRM_CARDS'
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
    if msg_name == 'CHAINING'
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
    else if msg_name == 'CHAINED' and room.long_resolve_card
      chain = buffer.readInt8(1)
      if !room.long_resolve_chain
        room.long_resolve_chain = []
      room.long_resolve_chain[chain] = true
      # console.log(1,chain)
      delete room.long_resolve_card
    else if msg_name == 'CHAIN_SOLVING' and room.long_resolve_chain
      chain = buffer.readInt8(1)
      # console.log(2,chain)
      if room.long_resolve_chain[chain]
        for player in room.get_playing_player()
          player.heartbeat_protected = true
    else if (msg_name == 'CHAIN_NEGATED' or msg_name == 'CHAIN_DISABLED') and room.long_resolve_chain
      chain = buffer.readInt8(1)
      # console.log(3,chain)
      delete room.long_resolve_chain[chain]
    else if msg_name == 'CHAIN_END'
      # console.log(4,chain)
      delete room.long_resolve_card
      delete room.long_resolve_chain

  #登场台词
  if settings.modules.dialogues.enabled and !room.recovering
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

  if room.recovering and client.pos < 4
    if msg_name != 'WAITING'
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
        await ROOM_ban_player(player.name, player.ip, "${random_ban_reason_zombie}")
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
  return unless room and client.pos == 0
  pos = info.status >> 4
  is_ready = (info.status & 0xf) == 9
  room.ready_player_count = 0
  room.ready_player_count_without_host = 0
  for player in room.players
    if player.pos == pos
      player.is_ready = is_ready
    if player.is_ready
      ++room.ready_player_count
      unless player.is_host
        ++room.ready_player_count_without_host
  if settings.modules.athletic_check.enabled
    possibly_max_player = if room.hostinfo.mode == 2 then 4 else 2
    if room.ready_player_count >= possibly_max_player
      room.check_athletic()
  if room.max_player and pos < room.max_player
    if room.arena # mycard
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
        if !room.waiting_for_player_interval
          room.waiting_for_player_interval = setInterval (()-> wait_room_start_arena(ROOM_all[client.rid]);return), 1000
      else if !room.waiting_for_player and room.waiting_for_player_interval
        clearInterval room.waiting_for_player_interval
        room.waiting_for_player_interval = null
        room.waiting_for_player_time = settings.modules.arena_mode.ready_time
    else # random duel
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

ygopro.stoc_follow 'DUEL_END', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and settings.modules.replay_delay and room.hostinfo.mode == 1
  await SOCKET_flush_data(client, datas)
  await CLIENT_send_replays(client, room)
  if !room.replays_sent_to_watchers
    room.replays_sent_to_watchers = true
    for player in room.players when player and player.pos > 3
      CLIENT_send_replays(player, room)
    for player in room.watchers when player
      CLIENT_send_replays(player, room)
  return false

wait_room_start = (room, time)->
  if room and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and room.ready_player_count_without_host >= room.max_player - 1
    #log.info('wait room start', time)
    time -= 1
    if time
      unless time % 5
        ygopro.stoc_send_chat_to_room(room, "#{if time <= 9 then ' ' else ''}#{time}${kick_count_down}", if time <= 9 then ygopro.constants.COLORS.RED else ygopro.constants.COLORS.LIGHTBLUE)
      setTimeout (()-> wait_room_start(room, time);return), 1000
    else
      for player in room.players
        if player and player.is_host
          await ROOM_ban_player(player.name, player.ip, "${random_ban_reason_zombie}")
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

loadRemoteData = global.loadRemoteData = (loadObject, name, url)->
  try
    body = (await axios.get(url, {
      responseType: "json"
    })).data
    if _.isString body
      log.warn "#{name} bad json", body
      return false
    if !body
      log.warn "#{name} empty", body
      return false
    await setting_change(loadObject, name, body)
    log.info "#{name} loaded"
    return true
  catch e
    log.warn "#{name} error", e
    return false

load_tips = global.load_tips = ()->
  return await loadRemoteData(tips, "tips", settings.modules.tips.get)

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and !client.reconnecting
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN #first start
    room.duel_stage = ygopro.constants.DUEL_STAGE.FINGER
    room.start_time = moment_now_string
    room.turn = 0
    roomlist.start room if !room.windbot and settings.modules.http.websocket_roomlist
    #room.duels = []
    room.dueling_players = []
    for player in room.get_playing_player()
      room.dueling_players[player.pos] = player
      room.scores[player.name_vpass] = 0
      room.player_datas.push key: CLIENT_get_authorize_key(player), name: player.name, pos: player.pos
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
          if response.statusCode > 300
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
      if response.statusCode >= 300
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
  room.refreshLastActiveTime() unless cancel or not (room.random_type or room.arena) or room.duel_stage == ygopro.constants.DUEL_STAGE.FINGER or room.duel_stage == ygopro.constants.DUEL_STAGE.FIRSTGO or room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING
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
      ygopro.stoc_send_chat(client, "${chat_order_refresh}")
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
    
    when '/refresh'
      if room.duel_stage == ygopro.constants.DUEL_STAGE.DUELING and client.last_game_msg and client.last_game_msg_title != 'WAITING'
        if client.last_hint_msg
          ygopro.stoc_send(client, 'GAME_MSG', client.last_hint_msg)
        ygopro.stoc_send(client, 'GAME_MSG', client.last_game_msg)
        ygopro.stoc_send_chat(client, '${refresh_success}', ygopro.constants.COLORS.BABYBLUE)
      else
        ygopro.stoc_send_chat(client, '${refresh_fail}', ygopro.constants.COLORS.RED)

    when '/color'
      if settings.modules.chat_color.enabled
        cip = CLIENT_get_authorize_key(client)
        if cmsg = cmd[1]
          if cmsg.toLowerCase() == "help"
            ygopro.stoc_send_chat(client, "${show_color_list}", ygopro.constants.COLORS.BABYBLUE)
            for cname,cvalue of ygopro.constants.COLORS when cvalue > 10
              ygopro.stoc_send_chat(client, cname, cvalue)
          else if cmsg.toLowerCase() == "default"
            await dataManager.setUserChatColor(cip, null)
            ygopro.stoc_send_chat(client, "${set_chat_color_default}", ygopro.constants.COLORS.BABYBLUE)
          else
            ccolor = cmsg.toUpperCase()
            if ygopro.constants.COLORS[ccolor] and ygopro.constants.COLORS[ccolor] > 10 and ygopro.constants.COLORS[ccolor] < 20
              await dataManager.setUserChatColor(cip, ccolor)
              ygopro.stoc_send_chat(client, "${set_chat_color_part1}" + ccolor + "${set_chat_color_part2}", ygopro.constants.COLORS.BABYBLUE)
            else
              ygopro.stoc_send_chat(client, "${color_not_found_part1}" + ccolor + "${color_not_found_part2}", ygopro.constants.COLORS.RED)
        else
          color = await dataManager.getUserChatColor(cip)
          if color
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
  if !(room and (room.random_type or room.arena)) and not settings.modules.mycard.enabled
    if !cancel and settings.modules.display_watchers and (client.is_post_watcher or client.pos > 3)
      ygopro.stoc_send_chat_to_room(room, "#{client.name}: #{msg}", 9)
      return true
    return cancel
  if client.abuse_count>=5 or CLIENT_is_banned_by_mc(client)
    log.warn "BANNED CHAT", client.name, client.ip, msg
    ygopro.stoc_send_chat(client, "${banned_chat_tip}" + (if client.ban_mc and client.ban_mc.message then (": " + client.ban_mc.message) else ""), ygopro.constants.COLORS.RED)
    return true
  oldmsg = msg
  if badwordR.level3.test(msg)
    log.warn "BAD WORD LEVEL 3", client.name, client.ip, oldmsg, RegExp.$1
    report_to_big_brother room.name, client.name, client.ip, 3, oldmsg, RegExp.$1
    cancel = true
    if client.abuse_count>0
      ygopro.stoc_send_chat(client, "${banned_duel_tip}", ygopro.constants.COLORS.RED)
      await ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}")
      await ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}", 3)
      CLIENT_send_replays_and_kick(client, room)
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
      struct = ygopro.structs.get("chat")
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
    await ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}")
  if !cancel and settings.modules.display_watchers and (client.is_post_watcher or client.pos > 3)
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
    room.refreshLastActiveTime()
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and room.recovering
    recover_player_data = _.find(room.recover_duel_log.players, (player) ->
      return player.realName == client.name_vpass and buffer.compare(Buffer.from(player.startDeckBuffer, "base64")) == 0
    )
    if recover_player_data
      recoveredDeck = recover_player_data.getCurrentDeck()
      struct.set("mainc", recoveredDeck.main.length)
      struct.set("sidec", recoveredDeck.side.length)
      struct.set("deckbuf", recoveredDeck.main.concat(recoveredDeck.side))
      if recover_player_data.isFirst
        room.determine_firstgo = client
    else
      struct.set("mainc", 1)
      struct.set("sidec", 1)
      struct.set("deckbuf", [4392470, 4392470])
      ygopro.stoc_send_chat(client, "${deck_incorrect_reconnect}", ygopro.constants.COLORS.RED)
      return false
  else
    if room.arena and settings.modules.athletic_check.enabled and settings.modules.athletic_check.banCount
      athleticCheckResult = await athleticChecker.checkAthletic({main: buff_main, side: buff_side})
      if athleticCheckResult.success
        if athleticCheckResult.athletic and athleticCheckResult.athletic <= settings.modules.athletic_check.banCount
          struct.set("mainc", 1)
          struct.set("sidec", 1)
          struct.set("deckbuf", [4392470, 4392470])
          ygopro.stoc_send_chat(client, "${banned_athletic_deck_part1}#{settings.modules.athletic_check.banCount}${banned_athletic_deck_part2}", ygopro.constants.COLORS.RED)
          return false
      else
        log.warn("GET ATHLETIC FAIL", client.name, athleticCheckResult.message)
    if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.deck_check
      decks = await fs.promises.readdir(settings.modules.tournament_mode.deck_path)
      if decks.length
        struct.set("mainc", 1)
        struct.set("sidec", 1)
        struct.set("deckbuf", [4392470, 4392470])
        buffer = struct.buffer
        found_deck=false
        for deck in decks
          if deck_name_match(deck, client.name)
            found_deck=deck
        if found_deck
          deck_text = await fs.promises.readFile(settings.modules.tournament_mode.deck_path+found_deck,{encoding:"ASCII"})
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
            return false
        else
          #log.info("player deck not found: " + client.name)
          ygopro.stoc_send_chat(client, "#{client.name}${deck_not_found}", ygopro.constants.COLORS.RED)
          return false
  await return false

ygopro.ctos_follow 'RESPONSE', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and (room.random_type or room.arena)
  room.refreshLastActiveTime()
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
    if client.isClosed
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
    room.refreshLastActiveTime(true)
  await return

ygopro.ctos_follow 'TP_RESULT', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  client.selected_preduel = true
  # room.selecting_tp = false
  return unless room.random_type or room.arena
  room.refreshLastActiveTime()
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
  tcolor = await dataManager.getUserChatColor(CLIENT_get_authorize_key(tplayer));
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
    room.refreshLastActiveTime(true)
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
    room.refreshLastActiveTime()
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
        CLIENT_send_replays_and_kick(client, room)
        clearInterval sinterval
      else
        client.side_tcount = client.side_tcount - 1
        ygopro.stoc_send_chat(client, "${side_remain_part1}#{client.side_tcount}${side_remain_part2}", ygopro.constants.COLORS.BABYBLUE)
    , 60000
    client.side_interval = sinterval
  if settings.modules.challonge.enabled and settings.modules.challonge.post_score_midduel and room.hostinfo.mode != 2 and client.pos == 0
    room.post_challonge_score(true)
  if room.random_type or room.arena
    if client.pos == 0
      room.waiting_for_player = client
    else
      room.waiting_for_player2 = client
    room.refreshLastActiveTime()
  await return

ygopro.stoc_follow 'REPLAY', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  if room and !room.replays[room.duel_count - 1]
    # console.log("Replay saved: ", room.duel_count - 1, client.pos)
    room.replays[room.duel_count - 1] = buffer
    if settings.modules.mysql.enabled or room.has_ygopro_error
      #console.log('save replay')
      replay_filename=moment_now.format("YYYY-MM-DD HH-mm-ss")
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
      if settings.modules.mysql.enabled
        playerInfos = room.dueling_players.map((player) ->
          return {
            name: player.name
            pos: player.pos
            realName: player.name_vpass
            startDeckBuffer: player.start_deckbuf
            deck: {
              main: player.main,
              side: player.side
            }
            isFirst: player.is_first
            winner: player.pos == room.winner
            ip: player.ip
            score: room.scores[player.name_vpass]
            lp: if player.lp? then player.lp else room.hostinfo.start_lp
            cardCount: if player.card_count? then player.card_count else room.hostinfo.start_hand
          }
        )
        dataManager.saveDuelLog(room.name, room.process_pid, room.cloud_replay_id, replay_filename, room.hostinfo.mode, room.duel_count, playerInfos) # no synchronize here because too slow
    if settings.modules.mysql.enabled && settings.modules.cloud_replay.enabled and settings.modules.tournament_mode.enabled
      ygopro.stoc_send_chat(client, "${cloud_replay_delay_part1}R##{room.cloud_replay_id}${cloud_replay_delay_part2}", ygopro.constants.COLORS.BABYBLUE)
  await return settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.block_replay_to_player or settings.modules.replay_delay and room.hostinfo.mode == 1

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

global.rebooted = false
#http
if true

  getDuelLogQueryFromQs = (qdata) ->
    try
      ret = {}
      if(qdata.roomname)
        ret.roomName = decodeURIComponent(qdata.roomname).trim()
      if(qdata.duelcount)
        ret.duelCount = parseInt(decodeURIComponent(qdata.duelcount))
      if(qdata.playername)
        ret.playerName = decodeURIComponent(qdata.playername).trim()
      if(qdata.score)
        ret.playerScore = parseInt(decodeURIComponent(qdata.score))
      return ret
    catch
      return {}

  addCallback = (callback, text)->
    if not callback then return text
    return callback + "( " + text + " );"

  httpRequestListener = (request, response)->
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


    else if u.pathname == '/api/duellog' and settings.modules.mysql.enabled
      if !await auth.auth(u.query.username, u.query.pass, "duel_log", "duel_log")
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "[{name:'密码错误'}]"))
        return
      else
        response.writeHead(200)
        duellog = JSON.stringify(await dataManager.getDuelLogJSONFromCondition(settings.modules.tournament_mode, getDuelLogQueryFromQs(u.query)), null, 2)
        response.end(addCallback(u.query.callback, duellog))

    else if u.pathname == '/api/archive.zip' and settings.modules.mysql.enabled
      if !await auth.auth(u.query.username, u.query.pass, "download_replay", "download_replay_archive")
        response.writeHead(403)
        response.end("Invalid password.")
        return
      else
        try
          archiveStream = await dataManager.getReplayArchiveStreamFromCondition(settings.modules.tournament_mode.replay_path, getDuelLogQueryFromQs(u.query))
          if !archiveStream
            response.writeHead(403)
            response.end("Replay not found.")
            return
          response.writeHead(200, { "Content-Type": "application/octet-stream", "Content-Disposition": "attachment" })
          archiveStream.on "data", (data) ->
            response.write data
          archiveStream.on "end", () ->
            response.end()
          archiveStream.on "close", () ->
            log.warn("Archive closed")
          archiveStream.on "error", (error) ->
            log.warn("Archive error: #{error}")
        catch error
          response.writeHead(403)
          response.end("Failed reading replays. " + error)

    else if u.pathname == '/api/clearlog' and settings.modules.mysql.enabled
      if !await auth.auth(u.query.username, u.query.pass, "clear_duel_log", "clear_duel_log")
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "[{name:'密码错误'}]"))
        return
      else
        response.writeHead(200)
        if settings.modules.tournament_mode.log_save_path
          fs.writeFile(settings.modules.tournament_mode.log_save_path + 'duel_log.' + moment_now.format('YYYY-MM-DD HH-mm-ss') + '.json', JSON.stringify(await dataManager.getDuelLogJSON(settings.modules.tournament_mode), null, 2), (err) ->
            if err
              log.warn 'DUEL LOG SAVE ERROR', err
          )
        await dataManager.clearDuelLog()
        response.end(addCallback(u.query.callback, "[{name:'Success'}]"))

    else if _.startsWith(u.pathname, '/api/replay') and settings.modules.mysql.enabled
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
        try 
          buffer = await fs.promises.readFile(settings.modules.tournament_mode.replay_path + filename)
          response.writeHead(200, { "Content-Type": "application/octet-stream", "Content-Disposition": "attachment" })
          response.end(buffer)
        catch e
          response.writeHead(404)
          response.end("未找到文件 " + filename)

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
          await setting_change(settings, 'modules:stop', u.query.stop)
          response.end(addCallback(u.query.callback, "['stop ok', '" + u.query.stop + "']"))
        catch err
          response.end(addCallback(u.query.callback, "['stop fail', '" + u.query.stop + "']"))

      else if u.query.welcome
        if !await auth.auth(u.query.username, u.query.pass, "change_settings", "change_welcome")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        try
          await setting_change(settings, 'modules:welcome', u.query.welcome)
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
        success = await load_tips()
        response.writeHead(200)
        if success
          response.end(addCallback(u.query.callback, "['tip ok', '" +  settings.modules.tips.get + "']"))
        else
          response.end(addCallback(u.query.callback, "['tip fail', '" + settings.modules.tips.get + "']"))

      else if u.query.loaddialogues
        if !await auth.auth(u.query.username, u.query.pass, "change_settings", "change_dialogues")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        success = await load_dialogues()
        response.writeHead(200)
        if success
          response.end(addCallback(u.query.callback, "['dialogue ok', '" +  settings.modules.tips.get + "']"))
        else
          response.end(addCallback(u.query.callback, "['dialogue fail', '" + settings.modules.tips.get + "']"))

      else if u.query.ban
        if !await auth.auth(u.query.username, u.query.pass, "ban_user", "ban_user")
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['密码错误', 0]"))
          return
        try
          await ban_user(u.query.ban)
        catch e
          log.warn("ban fail", e.toString())
          response.writeHead(200)
          response.end(addCallback(u.query.callback, "['ban fail', '" + u.query.ban + "']"))
          return
        response.writeHead(200)
        response.end(addCallback(u.query.callback, "['ban ok', '" + u.query.ban + "']"))

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
        _async.each(ROOM_all, (room, done)->
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

ip6addr = require('ip6addr')

neosRequestListener = (client, req) ->
  physicalAddress = req.socket.remoteAddress
  if settings.modules.neos.trusted_proxies.some((trusted) ->
    cidr =  if trusted.includes('/') then ip6addr.createCIDR(trusted) else ip6addr.createAddrRange(trusted, trusted)
    return cidr.contains(physicalAddress)
  )
    ipHeader = req.headers[settings.modules.neos.trusted_proxy_header]
    if ipHeader
      client.ip = ipHeader.split(',')[0].trim()
  if !client.ip
    client.ip = physicalAddress
  client.setTimeout = () -> true
  client.destroy = () -> client.close()
  client.isWs = true
  netRequestHandler(client)


init()
