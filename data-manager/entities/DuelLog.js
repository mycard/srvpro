"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DuelLog = void 0;
const typeorm_1 = require("typeorm");
const DuelLogPlayer_1 = require("./DuelLogPlayer");
const moment_1 = __importDefault(require("moment"));
const underscore_1 = __importDefault(require("underscore"));
const CreateAndUpdateTimeBase_1 = require("./CreateAndUpdateTimeBase");
let DuelLog = class DuelLog extends CreateAndUpdateTimeBase_1.CreateAndUpdateTimeBase {
    getViewString() {
        const viewPlayers = underscore_1.default.clone(this.players);
        viewPlayers.sort((p1, p2) => p1.pos - p2.pos);
        const playerString = viewPlayers[0].realName.split("$")[0] + (viewPlayers[2] ? "+" + viewPlayers[2].realName.split("$")[0] : "") + " VS " + (viewPlayers[1] ? viewPlayers[1].realName.split("$")[0] : "AI") + (viewPlayers[3] ? "+" + viewPlayers[3].realName.split("$")[0] : "");
        return `<${this.id}> ${playerString} ${moment_1.default(this.time).format("YYYY-MM-DD HH-mm-ss")}`;
    }
    getViewJSON(tournamentModeSettings) {
        const data = {
            id: this.id,
            time: moment_1.default(this.time).format("YYYY-MM-DD HH:mm:ss"),
            name: this.name + (tournamentModeSettings.show_info ? " (Duel:" + this.duelCount + ")" : ""),
            roomid: this.roomId,
            cloud_replay_id: "R#" + this.cloudReplayId,
            replay_filename: this.replayFileName,
            roommode: this.roomMode,
            players: this.players.map(player => {
                return {
                    pos: player.pos,
                    is_first: player.isFirst === 1,
                    name: player.name + (tournamentModeSettings.show_ip ? " (IP: " + player.ip.slice(7) + ")" : "") + (tournamentModeSettings.show_info && !(this.roomMode === 2 && player.pos % 2 > 0) ? " (Score:" + player.score + " LP:" + (player.lp != null ? player.lp : "???") + (this.roomMode !== 2 ? " Cards:" + (player.cardCount != null ? player.cardCount : "???") : "") + ")" : ""),
                    winner: player.winner === 1
                };
            })
        };
        return data;
    }
};
__decorate([
    typeorm_1.PrimaryGeneratedColumn({ unsigned: true, type: "bigint" }),
    __metadata("design:type", Number)
], DuelLog.prototype, "id", void 0);
__decorate([
    typeorm_1.Index(),
    typeorm_1.Column("datetime"),
    __metadata("design:type", Date)
], DuelLog.prototype, "time", void 0);
__decorate([
    typeorm_1.Index(),
    typeorm_1.Column({ type: "varchar", length: 20 }),
    __metadata("design:type", String)
], DuelLog.prototype, "name", void 0);
__decorate([
    typeorm_1.Column("int"),
    __metadata("design:type", Number)
], DuelLog.prototype, "roomId", void 0);
__decorate([
    typeorm_1.Column("bigint"),
    __metadata("design:type", Number)
], DuelLog.prototype, "cloudReplayId", void 0);
__decorate([
    typeorm_1.Column({ type: "varchar", length: 256 }),
    __metadata("design:type", String)
], DuelLog.prototype, "replayFileName", void 0);
__decorate([
    typeorm_1.Column("tinyint", { unsigned: true }),
    __metadata("design:type", Number)
], DuelLog.prototype, "roomMode", void 0);
__decorate([
    typeorm_1.Index(),
    typeorm_1.Column("tinyint", { unsigned: true }),
    __metadata("design:type", Number)
], DuelLog.prototype, "duelCount", void 0);
__decorate([
    typeorm_1.OneToMany(() => DuelLogPlayer_1.DuelLogPlayer, player => player.duelLog),
    __metadata("design:type", Array)
], DuelLog.prototype, "players", void 0);
DuelLog = __decorate([
    typeorm_1.Entity({
        orderBy: {
            id: "DESC"
        }
    })
], DuelLog);
exports.DuelLog = DuelLog;
//# sourceMappingURL=DuelLog.js.map