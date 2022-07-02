/*
 ygopro-tournament.js
 ygopro tournament util
 Author: mercury233
 License: MIT
 
 不带参数运行时，会建立一个服务器，调用API执行对应操作
*/
const http = require('http');
const https = require('https');
const fs = require('fs');
const url = require('url');
const request = require('request');
const formidable = require('formidable');
const _ = require('underscore');
_.str = require('underscore.string');
_.mixin(_.str.exports());
const loadJSON = require('load-json-file').sync;
const axios = require('axios');

const auth = require('./ygopro-auth.js');

const settings = loadJSON('./config/config.json');
config = settings.modules.tournament_mode;
challonge_config = settings.modules.challonge;
ssl_config = settings.modules.http.ssl;

const _async = require("async");
const os = require("os");
const PROCESS_COUNT = os.cpus().length;

//http长连接
let responder;

config.wallpapers=[""];
request({
    url: "http://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=zh-CN",
    json: true
}, function(error, response, body) {
    if (_.isString(body)) {
        console.log("wallpapers bad json", body);
    }
    else if (error || !body) {
        console.log('wallpapers error', error, response);
    }
    else {
        config.wallpapers=[];
        for (const i in body.images) {
            const wallpaper=body.images[i];
            const img={
                "url": "http://s.cn.bing.net"+wallpaper.urlbase+"_768x1366.jpg",
                "desc": wallpaper.copyright
            }
            config.wallpapers.push(img);
        }
    }
});

//输出反馈信息，如有http长连接则输出到http，否则输出到控制台
const sendResponse = function(text) {
    text=""+text;
    if (responder) {
        text=text.replace(/\n/g,"<br>");
        responder.write("data: " + text + "\n\n");
    }
    else {
        console.log(text);
    }
}

//读取指定卡组
const readDeck = async function(deck_name, deck_full_path) {
    const deck={};
    deck.name=deck_name;
    deck_text = await fs.promises.readFile(deck_full_path, { encoding: "ASCII" });
    deck_array = deck_text.split("\n");
    deck.main = [];
    deck.extra = [];
    deck.side = [];
    current_deck = deck.main;
    for (l in deck_array) {
        line = deck_array[l];
        if (line.indexOf("#extra") >= 0) {
            current_deck = deck.extra;
        }
        if (line.indexOf("!side") >= 0) {
            current_deck = deck.side;
        }
        card = parseInt(line);
        if (!isNaN(card)) {
            current_deck.push(card);
        }
    }
    return deck;
}

//读取指定文件夹中所有卡组
const getDecks = function(callback) {
    const decks=[];
    _async.auto({
        readDir: (done) => {
            fs.readdir(config.deck_path, done);
        },
        handleDecks: ["readDir", (results, done) => {
            const decks_list = results.readDir;
            _async.each(decks_list, async(deck_name) => {
                if (_.endsWith(deck_name, ".ydk")) {
                    const deck = await readDeck(deck_name, config.deck_path + deck_name);
                    decks.push(deck);
                }
            }, done)
        }]
    }, (err) => { 
            callback(err, decks);
    });

}

const delDeck = function (deck_name, callback) {
    if (deck_name.startsWith("../") || deck_name.match(/\/\.\.\//)) { //security issue
        callback("Invalid deck");
    }
    fs.unlink(config.deck_path + deck_name, callback);
}

const clearDecks = function (callback) {
    _async.auto({
        deckList: (done) => { 
            fs.readdir(config.deck_path, done);
        },
        removeAll: ["deckList", (results, done) => { 
            const decks_list = results.deckList;
            _async.each(decks_list, delDeck, done);
        }]
    }, callback);
}

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
        if (_.endsWith(deck_name, ".ydk")) {
            player_list.push(deck_name.slice(0, deck_name.length - 4));
        }
    }
    if (!player_list.length) {
        sendResponse("玩家列表为空。");
        return false;
    }
    sendResponse("读取玩家列表完毕，共有" + player_list.length + "名玩家。");
    try {
        sendResponse("开始清空 Challonge 玩家列表。");
        await axios.delete(`https://api.challonge.com/v1/tournaments/${challonge_config.tournament_id}/participants/clear.json`, {
            params: {
                api_key: challonge_config.api_key
            },
            validateStatus: () => true,
        });
        sendResponse("开始上传玩家列表至 Challonge。");
        for (const chunk of _.chunk(player_list, 10)) {
            sendResponse(`开始上传玩家 ${chunk.join(', ')} 至 Challonge。`);
            await axios.post(`https://api.challonge.com/v1/tournaments/${challonge_config.tournament_id}/participants/bulk_add.json`, {
            api_key: challonge_config.api_key,
            participants: chunk.map(name => ({ name })),
        });
        }
        sendResponse("玩家列表上传完成。");
    } catch (e) {
        sendResponse("Challonge 上传失败：" + e.message);
    }
    return true;
}

const receiveDecks = function(files, callback) {
    const result = [];
    _async.eachSeries(files, async(file) => {
        if (_.endsWith(file.name, ".ydk")) {
            const deck = await readDeck(file.name, file.path);
            if (deck.main.length >= 40) {
                fs.createReadStream(file.path).pipe(fs.createWriteStream(config.deck_path + file.name));
                result.push({
                    file: file.name,
                    status: "OK"
                });
            }
            else {
                result.push({
                    file: file.name,
                    status: "卡组不合格"
                });
            }
        }
        else {
            result.push({
                file: file.name,
                status: "不是卡组文件"
            });
        }
    }, (err) => { 
        callback(err, result);
    });
}

//建立一个http服务器，接收API操作
async function requestListener(req, res) {
    const u = url.parse(req.url, true);
    
    /*if (u.query.password !== config.password) {
        res.writeHead(403);
        res.end("Auth Failed.");
        return;
    }*/
    
    if (u.pathname === '/api/upload_decks' && req.method.toLowerCase() == 'post') {
        if (!await auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "upload_deck")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        const form = new formidable.IncomingForm();
        form.parse(req, function(err, fields, files) {
            receiveDecks(files, (err, result) => { 
                if (err) {
                    console.error(`Upload error: ${err}`);
                    res.writeHead(500, {
                        "Access-Control-Allow-origin": "*",
                        'content-type': 'text/plain'
                    });
                    res.end(JSON.stringify({error: err.toString()}));
                    return;
                }
                res.writeHead(200, {
                    "Access-Control-Allow-origin": "*",
                    'content-type': 'text/plain'
                });
                res.end(JSON.stringify(result));
            });
        });
    }
    else if (u.pathname === '/api/msg') {
        if (!await auth.auth(u.query.username, u.query.password, "deck_dashboard_read", "login_deck_dashboard")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200, {
            "Access-Control-Allow-origin": "*",
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive"
        });
        
        res.on("close", function(){
            responder = null;
        });
        
        responder = res;
        
        sendResponse("已连接。");
    }
    else if (u.pathname === '/api/get_bg') {
        if (!await auth.auth(u.query.username, u.query.password, "deck_dashboard_read", "login_deck_dashboard")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        res.end(u.query.callback+'('+JSON.stringify(config.wallpapers[Math.floor(Math.random() * config.wallpapers.length)])+');');
    }
    else if (u.pathname === '/api/get_decks') {
        if (!await auth.auth(u.query.username, u.query.password, "deck_dashboard_read", "get_decks")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        getDecks((err, decks) => { 
            if (err) {
                res.writeHead(500);
                res.end(u.query.callback + '(' + err.toString() +');');
            } else { 
                res.writeHead(200);
                res.end(u.query.callback+'('+JSON.stringify(decks)+');');
            }
        })
    }
    else if (u.pathname === '/api/del_deck') {
        if (!await auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "delete_deck")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        delDeck(u.query.msg, (err) => { 
            let result;
            if (err) {
                result = "删除卡组 " + u.query.msg + "失败: " + err.toString();
            } else { 
                result = "删除卡组 " + u.query.msg + "成功。";
            }
            res.writeHead(200);
            res.end(u.query.callback+'("'+result+'");');
        });
    }
    else if (u.pathname === '/api/clear_decks') {
        if (!await auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "clear_decks")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        clearDecks((err) => { 
            let result;
            if (err) {
                result = "删除全部卡组失败。" + err.toString();
            } else { 
                result = "删除全部卡组成功。";
            }
            res.writeHead(200);
            res.end(u.query.callback+'("'+result+'");');
        });
    }
    else if (u.pathname === '/api/upload_to_challonge') {
        if (!await auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "upload_to_challonge")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        const result = await UploadToChallonge();
        res.end(u.query.callback+'("操作完成。");');
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
        key: ssl_key
    }
    https.createServer(options, requestListener).listen(config.port);
} else { 
    http.createServer(requestListener).listen(config.port);
}
