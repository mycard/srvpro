## SRVPro
一个YGOPro服务器。

现用于[萌卡](https://mycard.moe/)和[YGOPro 233服](https://ygo233.com/)。

### 支持功能
* Linux上运行
* Windows上运行
* 玩家输入同一房名约战
* 玩家不指定房间名，自动匹配在线玩家
* 房间列表json
* 广播消息
* 召唤台词
* 先行卡一键更新
* WindBot在线AI
* 萌卡用户登陆

### 不支持功能
* 在线聊天室

### 使用方法
* 可参考[wiki](https://github.com/mercury233/ygopro-server/wiki)安装
* 手动安装：
  * 安装修改后的YGOPro服务端：https://github.com/moecube/ygopro/tree/server
  * `git clone https://github.com/moecube/srvpro.git`
  * `cd srvpro`
  * `npm install`
* 将`config.json`复制为`config.user.json`并进行修改
  * `port`为你想要的端口
  * ~~更多选项参见wiki~~
* `node ygopro-server.js`即可运行
* 简易的控制台在 http://mercury233.me/ygosrv233/dashboard.html

### 高级功能
* 待补充说明
* 简易的先行卡更新控制台在 http://mercury233.me/ygosrv233/pre-dashboard.html

### 开发计划
* 重做CTOS和STOC部分
* 模块化附加功能
  * 房名代码
  * 随机对战
  * 召唤台词
  * WindBot
  * 云录像
  * 比赛模式
  * 先行卡更新
* 用户账号系统和管理员账号系统
* 云录像更换存储方式

### TODO
* refactoring CTOS and STOC
* change features to modules
  * room name parsing
  * random duel
  * summon dialogues
  * WindBot
  * cloud replay
  * tournament mode
  * expansions updater
* user and admin account system
* new database for cloud replay

### License
SRVPro

Copyright (C) 2013-2017  MoeCube Team

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
