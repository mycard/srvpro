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
var fse = require('fs-extra');
var path = require('path');
var spawn = require('child_process').spawn;
var url = require('url');
var moment = require('moment');
moment.locale('zh-cn');
var loadJSON = require('load-json-file').sync;

var auth = require('./ygopro-auth.js');

var constants = loadJSON('./data/constants.json');

var settings = loadJSON('./config/config.json');
config = settings.modules.pre_util;
ssl_config = settings.modules.http.ssl;

//全卡HTML列表
var cardHTMLs = [];
//http长连接
var responder;
//URL里的更新时间戳
var dataver = moment().format("YYYYMMDDHHmmss");

//输出反馈信息，如有http长连接则输出到http，否则输出到控制台
function sendResponse(data) {
    let text = data.toString();
    if (responder) {
        text = text.replace(/\r?\n/g, "<br>");
        responder.write("data: " + text + "\n\n");
    }
    else {
        console.log(text);
    }
}

async function runCommand(cmd, params, cwd, output = () => { },
    fail = (code, cmd, params) => { sendResponse(`运行命令出错：${code} ${cmd} ${params.join(' ')}`); }) {
    return new Promise((resolve, reject) => {
        let proc = spawn(cmd, params, { cwd: cwd, env: process.env });
        proc.stdout.setEncoding('utf8');
        proc.stdout.on('data', (data) => { output(data); });
        proc.stderr.setEncoding('utf8');
        proc.stderr.on('data', (data) => { output(data); });
        proc.on('close', (code) => { if (code == 0) { resolve(); } else { fail(code, cmd, params); reject(); } });
    });
}

//读取数据库内内容到cardHTMLs
async function loadDb(db_file) {
    var db = new sqlite3.Database(db_file);

    await new Promise((resolve) => {
        db.each("select * from datas,texts where datas.id=texts.id", function (err, result) {
            if (err) {
                sendResponse(db_file + ":" + err);
                return;
            }
            else {
                if (result.type & constants.TYPES.TYPE_TOKEN) {
                    return;
                }

                var cardHTML = "<tr>";

                cardHTML += `
<td><a href="${config.html_img_rel_path + result.id}.jpg" target="_blank">
    <img data-original="${config.html_img_rel_path + config.html_img_thumbnail + result.id}.jpg${config.html_img_thumbnail_suffix}" alt="${result.name}">
</a></td>\n`;
                cardHTML += '<td>' + result.name + '</td>\n';

                var cardText = "";

                var cardTypes = [];
                if (result.type & constants.TYPES.TYPE_MONSTER) { cardTypes.push("怪兽"); }
                if (result.type & constants.TYPES.TYPE_SPELL) { cardTypes.push("魔法"); }
                if (result.type & constants.TYPES.TYPE_TRAP) { cardTypes.push("陷阱"); }
                if (result.type & constants.TYPES.TYPE_NORMAL) { cardTypes.push("通常"); }
                if (result.type & constants.TYPES.TYPE_EFFECT) { cardTypes.push("效果"); }
                if (result.type & constants.TYPES.TYPE_FUSION) { cardTypes.push("融合"); }
                if (result.type & constants.TYPES.TYPE_RITUAL) { cardTypes.push("仪式"); }
                if (result.type & constants.TYPES.TYPE_TRAPMONSTER) { cardTypes.push("陷阱怪兽"); }
                if (result.type & constants.TYPES.TYPE_SPIRIT) { cardTypes.push("灵魂"); }
                if (result.type & constants.TYPES.TYPE_UNION) { cardTypes.push("同盟"); }
                if (result.type & constants.TYPES.TYPE_DUAL) { cardTypes.push("二重"); }
                if (result.type & constants.TYPES.TYPE_TUNER) { cardTypes.push("调整"); }
                if (result.type & constants.TYPES.TYPE_SYNCHRO) { cardTypes.push("同调"); }
                if (result.type & constants.TYPES.TYPE_TOKEN) { cardTypes.push("衍生物"); }
                if (result.type & constants.TYPES.TYPE_QUICKPLAY) { cardTypes.push("速攻"); }
                if (result.type & constants.TYPES.TYPE_CONTINUOUS) { cardTypes.push("永续"); }
                if (result.type & constants.TYPES.TYPE_EQUIP) { cardTypes.push("装备"); }
                if (result.type & constants.TYPES.TYPE_FIELD) { cardTypes.push("场地"); }
                if (result.type & constants.TYPES.TYPE_COUNTER) { cardTypes.push("反击"); }
                if (result.type & constants.TYPES.TYPE_FLIP) { cardTypes.push("反转"); }
                if (result.type & constants.TYPES.TYPE_TOON) { cardTypes.push("卡通"); }
                if (result.type & constants.TYPES.TYPE_XYZ) { cardTypes.push("超量"); }
                if (result.type & constants.TYPES.TYPE_PENDULUM) { cardTypes.push("灵摆"); }
                if (result.type & constants.TYPES.TYPE_SPSUMMON) { cardTypes.push("特殊召唤"); }
                if (result.type & constants.TYPES.TYPE_LINK) { cardTypes.push("连接"); }
                cardText += "[" + cardTypes.join('|') + "]";

                if (result.type & constants.TYPES.TYPE_MONSTER) {
                    var cardRace = "";
                    if (result.race & constants.RACES.RACE_WARRIOR) { cardRace = "战士"; }
                    if (result.race & constants.RACES.RACE_SPELLCASTER) { cardRace = "魔法师"; }
                    if (result.race & constants.RACES.RACE_FAIRY) { cardRace = "天使"; }
                    if (result.race & constants.RACES.RACE_FIEND) { cardRace = "恶魔"; }
                    if (result.race & constants.RACES.RACE_ZOMBIE) { cardRace = "不死"; }
                    if (result.race & constants.RACES.RACE_MACHINE) { cardRace = "机械"; }
                    if (result.race & constants.RACES.RACE_AQUA) { cardRace = "水"; }
                    if (result.race & constants.RACES.RACE_PYRO) { cardRace = "炎"; }
                    if (result.race & constants.RACES.RACE_ROCK) { cardRace = "岩石"; }
                    if (result.race & constants.RACES.RACE_WINDBEAST) { cardRace = "鸟兽"; }
                    if (result.race & constants.RACES.RACE_PLANT) { cardRace = "植物"; }
                    if (result.race & constants.RACES.RACE_INSECT) { cardRace = "昆虫"; }
                    if (result.race & constants.RACES.RACE_THUNDER) { cardRace = "雷"; }
                    if (result.race & constants.RACES.RACE_DRAGON) { cardRace = "龙"; }
                    if (result.race & constants.RACES.RACE_BEAST) { cardRace = "兽"; }
                    if (result.race & constants.RACES.RACE_BEASTWARRIOR) { cardRace = "兽战士"; }
                    if (result.race & constants.RACES.RACE_DINOSAUR) { cardRace = "恐龙"; }
                    if (result.race & constants.RACES.RACE_FISH) { cardRace = "鱼"; }
                    if (result.race & constants.RACES.RACE_SEASERPENT) { cardRace = "海龙"; }
                    if (result.race & constants.RACES.RACE_REPTILE) { cardRace = "爬虫类"; }
                    if (result.race & constants.RACES.RACE_PSYCHO) { cardRace = "念动力"; }
                    if (result.race & constants.RACES.RACE_DEVINE) { cardRace = "幻神兽"; }
                    if (result.race & constants.RACES.RACE_CREATORGOD) { cardRace = "创造神"; }
                    if (result.race & constants.RACES.RACE_WYRM) { cardRace = "幻龙"; }
                    if (result.race & constants.RACES.RACE_CYBERS) { cardRace = "电子界"; }
                    cardText += " " + cardRace;

                    var cardAttr = "";
                    if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_EARTH) { cardAttr = "地"; }
                    if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_WATER) { cardAttr = "水"; }
                    if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_FIRE) { cardAttr = "炎"; }
                    if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_WIND) { cardAttr = "风"; }
                    if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_LIGHT) { cardAttr = "光"; }
                    if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_DARK) { cardAttr = "暗"; }
                    if (result.attribute & constants.ATTRIBUTES.ATTRIBUTE_DEVINE) { cardAttr = "神"; }
                    cardText += "/" + cardAttr + "\n";

                    var cardLevel;
                    var cardLScale;
                    var cardRScale;
                    if (result.level <= 12) {
                        cardLevel = result.level;
                    }
                    else { //转化为16位，0x01010004，前2位是左刻度，2-4是右刻度，末2位是等级
                        var levelHex = parseInt(result.level, 10).toString(16);
                        cardLevel = parseInt(levelHex.slice(-2), 16);
                        cardLScale = parseInt(levelHex.slice(-8, -6), 16);
                        cardRScale = parseInt(levelHex.slice(-6, -4), 16);
                    }

                    if (!(result.type & constants.TYPES.TYPE_LINK)) {
                        cardText += "[" + ((result.type & constants.TYPES.TYPE_XYZ) ? "☆" : "★") + cardLevel + "]";
                        cardText += " " + (result.atk < 0 ? "?" : result.atk) + "/" + (result.def < 0 ? "?" : result.def);
                    }
                    else {
                        cardText += "[LINK-" + cardLevel + "]";
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
                        cardText += "  " + cardLScale + "/" + cardRScale;
                    }

                    cardText += "\n";
                }
                else {
                    cardText += "\n";
                }
                cardText += result.desc;

                cardHTML += '<td>' + cardText.replace(/\r?\n/g, "<br>") + '</td>\n';
                cardHTML += '</tr>';

                cardHTMLs.push(cardHTML);
            }
        }, function (err, num) {
            if (err) {
                sendResponse(db_file + ":" + err);
            }
            else {
                sendResponse(`已加载数据库${db_file}，共${num}张卡。`);
            }
            db.close();
            resolve();
        });
    });
}

//将cardHTMLs中内容更新到指定列表页
async function writeToFile(message) {
    let htmlfile = path.join(config.html_path, config.html_filename);
    let fileContent = fse.readFileSync(htmlfile, { "encoding": "utf-8" });

    let newContent = cardHTMLs.join("\n");
    fileContent = fileContent.replace(/<tbody class="auto-generated">[\w\W]*<\/tbody>/, '<tbody class="auto-generated">\n' + newContent + '\n</tbody>');

    //fileContent = fileContent.replace(/data-ygosrv233-download="(http.+)" href="http.+"/g, 'data-ygosrv233-download="$1" href="$1"');
    //fileContent = fileContent.replace(/href="(http.+)dataver/g, 'href="$1' + dataver);
    fileContent = fileContent.replace(/\$dataver="\d+/, '$dataver="' + dataver);

    if (message) {
        message = "<li>" + moment().format('L HH:mm') + "<ul><li>" + message.split("！换行符！").join("</li><li>") + "</li></ul></li>";
        fileContent = fileContent.replace(/<ul class="auto-generated">/, '<ul class="auto-generated">\n' + message);
    }

    await fse.writeFile(htmlfile, fileContent);

    if (!config.cdn.enabled) {
        let html_img_rel_path = path.join(config.html_path, config.html_img_rel_path);
        await fse.remove(html_img_rel_path);
        await fse.copy(path.join(config.db_path, "pics"), html_img_rel_path);
        await fse.remove(path.join(html_img_rel_path, "field"));
        sendResponse("卡图复制完成。");
    }

    sendResponse("列表更新完成。");
}

//读取指定文件夹里所有数据库
async function loadAllDbs() {
    cardHTMLs = [];
    let db_path = path.join(config.db_path, "expansions");
    let files = fse.readdirSync(db_path).filter((filename) => {
        return filename.slice(-4) === ".cdb" && (!config.only_show_dbs || config.only_show_dbs.length == 0 || config.only_show_dbs[filename])
    });
    await Promise.all(files.map(async (filename) => {
        await loadDb(path.join(db_path, filename));
    }));
    dataver = moment().format("YYYYMMDDHHmmss");
}

//从远程更新数据库
async function fetchDatas() {
    await runCommand("git", ["pull", "origin", "master"], config.git_db_path, (data) => { sendResponse("git pull: " + data); });
    sendResponse("数据更新完成。");
    await runCommand("git", ["pull", "origin", "master"], config.git_html_path, (data) => { sendResponse("git pull: " + data); });
    sendResponse("网页同步完成。");
    return;
}

//更新本地网页到服务器
async function pushDatas() {
    if (config.cdn.enabled) {
        await uploadCDN(config.cdn.local, config.cdn.remote);
        await uploadCDN(path.join(config.db_path, "pics"), path.join(config.cdn.pics_remote, "pics"));
        if (config.cdn.script) {
            sendResponse("开始执行CDN脚本。");
            await runCommand("bash", [config.cdn.script], ".", (data) => { sendResponse("CDN: " + data); });
            sendResponse("CDN脚本执行完成。");
        }
    }
    sendResponse("CDN上传全部完成。");
    await pushHTMLs();
}

async function pushHTMLs() {
    sendResponse("开始上传到网页。");
    try {
        await runCommand("git", ["add", "--all", "."], config.git_html_path);
        await runCommand("git", ["commit", "-m", "update-auto"], config.git_html_path);
    }
    catch (error) {
        sendResponse("git error: " + error);
    }

    for (var i in config.html_gits) {
        var git = config.html_gits[i];
        await runCommand("git", git.push, config.git_html_path, (data) => { sendResponse(git.name + " git push: " + data); });
        sendResponse(git.name + "上传完成。");
    }
}

//上传到CDN
async function uploadCDN(local, remote) {
    sendResponse("CDN " + remote + " 开始上传。");
    var params = config.cdn.params.slice(0);
    params.push(local);
    params.push(remote);

    await runCommand(config.cdn.exe, params, ".", (data) => { sendResponse("CDN " + remote + " : " + data); });
    sendResponse("CDN " + remote + " 上传完成。");
}

//将数据库文件夹复制到YGOPro文件夹里
async function copyToYGOPro() {
    await fse.remove(path.join(config.ygopro_path, "expansions"));
    await fse.copy(path.join(config.db_path, "expansions"), path.join(config.ygopro_path, "expansions"));
    await fse.copy(path.join(config.db_path, "script"), path.join(config.ygopro_path, "expansions", "script"));
    let lflistfile = path.join(config.db_path, "lflist.conf");
    if (fse.existsSync(lflistfile)) {
        await fse.copy(lflistfile, path.join(config.ygopro_path, "expansions", "lflist.conf"));
    }
    sendResponse("服务器更新完成。");
}

//生成更新包
async function packDatas() {
    file_path = config.html_path;
    if (config.cdn.enabled) {
        file_path = config.cdn.local + '/' + dataver;
        let olddirs = fse.readdirSync(config.cdn.local).filter((filename) => { return filename.match(/^\d+$/); }).sort();
        if (olddirs.length > 0) {
            olddirs.pop(); // keep the latest version
        }
        for (let i in olddirs) {
            await fse.remove(path.join(config.cdn.local, olddirs[i]));
        }
    }

    await fse.remove(path.join(config.db_path, "expansions", config.ypk_name));
    await fse.remove(path.join(config.db_path, "expansions", "script"));
    await fse.remove(path.join(config.db_path, "expansions", "pics"));
    await fse.remove(path.join(config.db_path, "expansions", "pack"));
    await fse.remove(path.join(config.db_path, "cdb"));
    await fse.remove(path.join(config.db_path, "picture"));

    await fse.copy(path.join(config.db_path, "pics"), path.join(config.db_path, "expansions", "pics"));
    await fse.copy(path.join(config.db_path, "field"), path.join(config.db_path, "expansions", "pics", "field"));
    await fse.copy(path.join(config.db_path, "script"), path.join(config.db_path, "expansions", "script"));
    await fse.copy(path.join(config.db_path, "deck"), path.join(config.db_path, "expansions", "pack"));

    //await fse.copy(path.join(config.db_path, "expansions"), path.join(config.db_path, "cdb"));
    //await fse.copy(path.join(config.db_path, "pics"), path.join(config.db_path, "picture", "card"));
    //await fse.copy(path.join(config.db_path, "field"), path.join(config.db_path, "picture", "field"));

    await fse.ensureDir(file_path);

    await runCommand(settings.modules.archive_tool,
        ["a", "-tzip", "-x!*.ypk", "-x!pics/field/.gitkeep",
            config.ypk_name, "*"],
        path.join(config.db_path, "expansions"));
    sendResponse("YPK打包完成。");

    /*
    await runCommand(settings.modules.archive_tool,
        ["a", "-x!*.zip", "-x!.git", "-x!LICENSE", "-x!README.md", "-x!.gitlab-ci.yml",
            "-x!cdb", "-x!picture", "-x!field", "-x!script", "-x!pics",
            "-x!expansions/pics", "-x!expansions/script", "-x!expansions/pack", "-x!expansions/*.cdb", "-x!expansions/*.conf",
            "ygosrv233-pre-2.zip", "*"],
        config.db_path);
    sendResponse("Pro2压缩包打包完成。");
    */

    //await fse.remove(path.join(config.db_path, "cdb"));
    //await fse.remove(path.join(config.db_path, "picture"));

    await runCommand(settings.modules.archive_tool,
        ["a", "-x!*.zip", "-x!.git", "-x!LICENSE", "-x!README.md", "-x!.gitlab-ci.yml",
            "-x!cdb", "-x!picture", "-x!field", "-x!script", "-x!pics",
            "-x!expansions/pics", "-x!expansions/script", "-x!expansions/pack", "-x!expansions/*.cdb", "-x!expansions/*.conf",
            "ygosrv233-pre.zip", "*"],
        config.db_path);
    sendResponse("电脑压缩包打包完成。");

    /*
    await runCommand(settings.modules.archive_tool,
        ["a", "-x!*.zip", "-x!.git", "-x!LICENSE", "-x!README.md", "-x!.gitlab-ci.yml",
            "-x!cdb", "-x!picture", "-x!field", "-x!script", "-x!pics",
            "-x!expansions/pics", "-x!expansions/script", "-x!expansions/pack", "-x!expansions/*.cdb", "-x!expansions/*.conf",
            "ygosrv233-pre-mobile.zip", "*"],
        config.db_path);
    sendResponse("手机压缩包打包完成。");
    */

    await fse.remove(path.join(config.db_path, "expansions", "script"));
    await fse.remove(path.join(config.db_path, "expansions", "pics"));
    await fse.remove(path.join(config.db_path, "expansions", "pack"));

    await fse.move(path.join(config.db_path, "ygosrv233-pre.zip"), path.join(file_path, "ygosrv233-pre.zip"), { overwrite: true });
    //await fse.move(path.join(config.db_path, "ygosrv233-pre-mobile.zip"), path.join(file_path, "ygosrv233-pre-mobile.zip"), { overwrite: true });
    //await fse.move(path.join(config.db_path, "ygosrv233-pre-2.zip"), path.join(file_path, "ygosrv233-pre-2.zip"), { overwrite: true });
    await fse.move(path.join(config.db_path, "expansions", config.ypk_name), path.join(file_path, config.ypk_name), { overwrite: true });
}

//建立一个http服务器，接收API操作
async function requestListener(req, res) {
    var u = url.parse(req.url, true);

    if (!await auth.auth(u.query.username, u.query.password, "pre_dashboard", "pre_dashboard")) {
        res.writeHead(403);
        res.end("Auth Failed.");
        return;
    }

    if (req.method == "OPTIONS") {
        res.writeHead(200, {
            "Access-Control-Allow-origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
            "Cache-Control": "no-cache"
        });
        res.end("");
        return;
    }

    if (u.pathname === '/api/msg') {
        res.writeHead(200, {
            "Access-Control-Allow-origin": "*",
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive"
        });

        res.on("close", function () {
            responder = null;
        });

        responder = res;

        sendResponse("已连接。");
    }
    else if (u.pathname === '/api/load_db') {
        res.writeHead(200);
        res.end(u.query.callback + '({"message":"开始加载数据库。"});');
        loadAllDbs();
    }
    else if (u.pathname === '/api/fetch_datas') {
        res.writeHead(200);
        res.end(u.query.callback + '({"message":"开始更新数据库。"});');
        fetchDatas();
    }
    else if (u.pathname === '/api/push_datas') {
        res.writeHead(200);
        res.end(u.query.callback + '({"message":"开始上传数据。"});');
        pushDatas();
    }
    else if (u.pathname === '/api/write_to_file') {
        res.writeHead(200);
        res.end(u.query.callback + '({"message":"开始写列表页。"});');
        writeToFile(u.query.message);
    }
    else if (u.pathname === '/api/copy_to_ygopro') {
        res.writeHead(200);
        res.end(u.query.callback + '({"message":"开始更新到服务器。"});');
        copyToYGOPro();
    }
    else if (u.pathname === '/api/pack_data') {
        res.writeHead(200);
        res.end(u.query.callback + '({"message":"开始生成更新包。"});');
        packDatas();
    }
    else {
        res.writeHead(400);
        res.end("400");
    }
}

if (ssl_config.enabled) {
    const ssl_cert = fse.readFileSync(ssl_config.cert);
    const ssl_key = fse.readFileSync(ssl_config.key);
    const options = {
        cert: ssl_cert,
        key: ssl_key
    }
    https.createServer(options, requestListener).listen(config.port);
} else {
    http.createServer(requestListener).listen(config.port);
}
