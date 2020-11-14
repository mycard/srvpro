import { Column, Entity, Index, ManyToOne, PrimaryGeneratedColumn } from "typeorm";
import { CloudReplayPlayerInfo } from "../DataManager";
import { CloudReplay } from "./CloudReplay";

@Entity()
export class CloudReplayPlayer {
	@PrimaryGeneratedColumn({unsigned: true, type: "bigint"})
	id: number;

	@Index()
	@Column({ type: "varchar", length: 40 })
	key: string;

	@Column({ type: "varchar", length: 20 })
	name: string;

	@Column({ type: "tinyint" })
	pos: number;

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
