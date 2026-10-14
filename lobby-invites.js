"use strict";

const crypto = require("crypto");

// These values are consumed by the gateway and never forwarded to ocgcore.
const METADATA_GAME_ID = 0x4d445034;
const INVITATION_GAME_ID = 0x4d445035;
const KEY_PATTERN = /^[A-Za-z0-9_-]{12}$/;

function createKey() {
  return crypto.randomBytes(9).toString("base64").replace(/\+/g, "-").replace(/\//g, "_");
}

function enabled(settings) {
  const modules = settings.modules;
  return !!(modules.http.public_roomlist || modules.http.websocket_roomlist) &&
    !modules.stop && !modules.tournament_mode.enabled && !modules.challonge.enabled;
}

function backend(settings) {
  return settings.modules.mycard.enabled ? "mycard" : "srvpro";
}

function negotiate(info, client) {
  client.invitationRequest = info.gameid === INVITATION_GAME_ID;
  client.supportsLobbyMetadata = client.invitationRequest || info.gameid === METADATA_GAME_ID;
  if (!client.supportsLobbyMetadata) return false;
  info.gameid = 0;
  return true;
}

function capacity(room) {
  const slots = room.hostinfo.mode === 2 ? 4 : 2;
  return room.max_player > 0 ? Math.min(room.max_player, slots) : slots;
}

function occupied(room) {
  // An undefined position is a pending connection that already owns a seat.
  // Keep closed sockets counted until Room.disconnect actually removes them.
  return room.players.filter(player => player && player.pos !== 7).length;
}

function publicWaiting(room, settings) {
  return enabled(settings) && !!room && KEY_PATTERN.test(room.inviteId) &&
    room.established && !room.deleted && !room.error && !room.finished &&
    room.duel_stage === 0 && !room.private && !room.random_type && !room.arena &&
    !room.windbot && !room.challonge_info && !room.recover_duel_log_id &&
    typeof room.name === "string" && !room.name.includes("$") && occupied(room) > 0;
}

function joinable(room, settings) {
  return publicWaiting(room, settings) && occupied(room) < capacity(room);
}

function findForInvitation(rooms, key, client, settings) {
  if (!client.invitationRequest || !KEY_PATTERN.test(key)) return null;
  const room = rooms.find(candidate => candidate && candidate.inviteId === key);
  if (!joinable(room, settings)) return null;
  client.inviteRoomKey = key;
  return room;
}

function mayAdmit(room, client, settings) {
  if (client.inviteRoomKey === undefined) return !client.invitationRequest;
  return client.invitationRequest && room.inviteId === client.inviteRoomKey && joinable(room, settings);
}

function metadata(room, client, settings) {
  if (!client.supportsLobbyMetadata || client.isClosed || !publicWaiting(room, settings) ||
      !room.players.includes(client) || !Number.isInteger(client.pos) ||
      client.pos < 0 || client.pos >= capacity(room)) return null;
  const frame = Buffer.alloc(17);
  frame.writeUInt16LE(15, 0);
  frame[2] = 0xf2;
  frame[3] = 2;
  frame[4] = backend(settings) === "mycard" ? 2 : 1;
  frame.write(room.inviteId, 5, 12, "ascii");
  return frame;
}

function listing(rooms, settings) {
  return {
    version: 1,
    backend: backend(settings),
    enabled: enabled(settings),
    rooms: rooms.filter(room => joinable(room, settings)).map(room => ({
      inviteId: room.inviteId,
      players: occupied(room),
      maxPlayers: capacity(room)
    }))
  };
}

module.exports = {
  METADATA_GAME_ID, INVITATION_GAME_ID, createKey, enabled, negotiate, capacity, occupied,
  publicWaiting, joinable, findForInvitation, mayAdmit, metadata, listing
};
