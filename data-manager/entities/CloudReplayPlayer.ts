import {Column, Entity, Index, ManyToOne} from "typeorm";
import {CloudReplayPlayerInfo} from "../DataManager";
import {CloudReplay} from "./CloudReplay";
import {BasePlayer} from "./BasePlayer";

@Entity()
export class CloudReplayPlayer extends BasePlayer {
	@Index()
	@Column({ type: "varchar", length: 40 })
	key: string;

	@ManyToOne(() => CloudReplay, replay => replay.players)
	cloudReplay: CloudReplay;

	static fromPlayerInfo(info: CloudReplayPlayerInfo) {
		const p = new CloudReplayPlayer();
		p.key = info.key;
		p.name = info.name;
		p.pos = info.pos;
		return p;
	}
}
