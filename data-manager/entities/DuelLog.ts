import {Column, Entity, Index, OneToMany, PrimaryGeneratedColumn} from "typeorm";
import {DuelLogPlayer} from "./DuelLogPlayer";
import moment from "moment";
import _ from "underscore";
import {CreateAndUpdateTimeBase} from "./CreateAndUpdateTimeBase";

@Entity({
    orderBy: {
        id: "DESC"
    }
})
export class DuelLog extends CreateAndUpdateTimeBase {
    @PrimaryGeneratedColumn({unsigned: true, type: "bigint"})
    id: number;

    @Index()
    @Column("datetime")
    time: Date;

    @Index()
    @Column({type: "varchar", length: 20})
    name: string;

    @Column("int")
    roomId: number;

    @Column("bigint")
    cloudReplayId: number; // not very needed to become a relation

    @Column({type: "varchar", length: 256})
    replayFileName: string;

    @Column("tinyint", {unsigned: true})
    roomMode: number;

    @Column("tinyint", {unsigned: true})
    duelCount: number;

    @OneToMany(() => DuelLogPlayer, player => player.duelLog)
    players: DuelLogPlayer[];

    getViewString() {
        const viewPlayers = _.clone(this.players);
        viewPlayers.sort((p1, p2) => p1.pos - p2.pos);
        const playerString = viewPlayers[0].realName.split("$")[0] + (viewPlayers[2] ? "+" + viewPlayers[2].realName.split("$")[0] : "") + " VS " + (viewPlayers[1] ? viewPlayers[1].realName.split("$")[0] : "AI") + (viewPlayers[3] ? "+" + viewPlayers[3].realName.split("$")[0] : "");
        return `<${this.id}> ${playerString} ${moment(this.time).format("YYYY-MM-DD HH-mm-ss")}`;
    }

    getViewJSON(tournamentModeSettings: any) {
        const data = {
            id: this.id,
            time: moment(this.time).format("YYYY-MM-DD HH:mm:ss"),
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
                }
            })
        }
        return data;
    }
}