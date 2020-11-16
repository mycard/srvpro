import {Column, Entity, Index, OneToMany, PrimaryColumn} from "typeorm";
import {CloudReplayPlayer} from "./CloudReplayPlayer";
import _ from "underscore";
import moment from "moment";
import {CreateAndUpdateTimeBase} from "./CreateAndUpdateTimeBase";

@Entity({
	orderBy: {
		date: "DESC"
	}
})
export class CloudReplay extends CreateAndUpdateTimeBase {
	@PrimaryColumn({ unsigned: true, type: "bigint" })
	id: number;

	@Column({ type: "text" })
	data: string;

	fromBuffer(buffer: Buffer) {
		this.data = buffer.toString("base64");
	}

	toBuffer() {
		return Buffer.from(this.data, "base64");
	}

	@Index()
	@Column({ type: "datetime" })
	date: Date;

	getDateString() {
		return moment(this.date).format('YYYY-MM-DD HH:mm:ss')
	}

	@OneToMany(() => CloudReplayPlayer, player => player.cloudReplay)
	players: CloudReplayPlayer[];

	getPlayerNamesString() {
		const playerInfos = _.clone(this.players);
		playerInfos.sort((p1, p2) => p1.pos - p2.pos);
		return playerInfos[0].name + (playerInfos[2] ? "+" + playerInfos[2].name : "") + " VS " + (playerInfos[1] ? playerInfos[1].name : "AI") + (playerInfos[3] ? "+" + playerInfos[3].name : "");
	}
	
	getDisplayString() {
		return `R#${this.id} ${this.getPlayerNamesString()} ${this.getDateString()}`;
	}
}
