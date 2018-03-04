/*
 ygopro-tournament.js
 ygopro tournament util
 Author: mercury233
 License: MIT
 
 不带参数运行时，会建立一个服务器，调用API执行对应操作
*/
var http = require('http');
var fs = require('fs');
var url = require('url');
var request = require('request');
var formidable = require('formidable');
var _ = require('underscore');
_.str = require('underscore.string');
_.mixin(_.str.exports());
var loadJSON = require('load-json-file').sync;

var settings = loadJSON('./config/config.json');
config=settings.modules.tournament_mode;

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
http.createServer(function (req, res) {
    var u = url.parse(req.url, true);
    
    if (u.query.password !== config.password) {
        res.writeHead(403);
        res.end("Auth Failed.");
        return;
    }
    
    if (u.pathname === '/api/upload_decks' && req.method.toLowerCase() == 'post') {
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
        res.writeHead(200);
        res.end(u.query.callback+'('+JSON.stringify(config.wallpapers[Math.floor(Math.random() * config.wallpapers.length)])+');');
    }
    else if (u.pathname === '/api/get_decks') {
        res.writeHead(200);
        var decklist=getDecks();
        res.end(u.query.callback+'('+JSON.stringify(decklist)+');');
    }
    else if (u.pathname === '/api/del_deck') {
        res.writeHead(200);
        var result=delDeck(u.query.msg);
        res.end(u.query.callback+'("'+result+'");');
    }
    else if (u.pathname === '/api/clear_decks') {
        res.writeHead(200);
        clearDecks();
        res.end(u.query.callback+'("已删除全部卡组。");');
    }
    else {
        res.writeHead(400);
        res.end("400");
    }

}).listen(config.port);

