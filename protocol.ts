/**
 * Created by zh99998 on 2016/12/24.
 */
import {Transform} from "stream";
import {ERROR_MSG, STOC_CHAT, Struct, Array, COLORS, ERRMSG} from "./types";
import ArrayType = require("ref-array");
import assert = require('assert');
import StructType = require("ref-struct");

export class Protocol extends Transform {
    buffer = Buffer.alloc(0);
    size = 0;
    follows = new Map<StructType, Function[]>();

    types: Map<number, StructType>;
    types_reverse: Map<StructType, number>;

    constructor(types: Map<number, StructType>) {
        super();
        this.types = types;
        this.types_reverse = new Map(Array.from(types).map(([key, value]) => <[StructType, number]>[value, key]));
    }

    follow(proto, callback) {
        let array = this.follows.get(proto);
        if (!array) {
            array = [];
            this.follows.set(proto, array);
        }
        array.push(callback);
    }

    send(data: Struct) {
        let id = this.types_reverse.get(<StructType>data.constructor);
        if (!id) {
            throw 'send unknown proto'
        }
        let buffer = data['ref.buffer'];
        let length_buffer = Buffer.alloc(2);
        length_buffer.writeUInt16LE(buffer.length + 1, 0);
        let id_buffer = Buffer.from([id]);
        this.push(length_buffer);
        this.push(id_buffer);
        this.push(buffer);
    }

    send_chat(msg: string, player: number = COLORS.LIGHTBLUE) {
        for (let line of msg.split("\n")) {
            if (player >= 10) {
                line = "[System]: " + line
            }
            let type = <ArrayType<number>>STOC_CHAT.fields['msg'].type;
            let buffer = Buffer.alloc(type.size);
            Buffer.from(msg, 'utf16le').copy(buffer);
            let data = new STOC_CHAT({player: player, msg: new type(buffer)});
            this.send(data);
        }
    }

    send_die(msg: string) {
        this.send_chat(msg, COLORS.RED);
        this.send(new ERROR_MSG({msg: ERRMSG.JOINERROR, code: 2}));
        this.end()
    }

    async _transform(chunk, encoding, callback) {
        // 这个方法会在收到数据的时候被调用，类似于on data
        // 收到数据后，先跟之前未处理的数据拼成一整个buffer，然后取当前需要的数据长度，先固定收包头长度2，然后再收包头指示的长度

        assert(encoding == 'buffer');

        this.buffer = Buffer.concat([this.buffer, chunk]);

        while (this.buffer.length >= (this.size || 2)) {
            if (this.size == 0) {
                // 收到包头，取前2位作为size，其余扔回this.buffer
                this.size = this.buffer.readUInt16LE(0);
                this.buffer = this.buffer.slice(2);
            } else {
                // 收到内容，取前size长度作为data，其余扔回this.buffer
                let data = this.buffer.slice(0, this.size);
                this.buffer = this.buffer.slice(this.size);

                // 内容第1位是类型
                let type_id = data.readUInt8(0);

                let type: StructType = this.types.get(type_id);
                if (type) {
                    // 找到了，解析丫
                    let follows = this.follows.get(type);
                    if (follows) {
                        let message = new type(data.slice(1));
                        for (let follow of follows) {
                            await follow(message)
                        }
                    }
                } else {
                    // 不认识这个消息
                    console.warn(`unknown protocol ${type_id}`)
                }

                // 处理完毕，构造出长度那个包头一起发送。
                // 这里要处理完整条消息再一起发，而不要处理完包头就直接发包头，这样可以保证任何时候执行send，对端收到的消息总是完好的，不会在包中间被插入。
                let length_buffer = Buffer.alloc(2);
                length_buffer.writeUInt16LE(this.size, 0);
                this.push(length_buffer); // this.push 是 ReadableStream 的方法，把数据放进去。
                this.push(data);
                this.size = 0;
            }
        }

        // transform 的 callback，用来表示已经处理完了
        callback();
    }

    // 这个Array<numer> 是指Ref里的Array，不是js的Array。
    static readUnicodeString(array: Array<number>) {
        let arr = Uint16Array.from(array);
        let index = arr.indexOf(0);
        if (index != -1) {
            arr = arr.slice(0, index);
        }
        return Buffer.from(arr.buffer).toString('utf16le');
    }
}