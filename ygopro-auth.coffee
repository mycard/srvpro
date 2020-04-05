###
Main script of new dashboard account system.
The account list file is stored at `./config/admin_user.json`. The users are stored at `users`.
The key is the username. The `permissions` field could be a string, using a permission set from the example, or an object, to define a specific set of permissions.
eg. An account for a judge could be as follows, to use the default permission of judges,
    "username": {
      "password": "123456",
      "enabled": true,
      "permissions": "judge"
    },
or as follows, to use a specific set of permissions.
    "username": {
      "password": "123456",
      "enabled": true,
      "permissions": {
        "get_rooms": true,
        "duel_log": true,
        "download_replay": true,
        "deck_dashboard_read": true,
        "deck_dashboard_write": true,
        "shout": true,
        "kick_user": true,
        "start_death": true
      }
    },
###
fs = require 'fs'
loadJSON = require('load-json-file').sync
loadJSONPromise = require('load-json-file')
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

bunyan = require 'bunyan'
log = bunyan.createLogger name: "auth"
util = require 'util'

if not fs.existsSync('./logs')
  fs.mkdirSync('./logs')

add_log = (message) ->
  mt = moment()
  log.info(message)
  text = mt.format('YYYY-MM-DD HH:mm:ss') + " --> " + message + "\n"
  res = false
  try
    await util.promisify(fs.appendFile)("./logs/"+mt.format('YYYY-MM-DD')+".log", text)
    res = true
  catch
    res = false
  return res


default_data = loadJSON('./data/default_data.json')
setting_save = (settings) ->
  try
    await util.promisify(fs.writeFile)(settings.file, JSON.stringify(settings, null, 2))
  catch e
    add_log("save fail");
  return

default_data = loadJSON('./data/default_data.json')

try
  users = loadJSON('./config/admin_user.json')
catch
  users = default_data.users
  setting_save(users)

save = () ->
  return await setting_save(users)

reload = () ->
  user_backup = users
  try
    users = await loadJSONPromise('./config/admin_user.json')
  catch
    users = user_backup
    await add_log("Invalid user data JSON")
  return

check_permission = (user, permission_required) ->
  _permission = user.permissions
  permission = _permission
  if typeof(permission) != 'object'
    permission = users.permission_examples[_permission]
  if !permission
    await add_log("Permision not set:"+_permission)
    return false
  return permission[permission_required]

@auth = (name, pass, permission_required, action = 'unknown', no_log) ->
  await reload()
  user = users.users[name]
  if !user
    await add_log("Unknown user login. User: "+ name+", Permission needed: "+ permission_required+", Action: " +action)
    return false
  if user.password != pass
    await add_log("Unauthorized user login. User: "+ name+", Permission needed: "+ permission_required+", Action: " +action)
    return false
  if !user.enabled
    await add_log("Disabled user login. User: "+ name+", Permission needed: "+ permission_required+", Action: " +action)
    return false
  if !await check_permission(user, permission_required)
    await add_log("Permission denied. User: "+ name+", Permission needed: "+ permission_required+", Action: " +action)
    return false
  if !no_log
    await add_log("Operation success. User: "+ name+", Permission needed: "+ permission_required+", Action: " +action)
  return true

@add_user = (name, pass, enabled, permissions) ->
  await reload()
  if users.users[name]
    return false
  users.users[name] = {
    "password": pass,
    "enabled": enabled,
    "permissions": permissions
  }
  await save()
  return true

@delete_user = (name) ->
  await reload()
  if !users.users[name]
    return false
  delete users.users[name]
  await save()
  return

@update_user = (name, key, value) ->
  await reload()
  if !users.users[name]
    return false
  users.users[name][key] = value
  await save()
  return
