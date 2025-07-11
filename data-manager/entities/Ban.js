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
exports.Ban = void 0;
const typeorm_1 = require("typeorm");
const CreateAndUpdateTimeBase_1 = require("./CreateAndUpdateTimeBase");
let Ban = class Ban extends CreateAndUpdateTimeBase_1.CreateAndUpdateTimeBase {
};
exports.Ban = Ban;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)({ unsigned: true, type: global.PrimaryKeyType || 'bigint' }),
    __metadata("design:type", Number)
], Ban.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Index)(),
    (0, typeorm_1.Column)({ type: "varchar", length: 64, nullable: true }),
    __metadata("design:type", String)
], Ban.prototype, "ip", void 0);
__decorate([
    (0, typeorm_1.Index)(),
    (0, typeorm_1.Column)({ type: "varchar", length: 20, nullable: true }),
    __metadata("design:type", String)
], Ban.prototype, "name", void 0);
exports.Ban = Ban = __decorate([
    (0, typeorm_1.Entity)(),
    (0, typeorm_1.Unique)(["ip", "name"])
], Ban);
