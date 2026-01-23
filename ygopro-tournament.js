"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/*
 ygopro-tournament.ts
 ygopro tournament util
 Author: mercury233
 License: MIT

 不带参数运行时，会建立一个服务器，调用API执行对应操作
*/
const http = __importStar(require("http"));
const https = __importStar(require("https"));
const fs = __importStar(require("fs"));
const url = __importStar(require("url"));
const axios_1 = __importDefault(require("axios"));
const formidable = __importStar(require("formidable"));
const load_json_file_1 = require("load-json-file");
const challonge_1 = require("./challonge");
const asyncLib = __importStar(require("async"));
const ygopro_deck_encode_1 = __importDefault(require("ygopro-deck-encode"));
const auth = __importStar(require("./ygopro-auth"));
const underscore_1 = __importDefault(require("underscore"));
const settings = (0, load_json_file_1.sync)("./config/config.json");
const config = settings.modules.tournament_mode;
const challonge_config = settings.modules.challonge;
const challonge = new challonge_1.Challonge(challonge_config);
const ssl_config = settings.modules.http.ssl;
//http长连接
let responder;
let wallpapers = [{ url: "", desc: "" }];
axios_1.default
    .get("http://www.bing.com/HPImageArchive.aspx", {
    params: {
        format: "js",
        idx: 0,
        n: 8,
        mkt: "zh-CN",
    },
})
    .then((response) => {
    const body = response.data;
    if (typeof body !== "object" || !body.images) {
        console.log("wallpapers bad json", body);
    }
    else if (!body) {
        console.log("wallpapers error", null, response);
    }
    else {
        wallpapers = [];
        for (const i in body.images) {
            const wallpaper = body.images[i];
            const img = {
                url: "http://s.cn.bing.net" + wallpaper.urlbase + "_768x1366.jpg",
                desc: wallpaper.copyright,
            };
            wallpapers.push(img);
        }
    }
})
    .catch((error) => {
    console.log("wallpapers error", error, error?.response);
});
//输出反馈信息，如有http长连接则输出到http，否则输出到控制台
const sendResponse = function (text) {
    text = "" + text;
    if (responder) {
        text = text.replace(/\n/g, "<br>");
        responder.write("data: " + text + "\n\n");
    }
    else {
        console.log(text);
    }
};
//读取指定卡组
const readDeck = async function (deck_name, deck_full_path) {
    const deck_text = await fs.promises.readFile(deck_full_path, { encoding: "utf-8" });
    const deck = ygopro_deck_encode_1.default.fromYdkString(deck_text);
    deck.name = deck_name;
    return deck;
};
//读取指定文件夹中所有卡组
const getDecks = function (callback) {
    const decks = [];
    asyncLib.auto({
        readDir: (done) => {
            fs.readdir(config.deck_path, done);
        },
        handleDecks: [
            "readDir",
            (results, done) => {
                const decks_list = results.readDir;
                asyncLib.each(decks_list, async (deck_name) => {
                    if (deck_name.endsWith(".ydk")) {
                        const deck = await readDeck(deck_name, config.deck_path + deck_name);
                        decks.push(deck);
                    }
                }, done);
            },
        ],
    }, (err) => {
        callback(err, decks);
    });
};
const delDeck = function (deck_name, callback) {
    if (deck_name.startsWith("../") || deck_name.match(/\/\.\.\//)) {
        //security issue
        callback(new Error("Invalid deck"));
    }
    fs.unlink(config.deck_path + deck_name, callback);
};
const clearDecks = function (callback) {
    asyncLib.auto({
        deckList: (done) => {
            fs.readdir(config.deck_path, done);
        },
        removeAll: [
            "deckList",
            (results, done) => {
                const decks_list = results.deckList;
                asyncLib.each(decks_list, delDeck, done);
            },
        ],
    }, callback);
};
const UploadToChallonge = async function () {
    if (!challonge_config.enabled) {
        sendResponse("未开启Challonge模式。");
        return false;
    }
    sendResponse("开始读取玩家列表。");
    const decks_list = fs.readdirSync(config.deck_path);
    const player_list = [];
    for (const k in decks_list) {
        const deck_name = decks_list[k];
        if (deck_name.endsWith(".ydk")) {
            player_list.push({
                name: deck_name.slice(0, deck_name.length - 4),
                deckbuf: Buffer.from(ygopro_deck_encode_1.default.fromYdkString(await fs.promises.readFile(config.deck_path + deck_name, { encoding: "utf-8" })).toUpdateDeckPayload()).toString("base64"),
            });
        }
    }
    if (!player_list.length) {
        sendResponse("玩家列表为空。");
        return false;
    }
    sendResponse("读取玩家列表完毕，共有" + player_list.length + "名玩家。");
    try {
        sendResponse("开始清空 Challonge 玩家列表。");
        await challonge.clearParticipants();
        sendResponse("开始上传玩家列表至 Challonge。");
        for (const chunk of underscore_1.default.chunk(player_list, 10)) {
            sendResponse(`开始上传玩家 ${chunk.map((c) => c.name).join(", ")} 至 Challonge。`);
            await challonge.uploadParticipants(chunk);
        }
        sendResponse("玩家列表上传完成。");
    }
    catch (e) {
        sendResponse("Challonge 上传失败：" + e.message);
    }
    return true;
};
const receiveDecks = function (files, callback) {
    const result = [];
    asyncLib.eachSeries(files, async (file) => {
        if (file.name.endsWith(".ydk")) {
            const deck = await readDeck(file.name, file.path);
            if (deck.main.length >= 40) {
                fs.createReadStream(file.path).pipe(fs.createWriteStream(config.deck_path + file.name));
                result.push({
                    file: file.name,
                    status: "OK",
                });
            }
            else {
                result.push({
                    file: file.name,
                    status: "卡组不合格",
                });
            }
        }
        else {
            result.push({
                file: file.name,
                status: "不是卡组文件",
            });
        }
    }, (err) => {
        callback(err, result);
    });
};
//建立一个http服务器，接收API操作
async function requestListener(req, res) {
    const u = url.parse(req.url || "", true);
    // Allow all CORS + PNA (Private Network Access) requests.
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Private-Network", "true");
    res.setHeader("Vary", "Origin, Access-Control-Request-Headers, Access-Control-Request-Method");
    if ((req.method || "").toLowerCase() === "options") {
        const requestHeaders = req.headers["access-control-request-headers"];
        res.writeHead(204, {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            "Access-Control-Allow-Headers": Array.isArray(requestHeaders)
                ? requestHeaders.join(", ")
                : requestHeaders || "*",
            "Access-Control-Allow-Private-Network": "true",
            "Access-Control-Max-Age": "86400",
        });
        res.end();
        return;
    }
    /*if (u.query.password !== config.password) {
          res.writeHead(403);
          res.end("Auth Failed.");
          return;
      }*/
    if (u.pathname === "/api/upload_decks" && (req.method || "").toLowerCase() == "post") {
        if (!(await auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "upload_deck"))) {
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        const form = new formidable.IncomingForm();
        form.parse(req, function (err, fields, files) {
            receiveDecks(files, (err, result) => {
                if (err) {
                    console.error(`Upload error: ${err}`);
                    res.writeHead(500, {
                        "Access-Control-Allow-origin": "*",
                        "content-type": "text/plain",
                    });
                    res.end(JSON.stringify({ error: err.toString() }));
                    return;
                }
                res.writeHead(200, {
                    "Access-Control-Allow-origin": "*",
                    "content-type": "text/plain",
                });
                res.end(JSON.stringify(result));
            });
        });
    }
    else if (u.pathname === "/api/msg") {
        if (!(await auth.auth(u.query.username, u.query.password, "deck_dashboard_read", "login_deck_dashboard"))) {
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200, {
            "Access-Control-Allow-origin": "*",
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            Connection: "keep-alive",
        });
        res.on("close", function () {
            responder = null;
        });
        responder = res;
        sendResponse("已连接。");
    }
    else if (u.pathname === "/api/get_bg") {
        if (!(await auth.auth(u.query.username, u.query.password, "deck_dashboard_read", "login_deck_dashboard"))) {
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        res.end(u.query.callback + "(" + JSON.stringify(wallpapers[Math.floor(Math.random() * wallpapers.length)]) + ");");
    }
    else if (u.pathname === "/api/get_decks") {
        if (!(await auth.auth(u.query.username, u.query.password, "deck_dashboard_read", "get_decks"))) {
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        getDecks((err, decks) => {
            if (err) {
                res.writeHead(500);
                res.end(u.query.callback + "(" + err.toString() + ");");
            }
            else {
                res.writeHead(200);
                res.end(u.query.callback + "(" + JSON.stringify(decks) + ");");
            }
        });
    }
    else if (u.pathname === "/api/del_deck") {
        if (!(await auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "delete_deck"))) {
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        delDeck(u.query.msg, (err) => {
            let result;
            if (err) {
                result = "删除卡组 " + u.query.msg + "失败: " + err.toString();
            }
            else {
                result = "删除卡组 " + u.query.msg + "成功。";
            }
            res.writeHead(200);
            res.end(u.query.callback + '("' + result + '");');
        });
    }
    else if (u.pathname === "/api/clear_decks") {
        if (!(await auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "clear_decks"))) {
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        clearDecks((err) => {
            let result;
            if (err) {
                result = "删除全部卡组失败。" + err.toString();
            }
            else {
                result = "删除全部卡组成功。";
            }
            res.writeHead(200);
            res.end(u.query.callback + '("' + result + '");');
        });
    }
    else if (u.pathname === "/api/upload_to_challonge") {
        if (!(await auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "upload_to_challonge"))) {
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        await UploadToChallonge();
        res.end(u.query.callback + '("操作完成。");');
    }
    else {
        res.writeHead(400);
        res.end("400");
    }
}
if (ssl_config.enabled) {
    const ssl_cert = fs.readFileSync(ssl_config.cert);
    const ssl_key = fs.readFileSync(ssl_config.key);
    const options = {
        cert: ssl_cert,
        key: ssl_key,
    };
    https.createServer(options, requestListener).listen(config.port);
}
else {
    http.createServer(requestListener).listen(config.port);
}
