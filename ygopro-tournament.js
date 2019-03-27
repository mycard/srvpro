/*
 ygopro-tournament.js
 ygopro tournament util
 Author: mercury233
 License: MIT
 
 不带参数运行时，会建立一个服务器，调用API执行对应操作
*/
var http = require('http');
var https = require('https');
var fs = require('fs');
var url = require('url');
var request = require('request');
var formidable = require('formidable');
var _ = require('underscore');
_.str = require('underscore.string');
_.mixin(_.str.exports());
var loadJSON = require('load-json-file').sync;

var auth = require('./ygopro-auth.js');

var settings = loadJSON('./config/config.json');
config = settings.modules.tournament_mode;
challonge_config = settings.modules.challonge;
ssl_config = settings.modules.http.ssl;

var challonge;
if (challonge_config.enabled) {
    challonge = require('challonge').createClient({
        apiKey: challonge_config.api_key
    });
}

//http长连接
var responder;

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
        for (var i in body.images) {
            var wallpaper=body.images[i];
            var img={
                "url": "http://s.cn.bing.net"+wallpaper.urlbase+"_768x1366.jpg",
                "desc": wallpaper.copyright
            }
            config.wallpapers.push(img);
        }
    }
});

//输出反馈信息，如有http长连接则输出到http，否则输出到控制台
var sendResponse = function(text) {
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
var readDeck = function(deck_name, deck_full_path) {
    var deck={};
    deck.name=deck_name;
    deck_text = fs.readFileSync(deck_full_path, { encoding: "ASCII" });
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
var getDecks = function() {
    var decks=[];
    var decks_list = fs.readdirSync(config.deck_path);
    for (var k in decks_list) {
        var deck_name = decks_list[k];
        if (_.endsWith(deck_name, ".ydk")) {
            var deck = readDeck(deck_name, config.deck_path+deck_name);
            decks.push(deck);
        }
    }
    return decks;
}

var delDeck = function(deck_name) {
    var result=0;
    try {
        fs.unlinkSync(config.deck_path+deck_name);
        result="已删除"+deck_name+"。";
    }
    catch(e) {
        result=e.toString();
    }
    finally {
        return result;
    }
}

var clearDecks = function() {
    var decks_list = fs.readdirSync(config.deck_path);
    for (var k in decks_list) {
        var deck_name = decks_list[k];
        if (_.endsWith(deck_name, ".ydk")) {
            delDeck(deck_name);
        }
    }
}

var UploadToChallonge = function() {
    if (!challonge) {
        sendResponse("未开启Challonge模式。");
        return false;
    }
    sendResponse("开始读取玩家列表。");
    var decks_list = fs.readdirSync(config.deck_path);
    var player_list = [];
    for (var k in decks_list) {
        var deck_name = decks_list[k];
        if (_.endsWith(deck_name, ".ydk")) {
            player_list.push(deck_name.slice(0, deck_name.length - 4));
        }
    }
    if (!player_list.length) {
        sendResponse("玩家列表为空。");
        return false;
    }
    sendResponse("读取玩家列表完毕，共有"+player_list.length+"名玩家。");
    sendResponse("开始上传玩家列表至Challonge。");
    var success_count = [0];
    for (var k in player_list) {
        var player_name = player_list[k];
        sendResponse("正在上传玩家 "+player_name+" 至Challonge。");
        challonge.participants.create({
            id: challonge_config.tournament_id,
            participant: {
                name: player_name
            },
            callback: (function(player_name, success_count) {
                return function(err, data) {
                    if (err) {
                        sendResponse("玩家 "+player_name+" 上传失败："+err.text);
                    } else {
                        if (data.participant) {
                            sendResponse("玩家 "+player_name+" 上传完毕，其Challonge ID是 "+data.participant.id+" 。");
                        } else {
                            sendResponse("玩家 "+player_name+" 上传完毕。");
                        }
                        ++success_count[0];
                        if (success_count[0] >= player_list.length) {
                            sendResponse("玩家列表上传完成。");
                        }
                    }
                };
            })(player_name, success_count)
        });
    }
    return true;
}

var receiveDecks = function(files) {
    var result=[];
    for (var i in files) {
        var file=files[i];
        if (_.endsWith(file.name, ".ydk")) {
            var deck=readDeck(file.name, file.path);
            if (deck.main.length>=40) {
                fs.createReadStream(file.path).pipe(fs.createWriteStream(config.deck_path+file.name));
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
    }
    return result;
}

//建立一个http服务器，接收API操作
function requestListener(req, res) {
    var u = url.parse(req.url, true);
    
    /*if (u.query.password !== config.password) {
        res.writeHead(403);
        res.end("Auth Failed.");
        return;
    }*/
    
    if (u.pathname === '/api/upload_decks' && req.method.toLowerCase() == 'post') {
        if (!auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "upload_deck")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        var form = new formidable.IncomingForm();
        form.parse(req, function(err, fields, files) {
            res.writeHead(200, {
                "Access-Control-Allow-origin": "*",
                'content-type': 'text/plain'
            });
            var result=receiveDecks(files);
            //console.log(files);
            res.end(JSON.stringify(result));
        });
    }
    else if (u.pathname === '/api/msg') {
        if (!auth.auth(u.query.username, u.query.password, "deck_dashboard_read", "login_deck_dashboard")) { 
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
        if (!auth.auth(u.query.username, u.query.password, "deck_dashboard_read", "login_deck_dashboard")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        res.end(u.query.callback+'('+JSON.stringify(config.wallpapers[Math.floor(Math.random() * config.wallpapers.length)])+');');
    }
    else if (u.pathname === '/api/get_decks') {
        if (!auth.auth(u.query.username, u.query.password, "deck_dashboard_read", "get_decks")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        var decklist=getDecks();
        res.end(u.query.callback+'('+JSON.stringify(decklist)+');');
    }
    else if (u.pathname === '/api/del_deck') {
        if (!auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "delete_deck")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        var result=delDeck(u.query.msg);
        res.end(u.query.callback+'("'+result+'");');
    }
    else if (u.pathname === '/api/clear_decks') {
        if (!auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "clear_decks")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        clearDecks();
        res.end(u.query.callback+'("已删除全部卡组。");');
    }
    else if (u.pathname === '/api/upload_to_challonge') {
        if (!auth.auth(u.query.username, u.query.password, "deck_dashboard_write", "upload_to_challonge")) { 
            res.writeHead(403);
            res.end("Auth Failed.");
            return;
        }
        res.writeHead(200);
        var result=UploadToChallonge();
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
