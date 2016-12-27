/**
 * Created by zh99998 on 2016/12/27.
 */
import {Room} from "./room";
import {Server} from "ws";
import WebSocket = require("ws");
const config = require('./config.json');

export class RoomList {
    static init(http_server) {
        // const http_server = https.createServer({
        //     key: config.http.ssl.key,
        //     cert: config.http.ssl.cert,
        // });
        const websocket_server = new Server({server: http_server});
        websocket_server.on("connection", (client: WebSocket) => {
            client.send(JSON.stringify({
                event: 'init',
                data: Room.all.filter((room) => !room._private && !room.started).map(this.room_data)
            }))
        });
        websocket_server.on('error', (error) => {
            console.error(error);
        });
        Room.emitter.on('create', (room) => {
            this.broadcast(websocket_server, 'create', this.room_data(room))
        });
        Room.emitter.on('update', (room) => {
            this.broadcast(websocket_server, 'update', this.room_data(room))
        });
        Room.emitter.on('start', (room) => {
            this.broadcast(websocket_server, 'delete', room.id)
        });

    }

    static broadcast(websocket_server, event, data) {
        let message = JSON.stringify({
            event: event,
            data: data
        });

        for (let client of websocket_server.clients) {
            // 不需要 try，如果失败，会在 websocket_server 上触发 error 事件。
            client.send(message);
        }
    }

    static room_data(room: Room) {
        let result = {
            id: room.id,
            title: room.title,
            users: room.players.map((player) => {
                return {username: player.username, position: player.pos}
            }),
            options: room.hostinfo
        }
    }
}
