/*
 ygopro-pre.js
 ygopro pre-release cards util
 Author: mercury233
 License: MIT
 
 不带参数运行时，会建立一个服务器，调用API执行对应操作
 TODO：带参数运行时执行对应操作后退出
*/
var http = require('http');
var sqlite3 = require('sqlite3').verbose();
var fs = require('fs');
var execSync = require('child_process').execSync;

var constants = require('./constants.json');
var config = require('./config.json').modules.pre;

//全卡HTML列表
var cardHTMLs=[];
//http长连接
var responder;

//输出反馈信息，如有http长连接则输出到http，否则输出到控制台
var sendResponse = function(text) {
    if (responder) {
        responder.write("data: " + text + "\n\n");
    }
    else {
        console.log(text);
    }
}

//读取数据库内内容到cardHTMLs，异步
var loadDb = function(db_file) {
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
            
            cardHTML+='<td><a href="'+ config.html_img_rel_path + result.id +'.jpg" target="_blank"><img src="'+config.html_img_rel_path+'thumbnail/'+ result.id +'.jpg" alt="'+ result.name +'"></a></td>';
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
                if (result.race & constants.RACES.RACE_PYRO) {cardRace="念动力";}
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
                if (result.race & constants.RACES.RACE_PHANTOMDRAGON) {cardRace="幻龙";}
                cardText+=" "+ cardRace;
                
                var cardAttr="";
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_EARTH) {cardAttr="地";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_WATER) {cardAttr="水";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_FIRE) {cardAttr="炎";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_WIND) {cardAttr="风";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_LIGHT) {cardAttr="光";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_DARK) {cardAttr="暗";}
                if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_DEVINE) {cardAttr="神";}
                cardText+="/"+ cardAttr +"\r\n";
            
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
                cardText+="[" + (new Array(cardLevel + 1)).join("★") + "]";
                
                cardText+=" " + result.atk + "/" + result.def;
                
                if (cardLScale) {
                    cardText+="  " + cardLScale + "/" +cardRScale;
                }
                
                cardText+="\r\n";
            }
            else {
                cardText+="\r\n";
            }
            cardText+=result.desc;
            
            cardHTML+='<td>'+ cardText.replace(/\r\n/g,"<br>") +'</td>';
            cardHTML+='</tr>';
            
            cardHTMLs.push(cardHTML);
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

//将cardHTMLs中内容更新到指定列表页，同步
var writeToFile = function() {
    var fileContent=fs.readFileSync(config.html_path+config.html_filename, {"encoding":"utf-8"});
    var newContent=cardHTMLs.join("\r\n");
    fileContent=fileContent.replace(/<tbody class="auto-generated">[\w\W]*<\/tbody>/,'<tbody class="auto-generated">\r\n'+newContent+'\r\n</tbody>');
    fs.writeFileSync(config.html_path+config.html_filename, fileContent);
    sendResponse("列表更新完成。");
}

//读取指定文件夹里所有数据库，异步
var loadAllDbs = function() {
    var files = fs.readdirSync(config.db_path+"expansions/");
    for (var i in files) {
        var filename = files[i];
        if (filename.slice(-4) === ".cdb") {
            loadDb(config.db_path+"expansions/"+filename);
        }
    }
}

//将数据库文件夹里卡图复制到列表页对应文件夹里
var copyImages = function() {
    execSync('rm -rf "' + config.html_path+config.html_img_rel_path +'"');
    execSync('cp -r "' + config.db_path + 'pics' + '" "' + config.html_path+config.html_img_rel_path + '"');
    sendResponse("卡图复制完成。");
}

//建立一个http服务器，接收API操作
http.createServer(function (req, res) {
    if(req.url === '/api/msg') {
        res.writeHead(200, {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive"
        });
        
        res.on("close", function(){
            responder = null;
        });
        
        responder = res;
    }
    else if (req.url === '/api/load_db') {
        loadAllDbs();
        res.writeHead(200);
        res.end("开始加载数据库。");
    }
    else if (req.url === '/api/write_to_file') {
        writeToFile();
        res.writeHead(200);
        res.end("开始写列表页。");
    }
    else if (req.url === '/api/copy_images') {
        copyImages();
        res.writeHead(200);
        res.end("开始复制卡图。");
    }
    else {
        res.writeHead(404);
        res.end("no");
    }

}).listen(config.port);

