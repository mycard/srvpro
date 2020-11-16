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
const User_1 = require("./entities/User");
const RandomDuelScore_1 = require("./entities/RandomDuelScore");
class DataManager {
    constructor(config, log) {
        this.config = config;
        this.ready = false;
        this.log = log;
    }
    async transaction(fun) {
        const runner = this.db.createQueryRunner();
        await runner.connect();
        await runner.startTransaction();
        let result = false;
        try {
            result = await fun(runner.manager);
        }
        catch (e) {
            result = false;
            this.log.warn(`Failed running transaction: ${e.toString()}`);
        }
        if (result) {
            await runner.commitTransaction();
        }
        else {
            await runner.rollbackTransaction();
        }
        await runner.release();
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
                .orderBy("replay.id", "DESC")
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
        replay.date = moment_1.default().toDate();
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
        duelLog.time = moment_1.default().toDate();
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
        score.win();
        await this.saveRandomDuelScore(score);
    }
    async randomDuelPlayerLose(name) {
        const score = await this.getOrCreateRandomDuelScore(name);
        score.lose();
        await this.saveRandomDuelScore(score);
    }
    async randomDuelPlayerFlee(name) {
        const score = await this.getOrCreateRandomDuelScore(name);
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