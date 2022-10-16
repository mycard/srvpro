"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
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
const User_1 = require("./entities/User");
const RandomDuelScore_1 = require("./entities/RandomDuelScore");
const jszip_1 = __importDefault(require("jszip"));
const fs = __importStar(require("fs"));
require("reflect-metadata");
class DataManager {
    config;
    log;
    ready;
    db;
    constructor(config, log) {
        this.config = config;
        this.log = log;
        this.ready = false;
    }
    async transaction(fun) {
        try {
            // @ts-ignore
            if (this.config.type !== 'sqlite') {
                await this.db.transaction(async (mdb) => {
                    const result = await fun(mdb);
                    if (!result) {
                        throw new Error('Rollback requested.');
                    }
                });
            }
            else {
                await fun(this.db.manager);
            }
        }
        catch (e) {
            this.log.warn(`Transaction failed: ${e.toString()}`);
        }
    }
    async init() {
        this.db = await (0, typeorm_1.createConnection)({
            type: "mysql",
            synchronize: true,
            supportBigNumbers: true,
            bigNumberStrings: false,
            entities: ["./data-manager/entities/*.js"],
            ...this.config
        });
        this.ready = true;
    }
    async getCloudReplaysFromKey(key) {
        try {
            const replaysQuery = this.db.createQueryBuilder(CloudReplay_1.CloudReplay, "replay");
            const sqb = replaysQuery.subQuery()
                .select('splayer.id')
                .from(CloudReplayPlayer_1.CloudReplayPlayer, 'splayer')
                .where('splayer.cloudReplayId = replay.id')
                .andWhere('splayer.key = :key');
            const replays = await replaysQuery.where(`exists ${sqb.getQuery()}`, { key })
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
            const [minQuery, maxQuery] = await Promise.all(["min", "max"].map(minOrMax => this.db.createQueryBuilder()
                .select(`${minOrMax}(id)`, "value")
                .from(CloudReplay_1.CloudReplay, "replay")
                .getRawOne()));
            if (!minQuery || !maxQuery) {
                return null;
            }
            const [minId, maxId] = [minQuery, maxQuery].map(query => parseInt(query.value));
            const targetId = Math.floor((maxId - minId) * Math.random()) + minId;
            return await this.db.createQueryBuilder(CloudReplay_1.CloudReplay, "replay")
                .where("replay.id >= :targetId", { targetId })
                .orderBy("replay.id", "ASC")
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
        replay.date = (0, moment_1.default)().toDate();
        const players = playerInfos.map(p => {
            const player = CloudReplayPlayer_1.CloudReplayPlayer.fromPlayerInfo(p);
            return player;
        });
        await this.transaction(async (mdb) => {
            try {
                const nreplay = await mdb.save(replay);
                for (let player of players) {
                    player.cloudReplay = nreplay;
                }
                await mdb.save(players);
                return true;
            }
            catch (e) {
                this.log.warn(`Failed to save replay R#${replay.id}: ${e.toString()}`);
                return false;
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
                const banDate = (0, moment_1.default)(ban.time);
                if ((0, moment_1.default)().isAfter(banDate)) {
                    ban.time = (0, moment_1.default)().add(banTime, 'm').toDate();
                }
                else {
                    ban.time = (0, moment_1.default)(banDate).add(banTime, 'm').toDate();
                }
                if (!underscore_1.default.contains(ban.reasons, reason)) {
                    ban.reasons.push(reason);
                }
                ban.needTip = 1;
            }
            else {
                ban = new RandomDuelBan_1.RandomDuelBan();
                ban.ip = ip;
                ban.time = (0, moment_1.default)().toDate();
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
    getEscapedString(text) {
        return text.replace(/\\/g, "").replace(/_/g, "\\_").replace(/%/g, "\\%") + "%";
    }
    async getDuelLogFromCondition(data) {
        //console.log(data);
        if (!data) {
            return this.getAllDuelLogs();
        }
        const { roomName, duelCount, playerName, playerScore } = data;
        const repo = this.db.getRepository(DuelLog_1.DuelLog);
        try {
            const queryBuilder = repo.createQueryBuilder("duelLog")
                .where("1");
            if (roomName != null && roomName.length) {
                //const escapedRoomName = this.getEscapedString(roomName);
                queryBuilder.andWhere("duelLog.name = :roomName", { roomName });
            }
            if (duelCount != null && !isNaN(duelCount)) {
                queryBuilder.andWhere("duelLog.duelCount = :duelCount", { duelCount });
            }
            if (playerName != null && playerName.length || playerScore != null && !isNaN(playerScore)) {
                const sqb = queryBuilder.subQuery()
                    .select('splayer.id')
                    .from(DuelLogPlayer_1.DuelLogPlayer, 'splayer')
                    .where('splayer.duelLogId = duelLog.id');
                //let innerQuery = "select id from duel_log_player where duel_log_player.duelLogId = duelLog.id";
                const innerQueryParams = {};
                if (playerName != null && playerName.length) {
                    //const escapedPlayerName = this.getEscapedString(playerName);
                    sqb.andWhere('splayer.realName = :playerName');
                    //innerQuery += " and duel_log_player.realName = :playerName";
                    innerQueryParams.playerName = playerName;
                }
                if (playerScore != null && !isNaN(playerScore)) {
                    //innerQuery += " and duel_log_player.score = :playerScore";
                    sqb.andWhere('splayer.score = :playerScore');
                    innerQueryParams.playerScore = playerScore;
                }
                queryBuilder.andWhere(`exists ${sqb.getQuery()}`, innerQueryParams);
            }
            queryBuilder.orderBy("duelLog.id", "DESC")
                .leftJoinAndSelect("duelLog.players", "player");
            // console.log(queryBuilder.getSql());
            const duelLogs = await queryBuilder.getMany();
            return duelLogs;
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
            const duelLogsQuery = repo.createQueryBuilder("duelLog")
                .where('startDeckBuffer is not null')
                .andWhere('currentDeckBuffer is not null')
                .andWhere('roomMode != 2');
            const sqb = duelLogsQuery.subQuery()
                .select('splayer.id')
                .from(DuelLogPlayer_1.DuelLogPlayer, 'splayer')
                .andWhere('splayer.duelLogId = duelLog.id')
                .andWhere('splayer.realName = :realName');
            const duelLogs = await duelLogsQuery.andWhere(`exists ${sqb.getQuery()}`, { realName })
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
    async getDuelLogJSONFromCondition(tournamentModeSettings, data) {
        const allDuelLogs = await this.getDuelLogFromCondition(data);
        return allDuelLogs.map(duelLog => duelLog.getViewJSON(tournamentModeSettings));
    }
    async getAllReplayFilenames() {
        const allDuelLogs = await this.getAllDuelLogs();
        return allDuelLogs.map(duelLog => duelLog.replayFileName);
    }
    async getReplayFilenamesFromCondition(data) {
        const allDuelLogs = await this.getDuelLogFromCondition(data);
        return allDuelLogs.map(duelLog => duelLog.replayFileName);
    }
    async getReplayArchiveStreamFromCondition(rootPath, data) {
        const filenames = await this.getReplayFilenamesFromCondition(data);
        if (!filenames.length) {
            return null;
        }
        try {
            const zip = new jszip_1.default();
            for (let fileName of filenames) {
                const filePath = `${rootPath}${fileName}`;
                try {
                    await fs.promises.access(filePath);
                    zip.file(fileName, fs.promises.readFile(filePath));
                }
                catch (e) {
                    this.log.warn(`Errored archiving ${filePath}: ${e.toString()}`);
                    continue;
                }
            }
            return zip.generateNodeStream({
                compression: "DEFLATE",
                compressionOptions: {
                    level: 9
                }
            });
        }
        catch (e2) {
            this.log.warn(`Errored creating archive: ${e2.toString()}`);
            return null;
        }
    }
    async clearDuelLog() {
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
        await runner.release();
    }
    async saveDuelLog(name, roomId, cloudReplayId, replayFilename, roomMode, duelCount, playerInfos) {
        const duelLog = new DuelLog_1.DuelLog();
        duelLog.name = name;
        duelLog.time = (0, moment_1.default)().toDate();
        duelLog.roomId = roomId;
        duelLog.cloudReplayId = cloudReplayId;
        duelLog.replayFileName = replayFilename;
        duelLog.roomMode = roomMode;
        duelLog.duelCount = duelCount;
        const players = playerInfos.map(p => DuelLogPlayer_1.DuelLogPlayer.fromDuelLogPlayerInfo(p));
        await this.transaction(async (mdb) => {
            try {
                const savedDuelLog = await mdb.save(duelLog);
                for (let player of players) {
                    player.duelLog = savedDuelLog;
                }
                await mdb.save(players);
                return true;
            }
            catch (e) {
                this.log.warn(`Failed to save duel log ${name}: ${e.toString()}`);
                return false;
            }
        });
    }
    async getUser(key) {
        const repo = this.db.getRepository(User_1.User);
        try {
            const user = await repo.findOne(key);
            return user;
        }
        catch (e) {
            this.log.warn(`Failed to fetch user: ${e.toString()}`);
            return null;
        }
    }
    async getOrCreateUser(key) {
        const user = await this.getUser(key);
        if (user) {
            return user;
        }
        const newUser = new User_1.User();
        newUser.key = key;
        return await this.saveUser(newUser);
    }
    async saveUser(user) {
        const repo = this.db.getRepository(User_1.User);
        try {
            return await repo.save(user);
        }
        catch (e) {
            this.log.warn(`Failed to save user: ${e.toString()}`);
            return null;
        }
    }
    async getUserChatColor(key) {
        const user = await this.getUser(key);
        return user ? user.chatColor : null;
    }
    async setUserChatColor(key, color) {
        let user = await this.getOrCreateUser(key);
        user.chatColor = color;
        return await this.saveUser(user);
    }
    async migrateChatColors(data) {
        await this.transaction(async (mdb) => {
            try {
                const users = [];
                for (let key in data) {
                    const chatColor = data[key];
                    let user = await mdb.findOne(User_1.User, key);
                    if (!user) {
                        user = new User_1.User();
                        user.key = key;
                    }
                    user.chatColor = chatColor;
                    users.push(user);
                }
                await mdb.save(users);
                return true;
            }
            catch (e) {
                this.log.warn(`Failed to migrate chat color data: ${e.toString()}`);
                return false;
            }
        });
    }
    async getRandomDuelScore(name) {
        const repo = this.db.getRepository(RandomDuelScore_1.RandomDuelScore);
        try {
            const score = await repo.findOne(name);
            return score;
        }
        catch (e) {
            this.log.warn(`Failed to fetch random duel score ${name}: ${e.toString()}`);
            return null;
        }
    }
    async saveRandomDuelScore(score) {
        const repo = this.db.getRepository(RandomDuelScore_1.RandomDuelScore);
        try {
            return await repo.save(score);
        }
        catch (e) {
            this.log.warn(`Failed to save random duel score: ${e.toString()}`);
            return null;
        }
    }
    async getOrCreateRandomDuelScore(name) {
        const score = await this.getRandomDuelScore(name);
        if (score) {
            return score;
        }
        const newScore = new RandomDuelScore_1.RandomDuelScore();
        newScore.name = name;
        return await this.saveRandomDuelScore(newScore);
    }
    async getRandomDuelScoreDisplay(name) {
        const score = await this.getRandomDuelScore(name);
        if (!score) {
            return `${name.split("$")[0]} \${random_score_blank}`;
        }
        return score.getScoreText();
    }
    async randomDuelPlayerWin(name) {
        const score = await this.getOrCreateRandomDuelScore(name);
        if (!score) {
            return;
        }
        score.win();
        await this.saveRandomDuelScore(score);
    }
    async randomDuelPlayerLose(name) {
        const score = await this.getOrCreateRandomDuelScore(name);
        if (!score) {
            return;
        }
        score.lose();
        await this.saveRandomDuelScore(score);
    }
    async randomDuelPlayerFlee(name) {
        const score = await this.getOrCreateRandomDuelScore(name);
        if (!score) {
            return;
        }
        score.flee();
        await this.saveRandomDuelScore(score);
    }
    async getRandomScoreTop10() {
        try {
            const scores = await this.db.getRepository(RandomDuelScore_1.RandomDuelScore)
                .createQueryBuilder("score")
                .orderBy("score.win", "DESC")
                .addOrderBy("score.lose", "ASC")
                .addOrderBy("score.flee", "ASC")
                .limit(10)
                .getMany();
            return scores.map(score => [score.getDisplayName(), {
                    win: score.winCount,
                    lose: score.loseCount,
                    flee: score.fleeCount,
                    combo: score.winCombo
                }]);
        }
        catch (e) {
            this.log.warn(`Failed to fetch random duel score ${name}: ${e.toString()}`);
            return [];
        }
    }
}
exports.DataManager = DataManager;
//# sourceMappingURL=DataManager.js.map