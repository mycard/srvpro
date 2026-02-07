/*
 ygopro-tournament.ts
 ygopro tournament util
 Author: mercury233
 License: MIT

 不带参数运行时，会建立一个服务器，调用API执行对应操作
*/
import * as http from "http";
import * as https from "https";
import * as fs from "fs";
import * as url from "url";
import axios from "axios";
import * as formidable from "formidable";
import { sync as loadJSON } from "load-json-file";
import defaultConfig from "./data/default_config.json";
import { Challonge } from "./challonge";
import YGOProDeckEncode from "ygopro-deck-encode";
import * as auth from "./ygopro-auth";
import _ from "underscore";

type Settings = typeof defaultConfig;
const settings = loadJSON("./config/config.json") as Settings;
const config = settings.modules.tournament_mode;
const challonge_config = settings.modules.challonge;
const challonge = new Challonge(challonge_config);
const ssl_config = settings.modules.http.ssl;

//http长连接
let responder: http.ServerResponse | null;

let wallpapers: Array<{ url: string; desc: string }> = [{ url: "", desc: "" }];
axios
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
    } else if (!body) {
      console.log("wallpapers error", null, response);
    } else {
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
const sendResponse = function (text: string) {
  text = "" + text;
  if (responder) {
    text = text.replace(/\n/g, "<br>");
    responder.write("data: " + text + "\n\n");
  } else {
    console.log(text);
  }
};

//读取指定卡组
const readDeck = async function (deck_name: string, deck_full_path: string) {
  const deck_text = await fs.promises.readFile(deck_full_path, { encoding: "utf-8" });
  const deck = YGOProDeckEncode.fromYdkString(deck_text);
  deck.name = deck_name;
  return deck;
};

//读取指定文件夹中所有卡组
const getDecks = async function (callback: (err: Error | null, decks: any[]) => void) {
  try {
    const decks: any[] = [];
    const decks_list = await fs.promises.readdir(config.deck_path);
    for (const deck_name of decks_list) {
      if (deck_name.endsWith(".ydk")) {
        const deck = await readDeck(deck_name, config.deck_path + deck_name);
        decks.push(deck);
      }
    }
    callback(null, decks);
  } catch (err) {
    callback(err as Error, []);
  }
};

const delDeck = function (deck_name: string, callback: (err?: NodeJS.ErrnoException | null) => void) {
  if (deck_name.startsWith("../") || deck_name.match(/\/\.\.\//)) {
    //security issue
    callback(new Error("Invalid deck"));
  }
  fs.unlink(config.deck_path + deck_name, callback);
};

const clearDecks = async function (callback: (err?: Error | null) => void) {
  try {
    const decks_list = await fs.promises.readdir(config.deck_path);
    for (const deck_name of decks_list) {
      await new Promise<void>((resolve, reject) => {
        delDeck(deck_name, (err) => (err ? reject(err) : resolve()));
      });
    }
    callback(null);
  } catch (err) {
    callback(err as Error);
  }
};

const UploadToChallonge = async function () {
  if (!challonge_config.enabled) {
    sendResponse("未开启Challonge模式。");
    return false;
  }
  sendResponse("开始读取玩家列表。");
  const decks_list = fs.readdirSync(config.deck_path);
  const player_list: Array<{ name: string; deckbuf: string }> = [];
  for (const k in decks_list) {
    const deck_name = decks_list[k];
    if (deck_name.endsWith(".ydk")) {
      player_list.push({
        name: deck_name.slice(0, deck_name.length - 4),
        deckbuf: Buffer.from(
          YGOProDeckEncode.fromYdkString(
            await fs.promises.readFile(config.deck_path + deck_name, { encoding: "utf-8" })
          ).toUpdateDeckPayload()
        ).toString("base64"),
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
    for (const chunk of _.chunk(player_list, 10)) {
      sendResponse(`开始上传玩家 ${chunk.map((c) => c.name).join(", ")} 至 Challonge。`);
      await challonge.uploadParticipants(chunk);
    }
    sendResponse("玩家列表上传完成。");
  } catch (e: any) {
    sendResponse("Challonge 上传失败：" + e.message);
  }
  return true;
};

const receiveDecks = async function (
  files: any,
  callback: (err: Error | null, result: Array<{ file: string; status: string }>) => void
) {
  try {
    const result: Array<{ file: string; status: string }> = [];
    for (const file of files) {
      if (file.name.endsWith(".ydk")) {
        const deck = await readDeck(file.name, file.path);
        if (deck.main.length >= 40) {
          fs.createReadStream(file.path).pipe(fs.createWriteStream(config.deck_path + file.name));
          result.push({
            file: file.name,
            status: "OK",
          });
        } else {
          result.push({
            file: file.name,
            status: "卡组不合格",
          });
        }
      } else {
        result.push({
          file: file.name,
          status: "不是卡组文件",
        });
      }
    }
    callback(null, result);
  } catch (err) {
    callback(err as Error, []);
  }
};

//建立一个http服务器，接收API操作
async function requestListener(req: http.IncomingMessage, res: http.ServerResponse) {
  const base = `http://${req.headers.host || "localhost"}`;
  const urlObj = new URL(req.url || "/", base);
  const u = {
    pathname: urlObj.pathname,
    query: Object.fromEntries(urlObj.searchParams),
  };

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
    if (!(await auth.auth(u.query.username as string, u.query.password as string, "deck_dashboard_write", "upload_deck"))) {
      res.writeHead(403);
      res.end("Auth Failed.");
      return;
    }
    const form = new (formidable as any).IncomingForm();
    form.parse(req, function (err: Error | null, fields: any, files: any) {
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
  } else if (u.pathname === "/api/msg") {
    if (!(await auth.auth(u.query.username as string, u.query.password as string, "deck_dashboard_read", "login_deck_dashboard"))) {
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
  } else if (u.pathname === "/api/get_bg") {
    if (!(await auth.auth(u.query.username as string, u.query.password as string, "deck_dashboard_read", "login_deck_dashboard"))) {
      res.writeHead(403);
      res.end("Auth Failed.");
      return;
    }
    res.writeHead(200);
    res.end(
      u.query.callback + "(" + JSON.stringify(wallpapers[Math.floor(Math.random() * wallpapers.length)]) + ");"
    );
  } else if (u.pathname === "/api/get_decks") {
    if (!(await auth.auth(u.query.username as string, u.query.password as string, "deck_dashboard_read", "get_decks"))) {
      res.writeHead(403);
      res.end("Auth Failed.");
      return;
    }
    getDecks((err, decks) => {
      if (err) {
        res.writeHead(500);
        res.end(u.query.callback + "(" + err.toString() + ");");
      } else {
        res.writeHead(200);
        res.end(u.query.callback + "(" + JSON.stringify(decks) + ");");
      }
    });
  } else if (u.pathname === "/api/del_deck") {
    if (!(await auth.auth(u.query.username as string, u.query.password as string, "deck_dashboard_write", "delete_deck"))) {
      res.writeHead(403);
      res.end("Auth Failed.");
      return;
    }
    res.writeHead(200);
    delDeck(u.query.msg as string, (err) => {
      let result;
      if (err) {
        result = "删除卡组 " + u.query.msg + "失败: " + err.toString();
      } else {
        result = "删除卡组 " + u.query.msg + "成功。";
      }
      res.writeHead(200);
      res.end(u.query.callback + '("' + result + '");');
    });
  } else if (u.pathname === "/api/clear_decks") {
    if (!(await auth.auth(u.query.username as string, u.query.password as string, "deck_dashboard_write", "clear_decks"))) {
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
      res.end(u.query.callback + '("' + result + '");');
    });
  } else if (u.pathname === "/api/upload_to_challonge") {
    if (!(await auth.auth(u.query.username as string, u.query.password as string, "deck_dashboard_write", "upload_to_challonge"))) {
      res.writeHead(403);
      res.end("Auth Failed.");
      return;
    }
    res.writeHead(200);
    await UploadToChallonge();
    res.end(u.query.callback + '("操作完成。");');
  } else {
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
} else {
  http.createServer(requestListener).listen(config.port);
}
