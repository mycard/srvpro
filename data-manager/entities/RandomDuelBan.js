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
Object.defineProperty(exports, "__esModule", { value: true });
exports.RandomDuelBan = void 0;
const typeorm_1 = require("typeorm");
let RandomDuelBan = /** @class */ (() => {
    let RandomDuelBan = class RandomDuelBan {
        setNeedTip(need) {
            this.needTip = need ? 1 : 0;
        }
        getNeedTip() {
            return this.needTip > 0 ? true : false;
        }
    };
    __decorate([
        typeorm_1.PrimaryColumn({ type: "varchar", length: 64 }),
        __metadata("design:type", String)
    ], RandomDuelBan.prototype, "ip", void 0);
    __decorate([
        typeorm_1.Column("datetime"),
        __metadata("design:type", Date)
    ], RandomDuelBan.prototype, "time", void 0);
    __decorate([
        typeorm_1.Column("smallint"),
        __metadata("design:type", Number)
    ], RandomDuelBan.prototype, "count", void 0);
    __decorate([
        typeorm_1.Column({ type: "simple-array" }),
        __metadata("design:type", Array)
    ], RandomDuelBan.prototype, "reasons", void 0);
    __decorate([
        typeorm_1.Column({ type: "tinyint", unsigned: true }),
        __metadata("design:type", Number)
    ], RandomDuelBan.prototype, "needTip", void 0);
    RandomDuelBan = __decorate([
        typeorm_1.Entity()
    ], RandomDuelBan);
    return RandomDuelBan;
})();
exports.RandomDuelBan = RandomDuelBan;
//# sourceMappingURL=RandomDuelBan.js.map