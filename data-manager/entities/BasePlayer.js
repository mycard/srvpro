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
exports.BasePlayer = void 0;
const typeorm_1 = require("typeorm");
let BasePlayer = /** @class */ (() => {
    class BasePlayer {
    }
    __decorate([
        typeorm_1.PrimaryGeneratedColumn({ unsigned: true, type: "bigint" }),
        __metadata("design:type", Number)
    ], BasePlayer.prototype, "id", void 0);
    __decorate([
        typeorm_1.Column({ type: "varchar", length: 20 }),
        __metadata("design:type", String)
    ], BasePlayer.prototype, "name", void 0);
    __decorate([
        typeorm_1.Column({ type: "tinyint" }),
        __metadata("design:type", Number)
    ], BasePlayer.prototype, "pos", void 0);
    return BasePlayer;
})();
exports.BasePlayer = BasePlayer;
//# sourceMappingURL=BasePlayer.js.map