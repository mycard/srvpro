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
var DuelLogPlayer_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.DuelLogPlayer = void 0;
const typeorm_1 = require("typeorm");
const BasePlayer_1 = require("./BasePlayer");
const DuelLog_1 = require("./DuelLog");
const DeckEncoder_1 = require("../DeckEncoder");
let DuelLogPlayer = DuelLogPlayer_1 = class DuelLogPlayer extends BasePlayer_1.BasePlayer {
    setStartDeck(deck) {
        if (deck === null) {
            this.startDeckBuffer = null;
            return;
        }
        this.startDeckBuffer = DeckEncoder_1.encodeDeck(deck).toString("base64");
    }
    getStartDeck() {
        return DeckEncoder_1.decodeDeck(Buffer.from(this.startDeckBuffer, "base64"));
    }
    setCurrentDeck(deck) {
        if (deck === null) {
            this.currentDeckBuffer = null;
            return;
        }
        this.currentDeckBuffer = DeckEncoder_1.encodeDeck(deck).toString("base64");
    }
    getCurrentDeck() {
        return DeckEncoder_1.decodeDeck(Buffer.from(this.currentDeckBuffer, "base64"));
    }
    static fromDuelLogPlayerInfo(info) {
        const p = new DuelLogPlayer_1();
        p.name = info.name;
        p.pos = info.pos;
        p.realName = info.realName;
        p.lp = info.lp;
        p.ip = info.ip;
        p.score = info.score;
        p.cardCount = info.cardCount;
        p.isFirst = info.isFirst ? 1 : 0;
        p.winner = info.winner ? 1 : 0;
        p.startDeckBuffer = info.startDeckBuffer.toString("base64");
        p.setCurrentDeck(info.deck);
        return p;
    }
};
__decorate([
    typeorm_1.Index(),
    typeorm_1.Column({ type: "varchar", length: 20 }),
    __metadata("design:type", String)
], DuelLogPlayer.prototype, "realName", void 0);
__decorate([
    typeorm_1.Column({ type: "varchar", length: 64, nullable: true }),
    __metadata("design:type", String)
], DuelLogPlayer.prototype, "ip", void 0);
__decorate([
    typeorm_1.Column("tinyint", { unsigned: true }),
    __metadata("design:type", Number)
], DuelLogPlayer.prototype, "isFirst", void 0);
__decorate([
    typeorm_1.Index(),
    typeorm_1.Column("tinyint"),
    __metadata("design:type", Number)
], DuelLogPlayer.prototype, "score", void 0);
__decorate([
    typeorm_1.Column("int", { nullable: true }),
    __metadata("design:type", Number)
], DuelLogPlayer.prototype, "lp", void 0);
__decorate([
    typeorm_1.Column("smallint", { nullable: true }),
    __metadata("design:type", Number)
], DuelLogPlayer.prototype, "cardCount", void 0);
__decorate([
    typeorm_1.Column("text", { nullable: true }),
    __metadata("design:type", String)
], DuelLogPlayer.prototype, "startDeckBuffer", void 0);
__decorate([
    typeorm_1.Column("text", { nullable: true }),
    __metadata("design:type", String)
], DuelLogPlayer.prototype, "currentDeckBuffer", void 0);
__decorate([
    typeorm_1.Column("tinyint"),
    __metadata("design:type", Number)
], DuelLogPlayer.prototype, "winner", void 0);
__decorate([
    typeorm_1.ManyToOne(() => DuelLog_1.DuelLog, duelLog => duelLog.players),
    __metadata("design:type", DuelLog_1.DuelLog)
], DuelLogPlayer.prototype, "duelLog", void 0);
DuelLogPlayer = DuelLogPlayer_1 = __decorate([
    typeorm_1.Entity()
], DuelLogPlayer);
exports.DuelLogPlayer = DuelLogPlayer;
//# sourceMappingURL=DuelLogPlayer.js.map