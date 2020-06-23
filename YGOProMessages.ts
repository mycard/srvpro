import { Struct } from "./struct";
import _ from "underscore";
import structs_declaration from "./data/structs.json";
import typedefs from "./data/typedefs.json";
import proto_structs from "./data/proto_structs.json";
import constants from "./data/constants.json";
import net from "net";


class Handler {
	handler: (buffer: Buffer, info: any, datas: Buffer[], params: any) => Promise<boolean>;
	synchronous: boolean;
	constructor(handler: (buffer: Buffer, info: any, datas: Buffer[], params: any) => Promise<boolean>, synchronous: boolean) {
		this.handler = handler;
		this.synchronous = synchronous || false;
	}
	async handle(buffer: Buffer, info: any, datas: Buffer[], params: any) {
		if (this.synchronous) {
			return !!(await this.handler(buffer, info, datas, params));
		} else {
			const newBuffer = Buffer.from(buffer);
			const newDatas = datas.map(b => Buffer.from(b));
			this.handler(newBuffer, info, newDatas, params);
			return false;
		}
	}
}

interface HandlerList {
	STOC: Map<number, Handler[]>[];
	CTOS: Map<number, Handler[]>[];
}

interface DirectionAndProto {
	direction: string;
	proto: string;
}

export interface Feedback{
	type: string;
	message: string;
}

export interface HandleResult {
	datas: Buffer[];
	feedback: Feedback;
}

export class YGOProMessagesHelper {

	handlers: HandlerList;
	structs: Map<string, Struct>;
	structs_declaration: any;
	typedefs: any;
	proto_structs: any;
	constants: any;
	singleHandleLimit: number;

	constructor(singleHandleLimit?: number) {
		this.handlers = {
			STOC: [new Map(),
			new Map(),
			new Map(),
			new Map(),
			new Map(),
			],
			CTOS: [new Map(),
			new Map(),
			new Map(),
			new Map(),
			new Map(),
			]
		}
		this.initDatas();
		this.initStructs();
		if (singleHandleLimit) {
			this.singleHandleLimit = singleHandleLimit;
		} else {
			this.singleHandleLimit = 1000;
		}
	}

	initDatas() {
		this.structs_declaration = structs_declaration;
		this.typedefs = typedefs;
		this.proto_structs = proto_structs;
		this.constants = constants;
	}

	initStructs() {
		this.structs = new Map();
		for (let name in this.structs_declaration) {
			const declaration = this.structs_declaration[name];
			let result = Struct();
			for (let field of declaration) {
				if (field.encoding) {
					switch (field.encoding) {
						case "UTF-16LE":
							result.chars(field.name, field.length * 2, field.encoding);
							break;
						default:
							throw `unsupported encoding: ${field.encoding}`;
					}
				} else {
					let type = field.type;
					if (this.typedefs[type]) {
						type = this.typedefs[type];
					}
					if (field.length) {
						result.array(field.name, field.length, type); //不支持结构体
					} else {
						if (this.structs.has(type)) {
							result.struct(field.name, this.structs.get(type));
						} else {
							result[type](field.name);
						}
					}
				}
			}
			this.structs.set(name, result);
		}
	}

	getDirectionAndProto(protoStr: string): DirectionAndProto {
		const protoStrMatch = protoStr.match(/^(STOC|CTOS)_([_A-Z]+)$/);
		if (!protoStrMatch) {
			throw `Invalid proto string: ${protoStr}`
		}
		return {
			direction: protoStrMatch[1].toUpperCase(),
			proto: protoStrMatch[2].toUpperCase()
		}
	}


	translateProto(proto: string | number, direction: string): number {
		const directionProtoList = this.constants[direction];
		if (typeof proto !== "string") {
			return proto;
		}
		const translatedProto = _.find(Object.keys(directionProtoList), p => {
			return directionProtoList[p] === proto;
		});
		if (!translatedProto) {
			throw `unknown proto ${direction} ${proto}`;
		}
		return parseInt(translatedProto);
	}

	prepareMessage(protostr: string, info?: string | Buffer | any): Buffer {
		const {
			direction,
			proto
		} = this.getDirectionAndProto(protostr);
		let buffer: Buffer;
		//console.log(proto, this.proto_structs[direction][proto]);
		//const directionProtoList = this.constants[direction];
		if (typeof info === 'undefined') {
			buffer = null;
		} else if (Buffer.isBuffer(info)) {
			buffer = info;
		} else {
			let struct = this.structs.get(this.proto_structs[direction][proto]);
			struct.allocate();
			struct.set(info);
			buffer = struct.buffer();
		}
		const translatedProto = this.translateProto(proto, direction);
		let sendBuffer = Buffer.allocUnsafe(3 + (buffer ? buffer.length : 0));
		if (buffer) {
			sendBuffer.writeUInt16LE(buffer.length + 1, 0);
			sendBuffer.writeUInt8(translatedProto, 2);
			buffer.copy(sendBuffer, 3);
		} else {
			sendBuffer.writeUInt16LE(1, 0);
			sendBuffer.writeUInt8(translatedProto, 2);
		}
		return sendBuffer;
	}

	sendMessage(socket: net.Socket, protostr: string, info?: string | Buffer | any) {
		const sendBuffer = this.prepareMessage(protostr, info);
		socket.write(sendBuffer);
	}

	sendMessageAsync(socket: net.Socket, protostr: string, info?: string | Buffer | any): Promise<Error> {
		const sendBuffer = this.prepareMessage(protostr, info);
		return new Promise(done => {
			socket.write(sendBuffer, done);
		});
	}

	addHandler(protostr: string, handler: (buffer: Buffer, info: any, datas: Buffer[], params: any) => Promise<boolean>, synchronous: boolean, priority: number) {
		if (priority < 0 || priority > 4) {
			throw "Invalid priority: " + priority;
		}
		let {
			direction,
			proto
		} = this.getDirectionAndProto(protostr);
		synchronous = synchronous || false;
		const handlerObj = new Handler(handler, synchronous);
		let handlerCollection: Map<number, Handler[]> = this.handlers[direction][priority];
		const translatedProto = this.translateProto(proto, direction);
		if (!handlerCollection.has(translatedProto)) {
			handlerCollection.set(translatedProto, []);
		}
		handlerCollection.get(translatedProto).push(handlerObj);
	}

	async handleBuffer(messageBuffer: Buffer, direction: string, protoFilter?: string[], params?: any): Promise<HandleResult> {
		let feedback: Feedback = null;
		let messageLength = 0;
		let bufferProto = 0;
		let datas: Buffer[] = [];
		for (let l = 0; l < this.singleHandleLimit; ++l) {
			if (messageLength === 0) {
				if (messageBuffer.length >= 2) {
					messageLength = messageBuffer.readUInt16LE(0);
				} else {
					if (messageBuffer.length !== 0) {
						feedback = {
							type: "BUFFER_LENGTH",
							message: `Bad ${direction} buffer length`
						};
					}
					break;
				}
			} else if (bufferProto === 0) {
				if (messageBuffer.length >= 3) {
					bufferProto = messageBuffer.readUInt8(2);
				} else {
					feedback = {
						type: "PROTO_LENGTH",
						message: `Bad ${direction} proto length`
					};
					break;
				}
			} else {
				if (messageBuffer.length >= 2 + messageLength) {
					const proto = this.constants[direction][bufferProto];
					let cancel = proto && protoFilter && _.indexOf(protoFilter, proto) === -1;
					let buffer = messageBuffer.slice(3, 2 + messageLength);
					//console.log(l, direction, proto, cancel);
					for (let priority = 0; priority < 4; ++priority) {
						if (cancel) {
							break;
						}
						const handlerCollection: Map<number, Handler[]> = this.handlers[direction][priority];
						if (proto && handlerCollection.has(bufferProto)) {
							let struct = this.structs.get(this.proto_structs[direction][proto]);
							let info = null;
							if (struct) {
								struct._setBuff(buffer);
								info = _.clone(struct.fields);
							}
							for (let handler of handlerCollection.get(bufferProto)) {
								cancel = await handler.handle(buffer, info, datas, params);
								if (cancel) {
									break;
								}
							}
						}
					}
					if (!cancel) {
						datas.push(messageBuffer.slice(0, 2 + messageLength));
					}
					messageBuffer = messageBuffer.slice(2 + messageLength);
					messageLength = 0;
					bufferProto = 0;
				} else {
					if (direction === "STOC" || messageLength !== 17735) {
						feedback = {
							type: "MESSAGE_LENGTH",
							message: `Bad ${direction} message length`
						};
					}
					break;
				}
			}
			if (l === this.singleHandleLimit - 1) {
				feedback = {
					type: "OVERSIZE",
					message: `Oversized ${direction}`
				};
			}
		}
		return {
			datas,
			feedback
		};
	}

}
