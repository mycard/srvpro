import child_process = require("child_process");
import {ChildProcess} from "child_process";
import {Socket} from "net";
import {HostInfo} from "./types";
import {EventEmitter} from "events";
import fetch from "node-fetch";
import net = require("net");
import url = require("url");

const config = require("./config.json");
const windbots: Windbot[] = require(config.modules.windbot.botlist).windbots;

interface Player {
    client: Socket,
    server: Socket,
    username: string,
    pass: string,
    pos: number
}
interface Windbot {
    name: string,
    deck: string,
    dialog: string
}

export class Room {
    started = false;
    players: Player[] = [];

    constructor(public id: string, public title: string, public hostinfo: HostInfo, public _private: Boolean, public child: ChildProcess, public port: number) {
        // private 是关键字，于是换了个名

        Room.emitter.emit('create', this);
        Room.all.push(this);

        new Promise((resolve, reject) => {
            this.child.on('exit', resolve);
        }).then(() => {
            this.destroy();
        });

    }


    static all: Room[] = [];
    static emitter = new EventEmitter();

    static async join(client: Socket, username: string, pass: string): Promise<Socket> {
        let room: Room;

        if (pass.length == 0) {
            // 随机对战?
        }
        if (config.modules.windbot && (pass == 'AI' || pass.startsWith('AI#'))) {
            // AI
            let bots: Windbot[];
            if (pass == 'AI') {
                bots = windbots;
            } else {
                let ai = pass.slice(3);
                bots = windbots.filter((bot) => bot.name == ai || bot.deck == ai);
                if (bots.length == 0) {
                    throw "未找到该AI角色或卡组"
                }
            }
            let bot = bots[Math.floor(Math.random() * bots.length)];
            let hostinfo: HostInfo = Object.assign({}, config.hostinfo, {mode: 0});
            room = await Room.create(pass, "AI", hostinfo, false);

            await fetch(url.format({
                protocol: 'http',
                hostname: '127.0.0.1',
                port: config.modules.windbot.port,
                query: {
                    name: bot.name,
                    deck: bot.deck,
                    dialog: bot.dialog,
                    host: '127.0.0.1',
                    port: room.port,
                    version: config.version,
                    // password=#{encodeURIComponent(@name)}
                    // 为什么要让AI也走 ygopro-server? 直接加进房间端口会有问题么
                }
            }));
        }

        // 直连加房
        if (!room) {
            room = this.all.find((room) => room.id == pass);
        }

        // 直连建房
        if (!room) {
            let hostinfo: HostInfo = Object.assign({}, config.hostinfo);
            if (pass.startsWith('M#')) {
                hostinfo.mode = 1;
            } else if (pass.startsWith('T#')) {
                hostinfo.mode = 2;
            }
            room = await Room.create(pass, pass.slice(2), hostinfo, false);
        }
        return room.connect(client, username, pass);
    }

    static async create(id: string, title: string, hostinfo: HostInfo, _private: boolean): Promise<Room> {

        let param = [
            '0', // port
            hostinfo.lflist.toString(),
            hostinfo.rule.toString(),
            hostinfo.mode.toString(),
            hostinfo.enable_priority ? 'T' : 'F',
            hostinfo.no_check_deck ? 'T' : 'F',
            hostinfo.no_shuffle_deck ? 'T' : 'F',
            hostinfo.start_lp.toString(),
            hostinfo.start_hand.toString(),
            hostinfo.draw_count.toString(),
            hostinfo.time_limit.toString(),
            '0' // replay_mode
        ];


        let child = child_process.spawn('./ygopro', param, {cwd: 'ygopro', stdio: ['ignore', 'pipe', 'ignore']});
        child.stdout.setEncoding('utf8');
        let port = await new Promise<number>((resolve, reject) => {
            child.stdout.on('data', (chunk: string) => {
                let result = parseInt(chunk);
                if (result) {
                    resolve(result);
                } else {
                    reject(chunk);
                }
            });
            child.on('close', reject);
            child.on('error', reject);
            child.on('exit', reject);
            // Promise 只承认第一次状态转移
        });

        return new Room(id, '', hostinfo, false, child, port);

    }

    auth() {

        // mycard_auth

    }

    async connect(client: Socket, username: string, pass: string): Promise<Socket> {
        let server = net.connect(this.port);
        await new Promise((resolve, reject) => {
            server.on('connect', resolve);
            server.on('error', reject);
        });

        this.players.push({
            client: client,
            server: server,
            username: username,
            pass: pass,
            pos: 0
        });
        Room.emitter.emit('update', this);
        return server
    }

    destroy() {
        let index = Room.all.indexOf(this);
        if (index != -1) {
            Room.all.splice(index, 1);
        }
        Room.emitter.emit('destroy', this.id);
    }

    start() {
        this.started = true;
        Room.emitter.emit('start', this.id);
    }
}

//调试用
Room.emitter.on('create', (room) => {
    console.log('room_create', room.id)
});
Room.emitter.on('update', (room) => {
    console.log('room_update', room.id)
});
Room.emitter.on('start', (room) => {
    console.log('room_start', room.id)
});
Room.emitter.on('destroy', (room_id) => {
    console.log('room_destroy', room_id)
});