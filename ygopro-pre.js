/*
 ygopro-pre.js
 ygopro pre-release cards util
 Author: mercury233
 License: MIT
 
 不带参数运行时，会建立一个服务器，调用API执行对应操作
 TODO：带参数运行时执行对应操作后退出
*/
var http = require('http');
var https = require('https');
var sqlite3 = require('sqlite3').verbose();
var fs = require('fs');
var exec = require('child_process').exec;
var execSync = require('child_process').execSync;
var spawn = require('child_process').spawn;
var url = require('url');
var util = require('util');
var moment = require('moment');
moment.locale('zh-cn');
var loadJSON = require('load-json-file').sync;

var auth = require('./ygopro-auth.js');

var constants = loadJSON('./data/constants.json');

var settings = loadJSON('./config/config.json');
config = settings.modules.pre_util;
ssl_config = settings.modules.http.ssl;

//全卡HTML列表
var cardHTMLs=[];
//http长连接
var responder;
//URL里的更新时间戳
var dataver = moment().format("YYYYMMDDHHmmss");
const _async = require("async");

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

//读取数据库内内容到cardHTMLs，异步
var loadDb = function(db_file, callback) {
    var db = new sqlite3.Database(db_file);
    
    db.each("select * from datas,texts where datas.id=texts.id", function (err,result) {
        if (err) {
            sendResponse(db_file + ":" + err);
            return;
        }
        else {
            if (result.type & constants.TYPES.TYPE_TOKEN) {
                return;
            }
            
            var cardHTML="<tr>";
            
            cardHTML+='<td><a href="'+ config.html_img_rel_path + result.id +'.jpg" target="_blank"><img data-original="'+config.html_img_rel_path+config.html_img_thumbnail+ result.id +'.jpg'+ config.html_img_thumbnail_suffix +'" alt="'+ result.name +'"></a></td>';
            cardHTML+='<td>'+ result.name +'</td>';
            
            var cardText="";
            
            var cardTypes=[];
            if (result.type & constants.TYPES.TYPE_MONSTER) {cardTypes.push("怪兽");}
            if (result.type & constants.TYPES.TYPE_SPELL) {cardTypes.push("魔法");}
            if (result.type & constants.TYPES.TYPE_TRAP) {cardTypes.push("陷阱");}
            if (result.type & constants.TYPES.TYPE_NORMAL) {cardTypes.push("通常");}
            if (result.type & constants.TYPES.TYPE_EFFECT) {cardTypes.push("效果");}
            if (result.type & constants.TYPES.TYPE_FUSION) {cardTypes.push("融合");}
            if (result.type & constants.TYPES.TYPE_RITUAL) {cardTypes.push("仪式");}
            if (result.type & constants.TYPES.TYPE_TRAPMONSTER) {cardTypes.push("陷阱怪兽");}
            if (result.type & constants.TYPES.TYPE_SPIRIT) {cardTypes.push("灵魂");}
            if (result.type & constants.TYPES.TYPE_UNION) {cardTypes.push("同盟");}
            if (result.type & constants.TYPES.TYPE_DUAL) {cardTypes.push("二重");}
            if (result.type & constants.TYPES.TYPE_TUNER) {cardTypes.push("调整");}
            if (result.type & constants.TYPES.TYPE_SYNCHRO) {cardTypes.push("同调");}
            if (result.type & constants.TYPES.TYPE_TOKEN) {cardTypes.push("衍生物");}
            if (result.type & constants.TYPES.TYPE_QUICKPLAY) {cardTypes.push("速攻");}
            if (result.type & constants.TYPES.TYPE_CONTINUOUS) {cardTypes.push("永续");}
            if (result.type & constants.TYPES.TYPE_EQUIP) {cardTypes.push("装备");}
            if (result.type & constants.TYPES.TYPE_FIELD) {cardTypes.push("场地");}
            if (result.type & constants.TYPES.TYPE_COUNTER) {cardTypes.push("反击");}
            if (result.type & constants.TYPES.TYPE_FLIP) {cardTypes.push("反转");}
            if (result.type & constants.TYPES.TYPE_TOON) {cardTypes.push("卡通");}
            if (result.type & constants.TYPES.TYPE_XYZ) {cardTypes.push("超量");}
            if (result.type & constants.TYPES.TYPE_PENDULUM) {cardTypes.push("灵摆");}
            if (result.type & constants.TYPES.TYPE_SPSUMMON) {cardTypes.push("特殊召唤");}
            if (result.type & constants.TYPES.TYPE_LINK) {cardTypes.push("连接");}
            cardText+="["+ cardTypes.join('|') +"]";
            
            if (result.type & constants.TYPES.TYPE_MONSTER) {
                var cardRace="";
                if (result.race & constants.RACES.RACE_WARRIOR) {cardRace="战士";}
                if (result.race & constants.RACES.RACE_SPELLCASTER) {cardRace="魔法师";}
                if (result.race & constants.RACES.RACE_FAIRY) {cardRace="天使";}
                if (result.race & constants.RACES.RACE_FIEND) {cardRace="恶魔";}
                if (result.race & constants.RACES.RACE_ZOMBIE) {cardRace="不死";}
                if (result.race & constants.RACES.RACE_MACHINE) {cardRace="机械";}
                if (result.race & constants.RACES.RACE_AQUA) {cardRace="水";}
                if (result.race & constants.RACES.RACE_PYRO) {cardRace="炎";}
                if (result.race & constants.RACES.RACE_ROCK) {cardRace="岩石";}
                if (result.race & constants.RACES.RACE_WINDBEAST) {cardRace="鸟兽";}
                if (result.race & constants.RACES.RACE_PLANT) {cardRace="植物";}
                if (result.race & constants.RACES.RACE_INSECT) {cardRace="昆虫";}
                if (result.race & constants.RACES.RACE_THUNDER) {cardRace="雷";}
                if (result.race & constants.RACES.RACE_DRAGON) {cardRace="龙";}
                if (result.race & constants.RACES.RACE_BEAST) {cardRace="兽";}
                if (result.race & constants.RACES.RACE_BEASTWARRIOR) {cardRace="兽战士";}
                if (result.race & constants.RACES.RACE_DINOSAUR) {cardRace="恐龙";}
                if (result.race & constants.RACES.RACE_FISH) {cardRace="鱼";}
                if (result.race & constants.RACES.RACE_SEASERPENT) {cardRace="海龙";}
                if (result.race & constants.RACES.RACE_REPTILE) {cardRace="爬虫类";}
                if (result.race & constants.RACES.RACE_PSYCHO) {cardRace="念动力";}
                if (result.race & constants.RACES.RACE_DEVINE) {cardRace="幻神兽";}
                if (result.race & constants.RACES.RACE_CREATORGOD) {cardRace="创造神";}
                if (result.race & constants.RACES.RACE_WYRM) {cardRace="幻龙";}
                if (result.race & constants.RACES.RACE_CYBERS) {cardRace="电子界";}
                cardText+=" "+ cardRace;
                
                var cardAttr="";
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_EARTH) {cardAttr="地";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_WATER) {cardAttr="水";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_FIRE) {cardAttr="炎";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_WIND) {cardAttr="风";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_LIGHT) {cardAttr="光";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_DARK) {cardAttr="暗";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_DEVINE) {cardAttr="神";}
                cardText+="/"+ cardAttr +"\n";
            
                var cardLevel;
                var cardLScale;
                var cardRScale;
                if (result.level<=12) {
                    cardLevel=result.level;
                }
                else { //转化为16位，0x01010004，前2位是左刻度，2-4是右刻度，末2位是等级
                    var levelHex=parseInt(result.level, 10).toString(16);
                    cardLevel=parseInt(levelHex.slice(-2), 16);
                    cardLScale=parseInt(levelHex.slice(-8,-6), 16);
                    cardRScale=parseInt(levelHex.slice(-6,-4), 16);
                }

                if (!(result.type & constants.TYPES.TYPE_LINK)) {
                    cardText+="[" + ((result.type & constants.TYPES.TYPE_XYZ) ? "☆" : "★") + cardLevel + "]";
                    cardText+=" " + (result.atk < 0 ? "?" : result.atk) + "/" + (result.def < 0 ? "?" : result.def);
                }
                else {
                    cardText+="[LINK-" + cardLevel + "]";
                    cardText += " " + (result.atk < 0 ? "?" : result.atk) + "/- ";
                    
                    if (result.def & constants.LINK_MARKERS.LINK_MARKER_TOP_LEFT)
                        cardText += "[↖]";
                    if (result.def & constants.LINK_MARKERS.LINK_MARKER_TOP)
                        cardText += "[↑]";
                    if (result.def & constants.LINK_MARKERS.LINK_MARKER_TOP_RIGHT)
                        cardText += "[↗]";
                    if (result.def & constants.LINK_MARKERS.LINK_MARKER_LEFT)
                        cardText += "[←]";
                    if (result.def & constants.LINK_MARKERS.LINK_MARKER_RIGHT)
                        cardText += "[→]";
                    if (result.def & constants.LINK_MARKERS.LINK_MARKER_BOTTOM_LEFT)
                        cardText += "[↙]";
                    if (result.def & constants.LINK_MARKERS.LINK_MARKER_BOTTOM)
                        cardText += "[↓]";
                    if (result.def & constants.LINK_MARKERS.LINK_MARKER_BOTTOM_RIGHT)
                        cardText += "[↘]";
                }
                
                if (cardLScale) {
                    cardText+="  " + cardLScale + "/" +cardRScale;
                }
                
                cardText+="\n";
            }
            else {
                cardText+="\n";
            }
            cardText+=result.desc;
            
            cardHTML+='<td>'+ cardText.replace(/\r/g,"").replace(/\n/g,"<br>") +'</td>';
            cardHTML+='</tr>';
            
            cardHTMLs.push(cardHTML);
        }
    }, function(err, num) {
        if(err) {
            sendResponse(db_file + ":" + err);
        }
        else {
            dataver = moment().format("YYYYMMDDHHmmss");
            sendResponse("已加载数据库"+db_file+"，共"+num+"张卡。");
        }
            callback(err, num);
    });
}

//将cardHTMLs中内容更新到指定列表页，同步
var writeToFile = function(message, callback) {
    var fileContent=fs.readFileSync(config.html_path+config.html_filename, {"encoding":"utf-8"});
    var newContent=cardHTMLs.join("\n");
    fileContent=fileContent.replace(/<tbody class="auto-generated">[\w\W]*<\/tbody>/,'<tbody class="auto-generated">\n'+newContent+'\n</tbody>');
    fileContent = fileContent.replace(/data-ygosrv233-download="(http.+)" href="http.+"/g, 'data-ygosrv233-download="$1" href="$1"');
    fileContent = fileContent.replace(/href="(http.+)dataver/g, 'href="$1' + dataver);
    if (message) {
        message="<li>"+moment().format('L HH:mm')+"<ul><li>"+message.split("！换行符！").join("</li><li>")+"</li></ul></li>";
        fileContent=fileContent.replace(/<ul class="auto-generated">/,'<ul class="auto-generated">\n'+message);
    }
    _async.auto({
        write: (done) => { 
            fs.writeFile(config.html_path + config.html_filename, fileContent, done)
        },
        copy: ["write", (results, done) => { 
            if (!config.cdn.enabled) {
                copyImages(done);
            } else { 
                done();
            }
        }]
    }, (err) => { 
        if (!err) {
            sendResponse("列表更新完成。");
        }
        callback(err);  
    })
}

//读取指定文件夹里所有数据库，异步
var loadAllDbs = function(callback) {
    cardHTMLs=[];
    _async.auto({
        files: (done) => {
            fs.readdir(config.db_path + "expansions/", done);
        },
        loadDbs: ["files", (results, done) => {
            _async.each(results.files.filter((filename) => { 
                return filename.slice(-4) === ".cdb" && (!config.only_show_dbs || config.only_show_dbs.length == 0 || config.only_show_dbs[filename])
            } ).map(filename => config.db_path + "expansions/" + filename), loadDb, done);
        }]
    }, callback);
}


function execCommands(commands, callback) { 
    _async.eachSeries(commands, (command, done) => {
        exec(command, (err) => { 
            done(err);
        });
    }, callback);
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

//更新本地网页到服务器，异步
var pushDatas = function(callback) {
    if (config.cdn.enabled) {
        _async.auto({
            local: (done) => {
                uploadCDN(config.cdn.local, config.cdn.remote + "/" + dataver, done);
            },
            pics: ["local", (results, done) => {
                uploadCDN(config.db_path + "pics", config.cdn.pics_remote + "pics", done);
            }],
            push: ["local", "pics", (results, done) => {
                sendResponse("CDN上传全部完成。");
                pushHTMLs(done);
            }]
        }, callback);
    }
}

var pushHTMLs = function(callback) {
    sendResponse("开始上传到网页。");
    try {
        execSync('git add --all .', { cwd: config.git_html_path, env: process.env });
        execSync('git commit -m update-auto', { cwd: config.git_html_path, env: process.env });
    } catch (error) {
        sendResponse("git error: "+error.stdout);
    }
    for (var i in config.html_gits) {
        var git = config.html_gits[i];
        var proc = spawn("git", git.push, { cwd: config.git_html_path, env: process.env });
        proc.stdout.setEncoding('utf8');
        proc.stdout.on('data', (function(git) {
            return function(data) {
                sendResponse(git.name + " git push: " + data);
            }
        })(git));
        proc.stderr.setEncoding('utf8');
        proc.stderr.on('data', (function(git) {
            return function(data) {
                sendResponse(git.name + " git push: " + data);
            }
        })(git));
        proc.on('close', (function(git) {
            return function(code) {
                sendResponse(git.name + "上传完成。");
                callback();
            }
        })(git));
    }
}

//上传到CDN，异步
var uploadCDN = function(local, remote, callback) {
    sendResponse("CDN " + remote + " 开始上传。");
    var params = config.cdn.params.slice(0);
    params.push(local);
    params.push(remote);
    var proc = spawn(config.cdn.exe, params, { cwd: ".", env: process.env });
    proc.stdout.setEncoding('utf8');
    proc.stdout.on('data', function(data) {
        data = data + "";
        if (data.includes("fails")) {
            var datas = data.split("\n");
            sendResponse("CDN " + remote + " : " + datas[datas.length - 2]);
        }
    });
    proc.stderr.setEncoding('utf8');
    proc.stderr.on('data', function(data) {
        sendResponse("CDN: "+data);
    });
    proc.on('close', function (code) {
        sendResponse("CDN " + remote + " 上传完成。");
        callback();
    });
}

//将数据库文件夹里卡图复制到列表页对应文件夹里，异步
var copyImages = function (callback) {
    const commands = [
        'rm -rf "' + config.html_path + config.html_img_rel_path + '"',
        'cp -r "' + config.db_path + 'pics' + '" "' + config.html_path + config.html_img_rel_path + '"',
        'rm -rf "' + config.html_path+config.html_img_rel_path +'field"',
    ]
    execCommands(commands, (err) => {
        if (err) {
            sendResponse("卡图复制失败: " + err.toString());
        } else {
            sendResponse("卡图复制完成。");
        }
        callback(err);
    });
    
}

//将数据库文件夹复制到YGOPRO文件夹里，同步
var copyToYGOPRO = function(callback) {
    const commands = [
        'rm -rf ' + config.ygopro_path + 'expansions/*' + '',
        'cp -rf "' + config.db_path + 'expansions' + '" "' + config.ygopro_path + '"',
        'cp -rf "' + config.db_path + 'script' + '" "' + config.ygopro_path + 'expansions"',
        'cp -rf "' + config.db_path + 'lflist.conf' + '" "' + config.ygopro_path + '" || true'
    ]
    execCommands(commands, (err) => {
        if (err) {
            sendResponse("更新失败: " + err.toString());
        } else {
            sendResponse("更新完成。");
        }
        callback(err);
    });
}

function run7z(params, cwd, callback) { 
    let proc = spawn(settings.modules.tournament_mode.replay_archive_tool, params, { cwd: cwd, env: process.env });
    proc.stdout.setEncoding('utf8');
    proc.stdout.on('data', function(data) {
        //sendResponse("7z: "+data);
    });
    proc.stderr.setEncoding('utf8');
    proc.stderr.on('data', function(data) {
        sendResponse("7z error: "+data);
    });
    proc.on('close', function (code) {
        callback(code === 0 ? null : "exit " + code);
    });
} 

//生成更新包，异步
var packDatas = function (callback) {
    file_path = config.html_path;
    if (config.cdn.enabled) {
        file_path = config.cdn.local;
    }

    _async.auto({
        preCommands: (done) => {
            execCommands([
                'rm -rf "' + config.db_path +'expansions/' + config.ypk_name + '"',
                'rm -rf "' + config.db_path +'expansions/script"',
                'rm -rf "' + config.db_path +'expansions/pics"',
                'rm -rf "' + config.db_path +'cdb"',
                'rm -rf "' + config.db_path +'picture"',
                'mkdir "' + config.db_path +'picture"',
                'cp -r "' + config.db_path + 'expansions" "' + config.db_path + 'cdb"',
                'cp -r "' + config.db_path + 'pics" "' + config.db_path + 'expansions/pics"',
                'cp -r "' + config.db_path + 'field" "' + config.db_path + 'expansions/pics/field"',
                'cp -r "' + config.db_path + 'script" "' + config.db_path + 'expansions/script"',
                'cp -r "' + config.db_path + 'pics" "' + config.db_path + 'picture/card"',
                'cp -r "' + config.db_path + 'field" "' + config.db_path + 'picture/field"'
            ], done);
        },
        run7zYPK: ["preCommands", (results, done) => {
            run7z(["a", "-tzip", "-x!*.ypk", config.ypk_name, "*"], config.db_path + "expansions/", done);
        }],
        run7zPC: ["run7zYPK", (results, done) => {
            run7z(["a", "-x!*.zip", "-x!.git", "-x!LICENSE", "-x!README.md",
                        "-x!cdb", "-x!picture", "-x!field", "-x!script", "-x!pics",
                        "-x!expansions/pics", "-x!expansions/script", "-x!expansions/*.cdb", "-x!expansions/*.conf",
                        "ygosrv233-pre.zip", "*"], config.db_path, done);
        }],
        run7zMobile: ["run7zYPK", (results, done) => {
            run7z(["a", "-x!*.zip", "-x!.git", "-x!LICENSE", "-x!README.md",
                        "-x!cdb", "-x!picture", "-x!field", "-x!script", "-x!pics",
                        "-x!expansions/pics", "-x!expansions/script", "-x!expansions/*.cdb", "-x!expansions/*.conf",
                        "ygosrv233-pre-mobile.zip", "*"], config.db_path, done);
        }],
        run7zPro2: ["preCommands", (results, done) => {
            run7z(["a", "-x!*.zip", "-x!.git", "-x!LICENSE", "-x!README.md",
                        "-x!expansions", "-x!pics", "-x!field",
                        "ygosrv233-pre-2.zip", "*"], config.db_path, done);
        }],
        commandsAfterPC: ["run7zPC", (results, done) => {
            execCommands([
                'mv -f "' + config.db_path + 'ygosrv233-pre.zip" "' + file_path + '"'
            ], (err) => { 
                    if (!err) { 
                        sendResponse("电脑更新包打包完成。");
                    }
                    done(err);
            });
        }],
        commandsAfterMobile: ["run7zPC", "run7zMobile", (results, done) => {
            execCommands([
                'mv -f "' + config.db_path +'ygosrv233-pre-mobile.zip" "'+ file_path +'"',
                'rm -rf "' + config.db_path +'expansions/' + config.ypk_name + '"',
                'rm -rf "' + config.db_path +'expansions/script"',
                'rm -rf "' + config.db_path +'expansions/pics"'
            ], (err) => { 
                    if (!err) { 
                        sendResponse("手机更新包打包完成。");
                    }
                    done(err);
            });
        }],
        commandsAfterPro2: ["run7zPro2", (results, done) => {
            execCommands([
                'mv -f "' + config.db_path + 'ygosrv233-pre-2.zip" "' + file_path + '"',
                'rm -rf "' + config.db_path +'cdb"',
                'rm -rf "' + config.db_path +'picture"'
            ], (err) => { 
                    if (!err) { 
                        sendResponse("Pro2更新包打包完成。");
                    }
                    done(err);
            });
        }]
    }, callback);
}

//建立一个http服务器，接收API操作
async function requestListener(req, res) {
    var u = url.parse(req.url, true);
    
    if (!await auth.auth(u.query.username, u.query.password, "pre_dashboard", "pre_dashboard")) {
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
        await util.promisify(loadAllDbs)();
    }
    else if (u.pathname === '/api/fetch_datas') {
        res.writeHead(200);
        res.end(u.query.callback+'({"message":"开始更新数据库。"});');
        fetchDatas();
    }
    else if (u.pathname === '/api/push_datas') {
        res.writeHead(200);
        res.end(u.query.callback + '({"message":"开始上传数据。"});');
        await util.promisify(pushDatas)();
    }
    else if (u.pathname === '/api/write_to_file') {
        res.writeHead(200);
        res.end(u.query.callback+'({"message":"开始写列表页。"});');
        await util.promisify(writeToFile)(u.query.message);
    }
    else if (u.pathname === '/api/copy_to_ygopro') {
        res.writeHead(200);
        res.end(u.query.callback+'({"message":"开始更新到服务器。"});');
        await util.promisify(copyToYGOPRO)();
    }
    else if (u.pathname === '/api/pack_data') {
        res.writeHead(200);
        res.end(u.query.callback+'({"message":"开始生成更新包。"});');
        await util.promisify(packDatas)();
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
