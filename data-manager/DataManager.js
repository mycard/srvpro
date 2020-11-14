"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DataManager = void 0;
const moment_1 = __importDefault(require("moment"));
const typeorm_1 = require("typeorm");
const CloudReplay_1 = require("./entities/CloudReplay");
const CloudReplayPlayer_1 = require("./entities/CloudReplayPlayer");
const Ban_1 = require("./entities/Ban");
const RandomDuelBan_1 = require("./entities/RandomDuelBan");
const underscore_1 = __importDefault(require("underscore"));
const DuelLog_1 = require("./entities/DuelLog");
const DuelLogPlayer_1 = require("./entities/DuelLogPlayer");
class DataManager {
    constructor(config, log) {
        this.config = config;
        this.ready = false;
        this.log = log;
    }
    async init() {
        this.db = await typeorm_1.createConnection({
            type: "mysql",
            synchronize: true,
            entities: ["./data-manager/entities/*.js"],
            ...this.config
        });
        this.ready = true;
    }
    async getCloudReplaysFromKey(key) {
        try {
            const replays = await this.db.createQueryBuilder(CloudReplay_1.CloudReplay, "replay")
                .where("exists (select id from cloud_replay_player where cloud_replay_player.cloudReplayId = replay.id and cloud_replay_player.key = :key)", { key })
                .orderBy("replay.date", "DESC")
                .limit(10)
                .leftJoinAndSelect("replay.players", "player")
                .getMany();
            return replays;
        }
        catch (e) {
            this.log.warn(`Failed to load replay of ${key}: ${e.toString()}`);
            return [];
        }
    }
    async getCloudReplayFromId(id) {
        try {
            return await this.db.getRepository(CloudReplay_1.CloudReplay).findOne(id, { relations: ["players"] });
        }
        catch (e) {
            this.log.warn(`Failed to load replay R#${id}: ${e.toString()}`);
            return null;
        }
    }
    async getRandomCloudReplay() {
        try {
            return await this.db.createQueryBuilder(CloudReplay_1.CloudReplay, "replay")
                .orderBy("rand()")
                .limit(4) //there may be 4 players
                .leftJoinAndSelect("replay.players", "player")
                .getOne();
        }
        catch (e) {
            this.log.warn(`Failed to load random replay: ${e.toString()}`);
            return null;
        }
    }
    async saveCloudReplay(id, buffer, playerInfos) {
        const replay = new CloudReplay_1.CloudReplay();
        replay.id = id;
        replay.fromBuffer(buffer);
        replay.date = moment_1.default().toDate();
        const players = playerInfos.map(p => {
            const player = CloudReplayPlayer_1.CloudReplayPlayer.fromPlayerInfo(p);
            return player;
        });
        await this.db.transaction(async (mdb) => {
            try {
                const nreplay = await mdb.save(replay);
                for (let player of players) {
                    player.cloudReplay = nreplay;
                }
                await mdb.save(players);
            }
            catch (e) {
                this.log.warn(`Failed to save replay R#${replay.id}: ${e.toString()}`);
            }
        });
    }
    async checkBan(field, value) {
        const banQuery = {};
        banQuery[field] = value;
        try {
            return await this.db.getRepository(Ban_1.Ban).findOne(banQuery);
        }
        catch (e) {
            this.log.warn(`Failed to load ban ${field} ${value}: ${e.toString()}`);
            return null;
        }
    }
    async checkBanWithNameAndIP(name, ip) {
        try {
            return await this.db.getRepository(Ban_1.Ban).findOne({ name, ip });
        }
        catch (e) {
            this.log.warn(`Failed to load ban ${name} ${ip}: ${e.toString()}`);
            return null;
        }
    }
    getBan(name, ip) {
        const ban = new Ban_1.Ban();
        ban.ip = ip;
        ban.name = name;
        return ban;
    }
    async banPlayer(ban) {
        try {
            const repo = this.db.getRepository(Ban_1.Ban);
            if (await repo.findOne({
                ip: ban.ip,
                name: ban.name
            })) {
                return;
            }
            return await repo.save(ban);
        }
        catch (e) {
            this.log.warn(`Failed to update ban ${JSON.stringify(ban)}: ${e.toString()}`);
            return null;
        }
    }
    async getRandomDuelBan(ip) {
        const repo = this.db.getRepository(RandomDuelBan_1.RandomDuelBan);
        try {
            const ban = await repo.findOne(ip);
            //console.log(ip, ban);
            return ban;
        }
        catch (e) {
            this.log.warn(`Failed to fetch random duel ban ${ip}: ${e.toString()}`);
            return null;
        }
    }
    async updateRandomDuelBan(ban) {
        const repo = this.db.getRepository(RandomDuelBan_1.RandomDuelBan);
        try {
            await repo.save(ban);
        }
        catch (e) {
            this.log.warn(`Failed to update random duel ban ${ban.ip}: ${e.toString()}`);
        }
    }
    async randomDuelBanPlayer(ip, reason, countadd) {
        const count = countadd || 1;
        const repo = this.db.getRepository(RandomDuelBan_1.RandomDuelBan);
        try {
            let ban = await repo.findOne(ip);
            if (ban) {
                ban.count += count;
                const banTime = ban.count > 3 ? Math.pow(2, ban.count - 3) * 2 : 0;
                const banDate = moment_1.default(ban.time);
                if (moment_1.default().isAfter(banDate)) {
                    ban.time = moment_1.default().add(banTime, 'm').toDate();
                }
                else {
                    ban.time = moment_1.default(banDate).add(banTime, 'm').toDate();
                }
                if (!underscore_1.default.contains(ban.reasons, reason)) {
                    ban.reasons.push(reason);
                }
                ban.needTip = 1;
            }
            else {
                ban = new RandomDuelBan_1.RandomDuelBan();
                ban.ip = ip;
                ban.time = moment_1.default().toDate();
                ban.count = count;
                ban.reasons = [reason];
                ban.needTip = 1;
            }
            return await repo.save(ban);
        }
        catch (e) {
            this.log.warn(`Failed to update random duel ban ${ip}: ${e.toString()}`);
            return null;
        }
    }
    async getAllDuelLogs() {
        const repo = this.db.getRepository(DuelLog_1.DuelLog);
        try {
            const allDuelLogs = await repo.find({ relations: ["players"] });
            return allDuelLogs;
        }
        catch (e) {
            this.log.warn(`Failed to fetch duel logs: ${e.toString()}`);
            return [];
        }
    }
    async getDuelLogFromId(id) {
        const repo = this.db.getRepository(DuelLog_1.DuelLog);
        try {
            const duelLog = await repo.findOne(id, { relations: ["players"] });
            return duelLog;
        }
        catch (e) {
            this.log.warn(`Failed to fetch duel logs: ${e.toString()}`);
            return null;
        }
    }
    async getDuelLogFromRecoverSearch(realName) {
        const repo = this.db.getRepository(DuelLog_1.DuelLog);
        try {
            const duelLogs = await repo.createQueryBuilder("duelLog")
                .where("startDeckBuffer is not null and currentDeckBuffer is not null and roomMode != 2 and exists (select id from duel_log_player where duel_log_player.duelLogId = duelLog.id and duel_log_player.realName = :realName)", { realName })
                .orderBy("duelLog.id", "DESC")
                .limit(10)
                .leftJoinAndSelect("duelLog.players", "player")
                .getMany();
            return duelLogs;
        }
        catch (e) {
            this.log.warn(`Failed to fetch duel logs: ${e.toString()}`);
            return null;
        }
    }
    async getDuelLogJSON(tournamentModeSettings) {
        const allDuelLogs = await this.getAllDuelLogs();
        return allDuelLogs.map(duelLog => duelLog.getViewJSON(tournamentModeSettings));
    }
    async getAllReplayFilenames() {
        const allDuelLogs = await this.getAllDuelLogs();
        return allDuelLogs.map(duelLog => duelLog.replayFileName);
    }
    async clearDuelLog() {
        //await this.db.transaction(async (mdb) => {
        const runner = this.db.createQueryRunner();
        try {
            await runner.connect();
            await runner.startTransaction();
            await runner.query("SET FOREIGN_KEY_CHECKS = 0; ");
            await runner.clearTable("duel_log_player");
            await runner.clearTable("duel_log");
            await runner.query("SET FOREIGN_KEY_CHECKS = 1; ");
            await runner.commitTransaction();
        }
        catch (e) {
            await runner.rollbackTransaction();
            this.log.warn(`Failed to clear duel logs: ${e.toString()}`);
        }
        //});
    }
    async saveDuelLog(name, roomId, cloudReplayId, replayFilename, roomMode, duelCount, playerInfos) {
        const duelLog = new DuelLog_1.DuelLog();
        duelLog.name = name;
        duelLog.time = moment_1.default().toDate();
        duelLog.roomId = roomId;
        duelLog.cloudReplayId = cloudReplayId;
        duelLog.replayFileName = replayFilename;
        duelLog.roomMode = roomMode;
        duelLog.duelCount = duelCount;
        const players = playerInfos.map(p => DuelLogPlayer_1.DuelLogPlayer.fromDuelLogPlayerInfo(p));
        await this.db.transaction(async (mdb) => {
            try {
                const savedDuelLog = await mdb.save(duelLog);
                for (let player of players) {
                    player.duelLog = savedDuelLog;
                }
                await mdb.save(players);
            }
            catch (e) {
                this.log.warn(`Failed to save duel log ${name}: ${e.toString()}`);
            }
        });
    }
}
exports.DataManager = DataManager;
//# sourceMappingURL=DataManager.js.map