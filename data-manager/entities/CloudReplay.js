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
exports.CloudReplay = void 0;
const typeorm_1 = require("typeorm");
const CloudReplayPlayer_1 = require("./CloudReplayPlayer");
const underscore_1 = __importDefault(require("underscore"));
const moment_1 = __importDefault(require("moment"));
const CreateAndUpdateTimeBase_1 = require("./CreateAndUpdateTimeBase");
let CloudReplay = class CloudReplay extends CreateAndUpdateTimeBase_1.CreateAndUpdateTimeBase {
    fromBuffer(buffer) {
        this.data = buffer.toString("base64");
    }
    toBuffer() {
        return Buffer.from(this.data, "base64");
    }
    getDateString() {
        return moment_1.default(this.date).format('YYYY-MM-DD HH:mm:ss');
    }
    getPlayerNamesString() {
        const playerInfos = underscore_1.default.clone(this.players);
        playerInfos.sort((p1, p2) => p1.pos - p2.pos);
        return playerInfos[0].name + (playerInfos[2] ? "+" + playerInfos[2].name : "") + " VS " + (playerInfos[1] ? playerInfos[1].name : "AI") + (playerInfos[3] ? "+" + playerInfos[3].name : "");
    }
    getDisplayString() {
        return `R#${this.id} ${this.getPlayerNamesString()} ${this.getDateString()}`;
    }
};
__decorate([
    typeorm_1.PrimaryColumn({ unsigned: true, type: "bigint" }),
    __metadata("design:type", Number)
], CloudReplay.prototype, "id", void 0);
__decorate([
    typeorm_1.Column({ type: "text" }),
    __metadata("design:type", String)
], CloudReplay.prototype, "data", void 0);
__decorate([
    typeorm_1.Index(),
    typeorm_1.Column({ type: "datetime" }),
    __metadata("design:type", Date)
], CloudReplay.prototype, "date", void 0);
__decorate([
    typeorm_1.OneToMany(() => CloudReplayPlayer_1.CloudReplayPlayer, player => player.cloudReplay),
    __metadata("design:type", Array)
], CloudReplay.prototype, "players", void 0);
CloudReplay = __decorate([
    typeorm_1.Entity({
        orderBy: {
            date: "DESC"
        }
    })
], CloudReplay);
exports.CloudReplay = CloudReplay;
//# sourceMappingURL=CloudReplay.js.map