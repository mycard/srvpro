"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.update_user = exports.delete_user = exports.add_user = exports.auth = void 0;
/*
Main script of new dashboard account system.
The account list file is stored at `./config/admin_user.json`. The users are stored at `users`.
The key is the username. The `permissions` field could be a string, using a permission set from the example, or an object, to define a specific set of permissions.
eg. An account for a judge could be as follows, to use the default permission of judges,
    "username": {
      "password": "123456",
      "enabled": true,
      "permissions": "judge"
    },
or as follows, to use a specific set of permissions.
    "username": {
      "password": "123456",
      "enabled": true,
      "permissions": {
        "get_rooms": true,
        "duel_log": true,
        "download_replay": true,
        "deck_dashboard_read": true,
        "deck_dashboard_write": true,
        "shout": true,
        "kick_user": true,
        "start_death": true
      }
    },
*/
const fs_1 = __importDefault(require("fs"));
const load_json_file_1 = require("load-json-file");
const load_json_file_2 = __importDefault(require("load-json-file"));
const moment_1 = __importDefault(require("moment"));
const bunyan_1 = __importDefault(require("bunyan"));
moment_1.default.updateLocale("zh-cn", {
    relativeTime: {
        future: "%s内",
        past: "%s前",
        s: "%d秒",
        m: "1分钟",
        mm: "%d分钟",
        h: "1小时",
        hh: "%d小时",
        d: "1天",
        dd: "%d天",
        M: "1个月",
        MM: "%d个月",
        y: "1年",
        yy: "%d年",
    },
});
const log = bunyan_1.default.createLogger({ name: "auth" });
if (!fs_1.default.existsSync("./logs")) {
    fs_1.default.mkdirSync("./logs");
}
const add_log = async function (message) {
    const mt = (0, moment_1.default)();
    log.info(message);
    const text = mt.format("YYYY-MM-DD HH:mm:ss") + " --> " + message + "\n";
    let res = false;
    try {
        await fs_1.default.promises.appendFile(`./logs/${mt.format("YYYY-MM-DD")}.log`, text);
        res = true;
    }
    catch {
        res = false;
    }
    return res;
};
const default_data = (0, load_json_file_1.sync)("./data/default_data.json");
const setting_save = async function (settings) {
    try {
        await fs_1.default.promises.writeFile(settings.file, JSON.stringify(settings, null, 2));
    }
    catch (e) {
        add_log("save fail");
    }
};
let users;
try {
    users = (0, load_json_file_1.sync)("./config/admin_user.json");
}
catch {
    users = default_data.users;
    setting_save(users);
}
const save = async function () {
    await setting_save(users);
};
const reload = async function () {
    const user_backup = users;
    try {
        users = (await (0, load_json_file_2.default)("./config/admin_user.json"));
    }
    catch {
        users = user_backup;
        await add_log("Invalid user data JSON");
    }
};
const check_permission = async function (user, permission_required) {
    const _permission = user.permissions;
    let permission;
    if (typeof _permission !== "object") {
        permission = users.permission_examples[_permission];
    }
    else {
        permission = _permission;
    }
    if (!permission) {
        await add_log("Permision not set:" + String(_permission));
        return false;
    }
    return Boolean(permission[permission_required]);
};
const auth = async function (name, pass, permission_required, action = "unknown", no_log) {
    await reload();
    const user = users.users[name];
    if (!user) {
        await add_log("Unknown user login. User: " +
            name +
            ", Permission needed: " +
            permission_required +
            ", Action: " +
            action);
        return false;
    }
    if (user.password !== pass) {
        await add_log("Unauthorized user login. User: " +
            name +
            ", Permission needed: " +
            permission_required +
            ", Action: " +
            action);
        return false;
    }
    if (!user.enabled) {
        await add_log("Disabled user login. User: " +
            name +
            ", Permission needed: " +
            permission_required +
            ", Action: " +
            action);
        return false;
    }
    if (!(await check_permission(user, permission_required))) {
        await add_log("Permission denied. User: " +
            name +
            ", Permission needed: " +
            permission_required +
            ", Action: " +
            action);
        return false;
    }
    if (!no_log) {
        await add_log("Operation success. User: " +
            name +
            ", Permission needed: " +
            permission_required +
            ", Action: " +
            action);
    }
    return true;
};
exports.auth = auth;
const add_user = async function (name, pass, enabled, permissions) {
    await reload();
    if (users.users[name]) {
        return false;
    }
    users.users[name] = {
        password: pass,
        enabled: enabled,
        permissions: permissions,
    };
    await save();
    return true;
};
exports.add_user = add_user;
const delete_user = async function (name) {
    await reload();
    if (!users.users[name]) {
        return;
    }
    delete users.users[name];
    await save();
};
exports.delete_user = delete_user;
const update_user = async function (name, key, value) {
    await reload();
    if (!users.users[name]) {
        return;
    }
    users.users[name][key] = value;
    await save();
};
exports.update_user = update_user;
