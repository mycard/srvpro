## ygopro-server
一个YGOPRO服务器，基于mycard代码修改。

现用于[YGOPRO 233服](http://mercury233.me/ygosrv233/)。

###支持功能
* Linux上运行
* 玩家输入同一房名约战
* 玩家不输入房间名，自动匹配在线玩家
* 房间列表json
* 广播消息
* 召唤台词
* 先行卡一键更新
* Windbot在线AI

###不支持功能
* 用户账号系统
* 在线聊天室

###使用方法
* 安装修改后的mycard版ygopro服务端：https://github.com/mercury233/ygopro/tree/server
* `git clone https://github.com/mercury233/ygopro-server.git`
* `cd ygopro-server`
* `npm install`
* 将`config.json`复制为`config.user.json`并进行修改
 * `port`为你想要的端口
 * `ygopro_path`为ygopro服务端的相对路径
 * `modules.stop`为文本时，表示服务器关闭
* `node ygopro-server.js`即可运行
* 简易的控制台在http://mercury233.me/ygosrv233/dashboard.html （我没有开发给用户使用的大厅的打算。）
* 简易的先行卡更新控制台在http://mercury233.me/ygosrv233/pre-dashboard.html
