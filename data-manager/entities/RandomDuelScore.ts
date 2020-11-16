import {Column, Entity, Index, PrimaryColumn} from "typeorm";

@Entity()
export class RandomDuelScore {
    @PrimaryColumn({type: "varchar", length: 20})
    name: string;

    @Index()
    @Column("int", {unsigned: true, default: 0})
    winCount: number;

    @Index()
    @Column("int", {unsigned: true, default: 0})
    loseCount: number;

    @Index()
    @Column("int", {unsigned: true, default: 0})
    fleeCount: number;

    @Column("int", {unsigned: true, default: 0})
    winCombo: number;

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
            return `${displayName} \${random_score_not_enough}`;
        }
        if (this.winCombo >= 2) {
            return `\${random_score_part1}${displayName} \${random_score_part2} ${Math.ceil(this.winCount / total * 100)}\${random_score_part3} ${Math.ceil(this.fleeCount / total * 100)}\${random_score_part4_combo}${this.winCombo}\${random_score_part5_combo}`;
        } else {
            //return displayName + " 的今日战绩：胜率" + Math.ceil(this.winCount/total*100) + "%，逃跑率" + Math.ceil(this.fleeCount/total*100) + "%，" + this.winCombo + "连胜中！"
            return `\${random_score_part1}${displayName} \${random_score_part2} ${Math.ceil(this.winCount / total * 100)}\${random_score_part3} ${Math.ceil(this.fleeCount / total * 100)}\${random_score_part4}`;
        }
    }
}