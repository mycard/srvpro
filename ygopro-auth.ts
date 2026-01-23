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
import fs from "fs";
import { sync as loadJSON } from "load-json-file";
import loadJSONPromise from "load-json-file";
import moment from "moment";
import bunyan from "bunyan";
import util from "util";

moment.updateLocale("zh-cn", {
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

const log = bunyan.createLogger({ name: "auth" });

if (!fs.existsSync("./logs")) {
  fs.mkdirSync("./logs");
}

type PermissionSet = Record<string, boolean>;

type UserPermissions = string | PermissionSet;

interface UserEntry {
  password: string;
  enabled: boolean;
  permissions: UserPermissions;
  [key: string]: any;
}

interface UsersFile {
  file?: string;
  permission_examples: Record<string, PermissionSet>;
  users: Record<string, UserEntry>;
}

const add_log = async function (message: string): Promise<boolean> {
  const mt = moment();
  log.info(message);
  const text = mt.format("YYYY-MM-DD HH:mm:ss") + " --> " + message + "\n";
  let res = false;
  try {
    await fs.promises.appendFile(`./logs/${mt.format("YYYY-MM-DD")}.log`, text);
    res = true;
  } catch {
    res = false;
  }
  return res;
};

const default_data = loadJSON("./data/default_data.json") as {
  users: UsersFile;
};

const setting_save = async function (settings: UsersFile): Promise<void> {
  try {
    await fs.promises.writeFile(settings.file as string, JSON.stringify(settings, null, 2));
  } catch (e) {
    add_log("save fail");
  }
};

let users: UsersFile;
try {
  users = loadJSON("./config/admin_user.json") as UsersFile;
} catch {
  users = default_data.users;
  setting_save(users);
}

const save = async function (): Promise<void> {
  await setting_save(users);
};

const reload = async function (): Promise<void> {
  const user_backup = users;
  try {
    users = (await loadJSONPromise("./config/admin_user.json")) as UsersFile;
  } catch {
    users = user_backup;
    await add_log("Invalid user data JSON");
  }
};

const check_permission = async function (
  user: UserEntry,
  permission_required: string
): Promise<boolean> {
  const _permission = user.permissions;
  let permission: PermissionSet | undefined;
  if (typeof _permission !== "object") {
    permission = users.permission_examples[_permission];
  } else {
    permission = _permission;
  }
  if (!permission) {
    await add_log("Permision not set:" + String(_permission));
    return false;
  }
  return Boolean(permission[permission_required]);
};

export const auth = async function (
  name: string,
  pass: string,
  permission_required: string,
  action = "unknown",
  no_log?: boolean
): Promise<boolean> {
  await reload();
  const user = users.users[name];
  if (!user) {
    await add_log(
      "Unknown user login. User: " +
        name +
        ", Permission needed: " +
        permission_required +
        ", Action: " +
        action
    );
    return false;
  }
  if (user.password !== pass) {
    await add_log(
      "Unauthorized user login. User: " +
        name +
        ", Permission needed: " +
        permission_required +
        ", Action: " +
        action
    );
    return false;
  }
  if (!user.enabled) {
    await add_log(
      "Disabled user login. User: " +
        name +
        ", Permission needed: " +
        permission_required +
        ", Action: " +
        action
    );
    return false;
  }
  if (!(await check_permission(user, permission_required))) {
    await add_log(
      "Permission denied. User: " +
        name +
        ", Permission needed: " +
        permission_required +
        ", Action: " +
        action
    );
    return false;
  }
  if (!no_log) {
    await add_log(
      "Operation success. User: " +
        name +
        ", Permission needed: " +
        permission_required +
        ", Action: " +
        action
    );
  }
  return true;
};

export const add_user = async function (
  name: string,
  pass: string,
  enabled: boolean,
  permissions: UserPermissions
): Promise<boolean> {
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

export const delete_user = async function (name: string): Promise<void> {
  await reload();
  if (!users.users[name]) {
    return;
  }
  delete users.users[name];
  await save();
};

export const update_user = async function (
  name: string,
  key: string,
  value: unknown
): Promise<void> {
  await reload();
  if (!users.users[name]) {
    return;
  }
  users.users[name][key] = value;
  await save();
};
