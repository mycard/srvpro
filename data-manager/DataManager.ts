import moment from "moment";
import { Moment } from "moment";
import bunyan from "bunyan";
import { Connection, ConnectionOptions, createConnection, Transaction } from "typeorm";
import { CloudReplay} from "./entities/CloudReplay";
import { CloudReplayPlayer } from "./entities/CloudReplayPlayer";


export interface CloudReplayPlayerInfo {
	name: string;
	key: string;
	pos: number
}

export class DataManager {
	config: ConnectionOptions;
	ready: boolean;
	db: Connection;
	log: bunyan;
	constructor(config: ConnectionOptions, log: bunyan) {
		this.config = config;
		this.ready = false;
		this.log = log;
	}
	async init() {
		this.db = await createConnection({
			type: "mysql",
			synchronize: true,
			entities: ["./data-manager/entities/*.js"],
			...this.config
		});
		this.ready = true;
	}
	async getCloudReplaysFromKey(key: string) {
		try {
			const replays = await this.db.createQueryBuilder(CloudReplay, "replay")
			.where("exists (select id from cloud_replay_player where cloud_replay_player.cloudReplayId = replay.id and cloud_replay_player.key = :key)", { key })
			.orderBy("replay.date", "DESC")
			.limit(10)
			.leftJoinAndSelect("replay.players", "player")
			.getMany();
			return replays;
		} catch (e) {
			this.log.warn(`Failed to load replay of ${key}: ${e.toString()}`);
			return [];
		}
		
	}

	async getCloudReplayFromId(id: number) {
		try {
			return await this.db.getRepository(CloudReplay).findOne(id, {relations: ["players"]});
		} catch (e) {
			this.log.warn(`Failed to load replay R#${id}: ${e.toString()}`);
			return null;
		}
	}

	async getRandomCloudReplay() {
		try {
			return await this.db.createQueryBuilder(CloudReplay, "replay")
				.orderBy("rand()")
				.limit(4) //there may be 4 players
				.leftJoinAndSelect("replay.players", "player")
				.getOne();
		} catch (e) {
			this.log.warn(`Failed to load random replay: ${e.toString()}`);
			return null;
		}
	}

	async saveCloudReplay(id: number, buffer: Buffer, playerInfos: CloudReplayPlayerInfo[]) {
		const replay = new CloudReplay();
		replay.id = id;
		replay.fromBuffer(buffer);
		replay.date = moment().toDate();
		const players = playerInfos.map(p => {
			const player = CloudReplayPlayer.fromPlayerInfo(p);
			return player;
		});
		await this.db.transaction(async (mdb) => {
			try {
				const nreplay = await mdb.save(replay);
				for (let player of players) {
					player.cloudReplay = nreplay;
				}
				await mdb.save(players);
			} catch (e) {
				this.log.warn(`Failed to save replay R#${replay.id}: ${e.toString()}`);
			}
		});
	}

}
