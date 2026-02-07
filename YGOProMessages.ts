import _ from "underscore";
import loadConstants from "./load-constants";
import net from "net";
import { YGOProCtos, YGOProCtosBase, YGOProStoc, YGOProStocBase } from "ygopro-msg-encode";
import { applyYGOProMsgStructCompat, fromPartialCompat } from "./ygopro-msg-struct-compat";
import legacyProtoStructs from "./data/proto_structs.json";
import { overwriteBuffer } from "./utility";


class Handler {
	constructor(
		private handler: (buffer: Buffer, info: YGOProStocBase | YGOProCtosBase, datas: Buffer[], params: any) => Promise<boolean | string | Buffer>,
		public synchronous: boolean
	) {}
	async handle(buffer: Buffer, info: YGOProStocBase | YGOProCtosBase, datas: Buffer[], params: any): Promise<boolean | string | Buffer> {
		if (this.synchronous) {
			return await this.handler(buffer, info, datas, params);
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

interface DirectionBase {
	STOC: typeof YGOProStocBase;
	CTOS: typeof YGOProCtosBase;
}

type DirectionToBase<T>
	= T extends `${infer K extends keyof DirectionBase}_${string}` ? DirectionBase[K] : DirectionBase[keyof DirectionBase];


interface DirectionAndProto {
	direction: keyof HandlerList;
	proto: string;
}

export interface Feedback {
	type: string;
	message: string;
}

export interface HandleResult {
	datas: Buffer[];
	feedback: Feedback;
}

export interface Constants {
	TYPES: Record<string, number>;
	RACES: Record<string, number>;
	ATTRIBUTES: Record<string, number>;
	LINK_MARKERS: Record<string, number>;
	DUEL_STAGE: Record<string, number>;
	COLORS: Record<string, number>;
	TIMING: Record<string, string>;
	NETWORK: Record<string, string>;
	NETPLAYER: Record<string, string>;
	CTOS: Record<string, string>;
	STOC: Record<string, string>;
	PLAYERCHANGE: Record<string, string>;
	ERRMSG: Record<string, string>;
	MODE: Record<string, string>;
	MSG: Record<string, string>;
}

export class LegacyStructInst {
	buffer: Buffer;
	constructor(private cls?: typeof YGOProCtosBase | typeof YGOProStocBase) {}

	_setBuff(buff: Buffer) { 
		this.buffer = buff;
	}

	set(field: string, value: any) { 
		if (!this.buffer || !this.cls) return;
		const inst = applyYGOProMsgStructCompat(new this.cls().fromPayload(this.buffer));
		inst[field] = value;
		overwriteBuffer(this.buffer, inst.toPayload());
	}
}

export class LegacyStruct {
	private protoClasses = new Map<string, typeof YGOProCtosBase | typeof YGOProStocBase>();
	constructor(private helper: YGOProMessagesHelper) { 
		for (const [direction, list] of Object.entries(legacyProtoStructs)) { 
			for (const [protoStr, structName] of Object.entries(list)) { 
				if(!structName) continue;
				this.protoClasses.set(structName, this.helper.getProtoClass(protoStr, direction as keyof HandlerList));
			}
		}
	}

	get(structName: string) {
		return new LegacyStructInst(this.protoClasses.get(structName));
	}
}

export class YGOProMessagesHelper {

	handlers: HandlerList = {
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
		};
	constants = loadConstants();

	constructor(public singleHandleLimit = 1000) {}

	structs = new LegacyStruct(this);

	getDirectionAndProto(protoStr: string): DirectionAndProto {
		const protoStrMatch = protoStr.match(/^(STOC|CTOS)_([_A-Z]+)$/);
		if (!protoStrMatch) {
			throw `Invalid proto string: ${protoStr}`
		}
		return {
			direction: protoStrMatch[1].toUpperCase() as keyof HandlerList,
			proto: protoStrMatch[2].toUpperCase()
		}
	}

	translateProto(proto: string | number, direction: keyof HandlerList): number {
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

	getProtoClass<T extends string | number>(proto: T, direction: keyof HandlerList): DirectionToBase<T> {
		const identifier = typeof proto === 'number' ? proto : this.translateProto(proto, direction);
		const registry = direction === 'CTOS' ? YGOProCtos : direction === 'STOC' ? YGOProStoc : null;
		if (!registry) {
			throw `Invalid direction: ${direction}`;
		}
		return registry.get(identifier) as DirectionToBase<T>;
	}

	classToProtoStr(cls: typeof YGOProCtosBase | typeof YGOProStocBase): string { 
		const registry = cls.prototype instanceof YGOProCtosBase ? YGOProCtos : cls.prototype instanceof YGOProStocBase ? YGOProStoc : null;
		if (!registry) { 
			throw `Invalid class: ${cls.name}`;
		}
		const identifier = cls.identifier;
		const direction = cls.prototype instanceof YGOProCtosBase ? 'CTOS' : 'STOC';
		return `${direction}_${this.constants[direction][identifier]}`;
	}

	prepareMessage(protostr: string, info?: string | Buffer | any): Buffer {
		const {
			direction,
			proto
		} = this.getDirectionAndProto(protostr);
		const translatedProto = this.translateProto(proto, direction);
		let buffer: Buffer;
		if (typeof info === 'undefined') {
			buffer = null;
		} else if (Buffer.isBuffer(info)) {
			buffer = info;
		} else {
			const protoCls = this.getProtoClass(translatedProto, direction);
			if (!protoCls) { 
				throw `No proto class for ${protostr}`;
			}
			buffer = Buffer.from(fromPartialCompat(protoCls, info).toPayload());
		}
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

	send(socket: net.Socket | WebSocket, buffer: Buffer) {
		return new Promise<Error | undefined>(done => {
			if (socket['isWs']) {
				const ws = socket as WebSocket;
				// @ts-ignore
				ws.send(buffer, {}, done);
			} else {
				const sock = socket as net.Socket;
				sock.write(buffer, done);
			}
		})
	}

	sendMessage(socket: net.Socket | WebSocket, protostr: string, info?: string | Buffer | any): Promise<Error> {
		const sendBuffer = this.prepareMessage(protostr, info);
		return this.send(socket, sendBuffer);
	}

	addHandler<T extends string>(protostr: T, handler: (buffer: Buffer, info: InstanceType<DirectionToBase<T>>, datas: Buffer[], params: any) => Promise<boolean | string>, synchronous: boolean, priority: number) {
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

	async handleBuffer(messageBuffer: Buffer, direction: keyof HandlerList, protoFilter?: string[], params?: any, preconnect = false): Promise<HandleResult> {
		let feedback: Feedback = null;
		let messageLength = 0;
		let bufferProto = 0;
		let datas: Buffer[] = [];
		const limit = preconnect ? protoFilter.length * 3 : this.singleHandleLimit;
		for (let l = 0; l < limit; ++l) {
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
					let cancel: string | boolean | Buffer = proto && protoFilter && !protoFilter.includes(proto);
					if (cancel && preconnect) {
						feedback = {
							type: "INVALID_PACKET",
							message: `${direction} proto not allowed`
						};
						break;
					}
					let buffer = messageBuffer.slice(3, 2 + messageLength);
					let bufferMutated = false;
					//console.log(l, direction, proto, cancel);
					for (let priority = 0; priority < 4; ++priority) {
						if (cancel) {
							break;
						}
						const handlerCollection: Map<number, Handler[]> = this.handlers[direction][priority];
						if (proto && handlerCollection.has(bufferProto)) {
							for (const handler of handlerCollection.get(bufferProto)) {
								const protoCls = this.getProtoClass(bufferProto, direction);
								const info = protoCls
									? applyYGOProMsgStructCompat(new protoCls().fromPayload(buffer))
									: null;
								cancel = await handler.handle(buffer, info, datas, params);
								if (cancel) {
									if (Buffer.isBuffer(cancel)) {
										buffer = cancel as any;
										bufferMutated = true;
										cancel = false;
									} else if (typeof cancel === "string") { 
										if (cancel === '_cancel') {
											return {
												datas: [],
												feedback
											}
										} else if (cancel.startsWith('_shrink_')) {
											const targetShrinkCount = parseInt(cancel.slice(8));
											if (targetShrinkCount > buffer.length) {
												cancel = true;
											} else {
												buffer = buffer.slice(0, buffer.length - targetShrinkCount);
												bufferMutated = true;
												cancel = false;
											}
										}
									}
									break;
								}
							}
						}
					}
					if (!cancel) {
						if (bufferMutated) {
							const newLength = buffer.length + 1;
							messageBuffer.writeUInt16LE(newLength, 0);
							datas.push(Buffer.concat([messageBuffer.slice(0, 3), buffer]));
						} else {
							datas.push(messageBuffer.slice(0, 2 + messageLength));
						}
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
			if (l === limit - 1) {
				feedback = {
					type: "OVERSIZE",
					message: `Oversized ${direction} ${limit}`
				};
			}
		}
		return {
			datas,
			feedback
		};
	}

}
