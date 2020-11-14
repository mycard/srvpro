import moment from "moment";
import { Moment } from "moment";
import bunyan from "bunyan";
import { Connection, ConnectionOptions, createConnection, Transaction } from "typeorm";
import { CloudReplay } from "./entities/CloudReplay";
import { CloudReplayPlayer } from "./entities/CloudReplayPlayer";
import { Ban } from "./entities/Ban";


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
			return await this.db.getRepository(CloudReplay).findOne(id, { relations: ["players"] });
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

	async checkBan(field: string, value: string) {
		const banQuery: any = {};
		banQuery[field] = value;
		try {
			return await this.db.getRepository(Ban).findOne(banQuery);
		} catch (e) {
			this.log.warn(`Failed to load ban ${field} ${value}: ${e.toString()}`);
			return null;
		}
	}

	async checkBanWithNameAndIP(name: string, ip: string) {
		try {
			return await this.db.getRepository(Ban).findOne({ name, ip });
		} catch (e) {
			this.log.warn(`Failed to load ban ${name} ${ip}: ${e.toString()}`);
			return null;
		}
	}

	getBan(name: string, ip: string) {
		const ban = new Ban();
		ban.ip = ip;
		ban.name = name;
		return ban;
	}

	async banPlayer(ban: Ban) {
		try {
			const repo = this.db.getRepository(Ban);
			if (await repo.findOne({
				ip: ban.ip,
				name: ban.name
			})) {
				return;
			}
			return await repo.save(ban);
		} catch (e) {
			this.log.warn(`Failed to update ban ${JSON.stringify(ban)}: ${e.toString()}`);
			return null;
		}
	}
}
