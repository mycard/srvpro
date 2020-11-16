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
exports.RandomDuelScore = void 0;
const typeorm_1 = require("typeorm");
let RandomDuelScore = class RandomDuelScore {
    getDisplayName() {
        return this.name.split("$")[0];
    }
    win() {
        ++this.winCount;
        ++this.winCombo;
    }
    lose() {
        ++this.loseCount;
        this.winCombo = 0;
    }
    flee() {
        ++this.fleeCount;
        this.lose();
    }
    getScoreText() {
        const displayName = this.getDisplayName();
        const total = this.winCount + this.loseCount;
        if (this.winCount < 2 && total < 3) {
            return `${displayName} \${random_this_not_enough}`;
        }
        if (this.winCombo >= 2) {
            return `\${random_this_part1}${displayName} \${random_this_part2} ${Math.ceil(this.winCount / total * 100)}\${random_this_part3} ${Math.ceil(this.fleeCount / total * 100)}\${random_this_part4_combo}${this.winCombo}\${random_this_part5_combo}`;
        }
        else {
            //return displayName + " 的今日战绩：胜率" + Math.ceil(this.winCount/total*100) + "%，逃跑率" + Math.ceil(this.fleeCount/total*100) + "%，" + this.winCombo + "连胜中！"
            return `\${random_this_part1}${displayName} \${random_this_part2} ${Math.ceil(this.winCount / total * 100)}\${random_this_part3} ${Math.ceil(this.fleeCount / total * 100)}\${random_this_part4}`;
        }
    }
};
__decorate([
    typeorm_1.PrimaryColumn({ type: "varchar", length: 20 }),
    __metadata("design:type", String)
], RandomDuelScore.prototype, "name", void 0);
__decorate([
    typeorm_1.Index(),
    typeorm_1.Column("int", { unsigned: true, default: 0 }),
    __metadata("design:type", Number)
], RandomDuelScore.prototype, "winCount", void 0);
__decorate([
    typeorm_1.Index(),
    typeorm_1.Column("int", { unsigned: true, default: 0 }),
    __metadata("design:type", Number)
], RandomDuelScore.prototype, "loseCount", void 0);
__decorate([
    typeorm_1.Index(),
    typeorm_1.Column("int", { unsigned: true, default: 0 }),
    __metadata("design:type", Number)
], RandomDuelScore.prototype, "fleeCount", void 0);
__decorate([
    typeorm_1.Column("int", { unsigned: true, default: 0 }),
    __metadata("design:type", Number)
], RandomDuelScore.prototype, "winCombo", void 0);
RandomDuelScore = __decorate([
    typeorm_1.Entity()
], RandomDuelScore);
exports.RandomDuelScore = RandomDuelScore;
//# sourceMappingURL=RandomDuelScore.js.map