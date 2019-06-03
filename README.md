## SRVPro
一个YGOPro服务器。

现用于[萌卡](https://mycard.moe/)，[YGOPro 233服](https://ygo233.com/)和[YGOPro Koishi服](http://koishi.222diy.gdn/)。

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
* 竞赛模式锁定玩家卡组
* 竞赛模式后台保存录像
* 竞赛模式自动加时赛系统（规则可调）
  * 0 正常加时赛规则
  * 1 YGOCore战队联盟第十二届联赛使用规则
  * 2 正常加时赛规则 + 1胜规则
  * 3 2018年7月适用的OCG/TCG加时赛规则
* 断线重连

### 不支持功能
* 在线聊天室

### 使用方法
* 可参考[wiki](https://github.com/moecube/srvpro/wiki)安装
* 手动安装：
  * `git clone https://github.com/moecube/srvpro.git`
  * `cd srvpro`
  * `npm install`
  * 安装修改后的YGOPro服务端：https://github.com/moecube/ygopro/tree/server
* `node ygopro-server.js`即可运行
* 简易的控制台在 http://srvpro.ygo233.com/dashboard.html 或 http://srvpro-cn.ygo233.com/dashboard.html
* 使用本项目的Docker镜像: https://hub.docker.com/r/mycard/ygopro-server/
  * `7911`: YGOPro端口
  * `7922`: 管理后台端口
  * `/ygopro-server/config`: SRVPro配置文件数据卷
  * `/ygopro-server/ygopro/expansions`: YGOPro额外卡片数据卷

### 高级功能
* 待补充说明
* 简易的先行卡更新控制台在 http://srvpro.ygo233.com/pre-dashboard.html 或 http://srvpro-cn.ygo233.com/pre-dashboard.html

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

Copyright (C) 2013-2018  MoeCube Team

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
