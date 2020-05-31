"use strict";
const Struct = require('./struct.js').Struct;
const fs = require("fs");
const _ = require("underscore");

function loadJSON(path) {
	return JSON.parse(fs.readFileSync(path, "utf8"));
}

class Handler {
	constructor(handler, synchronous) {
		this.handler = handler;
		this.synchronous = synchronous || false;
	}
	async handle(buffer, info, datas, params) {
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

class YGOProMessagesHelper {

	constructor() {
		this.handlers = {
			STOC: [{},
				{},
				{},
				{},
				{},
			],
			CTOS: [{},
				{},
				{},
				{},
				{},
			]
		}
		this.initDatas();
		this.initStructs();
	}

	initDatas() {
		this.structs_declaration = loadJSON('./data/structs.json');
		this.typedefs =  loadJSON('./data/typedefs.json');
		this.proto_structs = loadJSON('./data/proto_structs.json');
		this.constants = loadJSON('./data/constants.json');
	}

	initStructs() {
		this.structs = {};
		for (let name in this.structs_declaration ) {
			const declaration = this.structs_declaration [name];
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
						if (this.structs[type]) {
							result.struct(field.name, this.structs[type]);
						} else {
							result[type](field.name);
						}
					}
				}
			}
			this.structs[name] = result;
		}
	}

	getDirectionAndProto(protoStr) {
		const protoStrMatch = protoStr.match(/^(STOC|CTOS)_([_A-Z]+)$/);
		if (!protoStrMatch) {
			throw `Invalid proto string: ${protoStr}`
		}
		return {
			direction: protoStrMatch[1].toUpperCase(),
			proto: protoStrMatch[2].toUpperCase()
		}
	}


	translateProto(proto, direction) {
		const directionProtoList = this.constants[direction];
		if (typeof proto !== "string") {
			return proto;
		}
		let translatedProto = _.find(Object.keys(directionProtoList), p => {
			return directionProtoList[p] === proto;
		});
		if (!translatedProto) {
			throw `unknown proto ${direction} ${proto}`;
		}
		return translatedProto;
	}

	sendMessage(socket, protostr, info) {
		const {
			direction,
			proto
		} = this.getDirectionAndProto(protostr);
		let buffer;
		if (socket.closed) {
			return;
		}
		//console.log(proto, this.proto_structs[direction][proto]);
		//const directionProtoList = this.constants[direction];
		if (typeof info === 'undefined') {
			buffer = "";
		} else if (Buffer.isBuffer(info)) {
			buffer = info;
		} else {
			let struct = this.structs[this.proto_structs[direction][proto]];
			struct.allocate();
			struct.set(info);
			buffer = struct.buffer();
		}
		const translatedProto = this.translateProto(proto, direction);
		let header = Buffer.allocUnsafe(3);
		header.writeUInt16LE(buffer.length + 1, 0);
		header.writeUInt8(translatedProto, 2);
		socket.write(header);
		if (buffer.length) {
			socket.write(buffer);
		}
	}

	addHandler(protostr, handler, synchronous, priority) {
		if (priority < 0 || priority > 4) {
			throw "Invalid priority: " + priority;
		}
		let {
			direction,
			proto
		} = this.getDirectionAndProto(protostr);
		synchronous = synchronous || false;
		priority = priority || 1;
		const handlerObj = new Handler(handler, synchronous);
		let handlerCollection = this.handlers[direction][priority];
		const translatedProto = this.translateProto(proto, direction);
		if (!handlerCollection[translatedProto]) {
			handlerCollection[translatedProto] = [];
		}
		handlerCollection[translatedProto].push(handlerObj);
	}

	async handleBuffer(messageBuffer, direction, protoFilter, params) {
		let feedback = null;
		let messageLength = 0;
		let bufferProto = 0;
		let datas = [];
		for (let l = 0; l < 1000; ++l) {
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
						const handlerCollection = this.handlers[direction][priority];
						if (proto && handlerCollection[bufferProto]) {
							let struct = this.structs[this.proto_structs[direction][proto]];
							let info = null;
							if (struct) {
								struct._setBuff(buffer);
								info = _.clone(struct.fields);
							}
							for (let handler of handlerCollection[bufferProto]) {
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
			if (l === 999) {
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

module.exports = YGOProMessagesHelper;
