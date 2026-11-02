# The enumerable registry contains only lightweight state, never client sockets.
class MycardSpectatorReplay
  constructor: ->
    @identities = new WeakMap()
    @sessions = new WeakMap()
    @observers = new Map()

  authenticate: (client, user) ->
    @identities.set(client, {username: user.username, active: user.active})
    return

  observe: (client, roomName) ->
    identity = @identities.get(client)
    return unless identity
    session = @sessions.get(client)
    if !session or session.roomName != roomName
      @unobserve(client)
      session = {username: identity.username, roomName, blockedByMultipleRooms: false}
      @sessions.set(client, session)
    rooms = @observers.get(session.username)
    unless rooms
      rooms = new Map()
      @observers.set(session.username, rooms)
    sessions = rooms.get(roomName)
    unless sessions
      sessions = new Set()
      rooms.set(roomName, sessions)
    sessions.add(session)
    if rooms.size > 1
      for roomSessions from rooms.values()
        for current from roomSessions
          current.blockedByMultipleRooms = true
    return

  unobserve: (client) ->
    session = @sessions.get(client)
    return unless session
    rooms = @observers.get(session.username)
    sessions = rooms?.get(session.roomName)
    sessions?.delete(session)
    rooms?.delete(session.roomName) unless sessions?.size
    @observers.delete(session.username) unless rooms?.size
    return

  leave: (client) ->
    @unobserve(client)
    @sessions.delete(client)
    @identities.delete(client)
    return

  clearRoom: (roomName) ->
    for [username, rooms] from @observers
      rooms.delete(roomName)
      @observers.delete(username) unless rooms.size
    return

  blocked: (client, restrictMultiRoom = false, restrictUnverified = false) ->
    session = @sessions.get(client)
    return false unless session
    blockedByMultipleRooms = restrictMultiRoom and session.blockedByMultipleRooms
    blockedByUnverifiedEmail = restrictUnverified and @identities.get(client)?.active is false
    return !!(blockedByMultipleRooms or blockedByUnverifiedEmail)

module.exports = {MycardSpectatorReplay}
