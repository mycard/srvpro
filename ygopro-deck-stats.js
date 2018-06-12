/*
 ygopro-deck-stats.js
 get card usage from decks
 Author: mercury233
 License: MIT
 
 读取指定文件夹里所有卡组，得出卡片使用量，生成csv
*/
var sqlite3 = require('sqlite3').verbose();
var fs = require('fs');
var loadJSON = require('load-json-file').sync;
var config = loadJSON('./config/deckstats.json'); //{ "deckpath": "../decks", "dbfile": "cards.cdb" }
var constants = loadJSON('./data/constants.json');

var ALL_MAIN_CARDS={};
var ALL_SIDE_CARDS={};
var ALL_CARD_DATAS={};

function add_to_deck(deck,id) {
    if (deck[id]) {
        deck[id]=deck[id]+1;
    }
    else {
        deck[id]=1;
    }
}

function add_to_all_list(LIST,id,use) {
    if (!ALL_CARD_DATAS[id]) {
        return;
    }
    if (ALL_CARD_DATAS[id].alias) {
        id=ALL_CARD_DATAS[id].alias;
    }
    if (!LIST[id]) {
        LIST[id]={"use1":0, "use2":0, "use3":0};
    }
    if (use==1) {
        LIST[id].use1=LIST[id].use1+1;
    }
    else if (use==2) {
        LIST[id].use2=LIST[id].use2+1;
    }
    else {
        LIST[id].use3=LIST[id].use3+1;
    }
}

function read_deck_file(filename) {
    console.log("reading "+filename);
    var deck_text=fs.readFileSync(config.deckpath+"/"+filename,{encoding:"ASCII"})
    var deck_array=deck_text.split("\n");
    var deck_main={};
    var deck_side={};
    var current_deck=deck_main;
    for (var i in deck_array) {
        if (deck_array[i].indexOf("!side")>=0)
            current_deck=deck_side;
        var card=parseInt(deck_array[i]);
        if (!isNaN(card)) {
            add_to_deck(current_deck,card);
        }
    }
    for (var i in deck_main) {
        add_to_all_list(ALL_MAIN_CARDS,i,deck_main[i]);
    }
    for (var i in deck_side) {
        add_to_all_list(ALL_SIDE_CARDS,i,deck_side[i]);
    }
}

function load_database(callback) {
    var db=new sqlite3.Database(config.dbfile);
    db.each("select * from datas,texts where datas.id=texts.id", function (err,result) {
        if (err) {
            console.log(config.dbfile + ":" + err);
            return;
        }
        else {
            if (result.type & constants.TYPES.TYPE_TOKEN) {
                return;
            }
            
            var card={};
            
            card.name=result.name;
            card.alias=result.alias;
            
            if (result.type & constants.TYPES.TYPE_MONSTER) {
                if ((result.type & constants.TYPES.TYPE_FUSION) || (result.type & constants.TYPES.TYPE_SYNCHRO) || (result.type & constants.TYPES.TYPE_XYZ) || (result.type & constants.TYPES.TYPE_LINK))
                    card.type="额外";
                else
                    card.type="怪兽";
            }
            if (result.type & constants.TYPES.TYPE_SPELL){
                card.type="魔法";
            }
            if (result.type & constants.TYPES.TYPE_TRAP){
                card.type="陷阱";
            }
            
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
            if (result.type & constants.TYPES.TYPE_LINK) {cardTypes.push("连接");}
            card.fulltype=cardTypes.join('|');
            
            if (result.type & constants.TYPES.TYPE_MONSTER) {
                if (result.level<=12) {
                    card.level=result.level;
                }
                else { //转化为16位，0x01010004，前2位是左刻度，2-4是右刻度，末2位是等级
                    var levelHex=parseInt(result.level, 10).toString(16);
                    card.level=parseInt(levelHex.slice(-2), 16);
                    card.LScale=parseInt(levelHex.slice(-8,-6), 16);
                    //card.RScale=parseInt(levelHex.slice(-6,-4), 16);
                }
            }
            
            ALL_CARD_DATAS[result.id]=card;
        }
    }, callback);
}

function read_decks() {
    var ALL_DECKS=fs.readdirSync(config.deckpath);

    for (var i in ALL_DECKS) {
        var filename=ALL_DECKS[i];
        if (filename.indexOf(".ydk")>0) {
            read_deck_file(filename);
        }
    }
    output_csv(ALL_MAIN_CARDS,"main.csv");
    var ALL_SIDE_CARDS_isempty = true;
    for (var j in ALL_SIDE_CARDS) {
        ALL_SIDE_CARDS_isempty = false;
        break;
    }
    if (!ALL_SIDE_CARDS_isempty) {
        output_csv(ALL_SIDE_CARDS,"side.csv");
    }
}

function output_csv(list,filename) {
    //console.log(JSON.stringify(list));
    var file=fs.openSync(filename,"w");
    for (var i in list) {
        var card=ALL_CARD_DATAS[i];
        if (!card) {
            continue;
        }
        var card_usage=list[i];
        
        console.log("writing "+card.name);
        
        var line=[];
        line.push(card.name);
        line.push(card.type);
        line.push(card.fulltype);
        //line.push(card.level ? card.level : "");
        //line.push(card.LScale ? card.LScale : "");
        line.push(card_usage.use1+card_usage.use2+card_usage.use3);
        line.push(card_usage.use1);
        line.push(card_usage.use2);
        line.push(card_usage.use3);
        var linetext="\""+line.join("\",\"")+"\"\r\n";
        fs.writeSync(file,linetext);
    }
}

load_database(read_decks);

