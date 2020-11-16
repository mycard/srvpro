import {Column, Entity, PrimaryColumn} from "typeorm";


@Entity()
export class RandomDuelBan {
    @PrimaryColumn({type: "varchar", length: 64})
    ip: string;

    @Column("datetime")
    time: Date;

    @Column("smallint")
    count: number;

    @Column({type: "simple-array"})
    reasons: string[]

    @Column({type: "tinyint", unsigned: true})
    needTip: number;

    setNeedTip(need: boolean) {
        this.needTip = need ? 1 : 0;
    }

    getNeedTip() {
        return this.needTip > 0 ? true : false;
    }
}