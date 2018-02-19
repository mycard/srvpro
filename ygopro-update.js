/*
 ygopro-update.js
 ygopro update util (not fully implymented)
 Author: mercury233
 License: MIT
 
 不带参数运行时，会建立一个服务器，调用API执行对应操作
 TODO：带参数运行时执行对应操作后退出
*/
var http = require('http');
var sqlite3 = require('sqlite3').verbose();
var fs = require('fs');
var execSync = require('child_process').execSync;
var spawn = require('child_process').spawn;
var spawnSync = require('child_process').spawnSync;
var url = require('url');
var moment = require('moment');
moment.locale('zh-cn');

var constants = require('./data/constants.json');

var settings = require('./config/config.json');
config=settings.modules.update_util;

//全卡名称列表
var cardNames={};
//
var changelog=[];
//http长连接
var responder;

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

//读取数据库内内容到cardNames，异步
var loadDb = function(db_file) {
    var db = new sqlite3.Database(db_file);
    
    db.each("select id,name from texts", function (err,result) {
        if (err) {
            sendResponse(db_file + ":" + err);
            return;
        }
        else {
            cardNames[result.id] = result.name;
        }
    }, function(err, num) {
        if(err) {
            sendResponse(db_file + ":" + err);
        }
        else {
            sendResponse("已加载数据库"+db_file+"，共"+num+"张卡。");
        }
    });
}
var loadChangelog = function(json_file) {
    changelog = JSON.parse(fs.readFileSync(json_file, 'utf8')).changelog;
    sendResponse("已加载更新记录"+json_file+"，共"+changelog.length+"条，最后更新于"+changelog[0].date+"。");
}

var makeChangelogs = function(dir, since) {
    var lastcommit;
    var addedCards=[];
    var changedCards=[];
    var prc_git_log = spawnSync("git", [ "log", "--pretty=%H,%ai", since ], { "cwd" : dir });
    if (prc_git_log.stdout) {
        var logs = prc_git_log.stdout.toString().split(/\n/g);
        for (var i in logs) {
            var log = logs[i].split(",");
            var date = log[1];
            if (date) {
                var prc_git_diff = spawnSync("git", [ "diff-tree", "--no-commit-id", "--name-only" ,"--diff-filter=A" , "-r", log[0] ], { "cwd" : dir });
                if (prc_git_diff.stdout) {
                    var lines = prc_git_diff.stdout.toString().split(/\n/g);
                    for (var j in lines) {
                        var line = lines[j].match(/c(\d+)\.lua/);
                        if (line) {
                            var name = cardNames[line[1]] || line[1];
                            addedCards.push(name);
                            sendResponse("<span class='add'>" + date + " + " + name + "</span>");
                        }
                    }
                }
            }
        }
        for (var i in logs) {
            var log = logs[i].split(",");
            var date = log[1];
            if (date) {
                var prc_git_diff = spawnSync("git", [ "diff-tree", "--no-commit-id", "--name-only" ,"--diff-filter=ad" , "-r", log[0] ], { "cwd" : dir });
                if (prc_git_diff.stdout) {
                    var lines = prc_git_diff.stdout.toString().split(/\n/g);
                    for (var j in lines) {
                        var line = lines[j].match(/c(\d+)\.lua/);
                        if (line) {
                            var name = cardNames[line[1]] || line[1];
                            sendResponse("<span class='change'>" + date + " * " + name + "</span>");
                            if (!addedCards.includes(name) && !changedCards.includes(name)) {
                                changedCards.push(name);
                            }
                        }
                    }
                }
            }
        }
        
        sendResponse("新增卡片：");
        for (var i in addedCards) {
            sendResponse("-&nbsp;&nbsp;&nbsp;" + addedCards[i]);
        }
        if (addedCards.length == 0) {
            sendResponse("-&nbsp;&nbsp;&nbsp;无");
        }
        sendResponse("\n");
        sendResponse("卡片更改：");
        for (var i in changedCards) {
            sendResponse("-&nbsp;&nbsp;&nbsp;" + changedCards[i]);
        }
        if (changedCards.length == 0) {
            sendResponse("-&nbsp;&nbsp;&nbsp;无");
        }
    } else {
        sendResponse("获取更新记录失败：" + prc_git_log.stderr.toString());
    }
}

//从远程更新数据库，异步
var fetchDatas = function() {
    var proc = spawn("git", ["pull", "origin", "master"], { cwd: config.git_db_path, env: process.env });
    proc.stdout.setEncoding('utf8');
    proc.stdout.on('data', function(data) {
        sendResponse("git pull: "+data);
    });
    proc.stderr.setEncoding('utf8');
    proc.stderr.on('data', function(data) {
        sendResponse("git pull: "+data);
    });
    proc.on('close', function (code) {
        sendResponse("数据更新完成。");
    });
    var proc2 = spawn("git", ["pull", "origin", "master"], { cwd: config.git_html_path, env: process.env });
    proc2.stdout.setEncoding('utf8');
    proc2.stdout.on('data', function(data) {
        sendResponse("git pull: "+data);
    });
    proc2.stderr.setEncoding('utf8');
    proc2.stderr.on('data', function(data) {
        sendResponse("git pull: "+data);
    });
    proc2.on('close', function (code) {
        sendResponse("网页同步完成。");
    });
}


//建立一个http服务器，接收API操作
http.createServer(function (req, res) {
    var u = url.parse(req.url, true);
    
    if (u.query.password !== config.password) {
        res.writeHead(403);
        res.end("Auth Failed.");
        return;
    }
    
    if (u.pathname === '/api/msg') {
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
    else if (u.pathname === '/api/load_db') {
        res.writeHead(200);
        res.end(u.query.callback+'({"message":"开始加载数据库。"});');
        loadDb("./ygopro/cards.cdb");
        loadChangelog(config.html_path + config.changelog_filename);
    }
    else if (u.pathname === '/api/make_changelog') {
        res.writeHead(200);
        var date = moment(changelog[0].date).add(1,'days').format("YYYY-MM-DD");
        res.end(u.query.callback+'({"message":"开始生成'+ date +'以来的更新记录："});');
        makeChangelogs("./ygopro/script", "--since="+date);
    }
    else if (u.pathname === '/api/make_more_changelog') {
        res.writeHead(200);
        res.end(u.query.callback+'({"message":"开始生成最近20次的更新记录："});');
        makeChangelogs("./ygopro/script", "-20");
    }
    else if (u.pathname === '/api/push_datas') {
        res.writeHead(200);
        res.end(u.query.callback+'({"message":"开始上传到网页。"});');
        pushDatas();
    }
    else if (u.pathname === '/api/write_to_file') {
        res.writeHead(200);
        res.end(u.query.callback+'({"message":"开始写列表页。"});');
        writeToFile(u.query.message);
    }
    else {
        res.writeHead(400);
        res.end("400");
    }

}).listen(config.port);

