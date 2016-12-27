import net = require("net");
import {JOIN_GAME, PLAYER_INFO, ERROR_MSG, ERRMSG, COLORS, CTOS, STOC} from "./types";
import {Protocol} from "./protocol";
import {Room} from "./room";
import {RoomList} from "./roomlist";
import i18n = require("i18n");
import child_process = require("child_process");
import https = require("https");
import fs = require("fs");

const config = require('./config.json');

i18n.configure({
    locales: ['zh-CN', 'en'],
    directory: 'locales'
});

const server = net.createServer((client) => {
    let ctos = new Protocol(CTOS);
    let stoc = new Protocol(STOC);
    client.pipe(ctos);
    stoc.pipe(client);

    // 每个连入用户一份，生存周期为会话的变量声明在这里
    let username, pass;
    ctos.follow(PLAYER_INFO, async(data: PLAYER_INFO) => {
        username = Protocol.readUnicodeString(data.name);
    });

    ctos.follow(JOIN_GAME, async(data: JOIN_GAME) => {
        if (data.version != config.version) {
            stoc.send_chat(i18n.__('invalid_version'), COLORS.RED);
            stoc.send(new ERROR_MSG({msg: ERRMSG.VERERROR, code: config.version}));
            return client.end();
        }
        pass = Protocol.readUnicodeString(data.pass);

        try {
            let server = await Room.join(client, username, pass);
            ctos.pipe(server);
            server.pipe(stoc);
        } catch (error) {
            console.error(error);
            return stoc.send_die(error.message || error.toString());
        }
    });
});

server.listen(config.port);

if (config.modules.windbot) {
    let windbot = child_process.spawn('mono', ['WindBot.exe', config.modules.windbot.port], {
        cwd: 'windbot',
        stdio: 'inherit'
    });
    // config.modules.windbots = require(config.modules.windbot.botlist).windbots
    process.on('exit', (code) => {
        windbot.kill()
    });
}
if (config.modules.http) {
    const http_server = https.createServer({
        key: fs.readFileSync(config.modules.http.ssl.key),
        cert: fs.readFileSync(config.modules.http.ssl.cert),
    });
    http_server.listen(config.modules.http.port);
    if (config.websocket_roomlist) {
        RoomList.init(http_server);
    }
}
process.on('unhandledRejection', (reason, p) => {
    console.error('Unhandled Rejection at: Promise', p, 'reason:', reason);
    // application specific logging, throwing an error, or other logic here
});

process.on('exit', (code) => {
    for (let room of Room.all) {
        room.child.kill()
    }
});