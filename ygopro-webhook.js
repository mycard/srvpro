/*
 ygopro-webhook.js
 ygopro webhook auto update
 
 To use this, add a webhook of http://(server_ip):(port)/api/(password)/(repo) into the related github repos.
 eg. Set http://tiramisu.mycard.moe:7966/api/123456/script in ygopro-scripts to make the server script synced with github FOREVER.
 
 Author: Nanahira
 License: MIT
 
*/
var http = require('http');
var fs = require('fs');
var execSync = require('child_process').execSync;
var spawn = require('child_process').spawn;
var spawnSync = require('child_process').spawnSync;
var url = require('url');
var moment = require('moment');
moment.locale('zh-cn');
var loadJSON = require('load-json-file').sync;

var constants = loadJSON('./data/constants.json');

var settings = loadJSON('./config/config.json');
config=settings.modules.webhook;

var status = {};

var sendResponse = function(text) {
	console.log(moment().format('YYYY-MM-DD HH:mm:ss') + " --> " + text);
}

var pull_data = function(path, remote, branch, callback) {
	sendResponse("Started pulling on branch "+branch+" at "+path+" from "+remote+".");
	try {
		var proc = spawn("git", ["pull", remote, branch], { cwd: path, env: process.env });
		proc.stdout.setEncoding('utf8');
		proc.stdout.on('data', function(data) {
			sendResponse("git pull stdout: "+data);
		});
		proc.stderr.setEncoding('utf8');
		proc.stderr.on('data', function(data) {
			sendResponse("git pull stderr: "+data);
		});
		proc.on('close', function (code) {
			sendResponse("Finished pulling on branch "+branch+" at "+path+" from "+remote+".");
			if (callback) {
				callback();
			}
		});
	} catch (err) {
		sendResponse("Errored pulling on branch "+branch+" at "+path+" from "+remote+".");
		if (callback) {
			callback();
		}
	}
	return;
}

var run_custom_callback = function(command, args, path, callback) {
	sendResponse("Started running custom callback.");
	try {
		var proc = spawn(command, args, { cwd: path, env: process.env });
		proc.stdout.setEncoding('utf8');
		proc.stdout.on('data', function(data) {
			sendResponse("custom callback stdout: "+data);
		});
		proc.stderr.setEncoding('utf8');
		proc.stderr.on('data', function(data) {
			sendResponse("custom callback stderr: "+data);
		});
		proc.on('close', function (code) {
			sendResponse("Finished running custom callback.");
			if (callback) {
				callback();
			}
		});
	} catch (err) {
		sendResponse("Errored running custom callback.");
		if (callback) {
			callback();
		}
	}
	return;
}

var pull_callback = function(name, info) {
	if (info.callback) {
		run_custom_callback(info.callback.command, info.callback.args, info.callback.path, function() {
			process_callback(name, info);
		});
	} else {
		process_callback(name, info);
	}
	return;
}

var process_callback = function(name, info) {
	if (status[name] === 2) {
		status[name] = 1;
		sendResponse("The Process "+name+" was triggered during running. It will be ran again.");
		pull_data(info.path, info.remote, info.branch, function() {
			pull_callback(name, info);
		});
	} else {
		status[name] = false;
		sendResponse("Finished process "+name+".");		
	}
	return;
}

var add_process = function(name, info) {
	if (status[name]) {
		status[name] = 2;
		return "Another process in repo "+name+" is running. The process will start after this.";
	}
	status[name] = 1;
	pull_data(info.path, info.remote, info.branch, function() {
		pull_callback(name, info);
	});
	return "Started a process in repo "+name+".";
}

//returns
var return_error = function(res, msg) {
	res.writeHead(403);
	res.end(msg);
	sendResponse("Remote error: "+msg);
	return;
}

var return_success = function(res, msg) {
	res.writeHead(200);
	res.end(msg);
	sendResponse("Remote message: "+msg);
	return;
}

//will create an http server to receive apis
http.createServer(function (req, res) {
	var u = url.parse(req.url, true);
	var data = u.pathname.split("/");
	if (data[0] !== "" || data[1] !== "api") {
		return return_error(res, "Invalid format.");
	}
	if (data[2] !== config.password) {
		return return_error(res, "Auth Failed.");
	}
	var hook = data[3];
	if (!hook) {
		return return_error(res, "Invalid format.");
	}
	var hook_info = config.hooks[hook];
	if (!hook_info) {
		return return_error(res, "Hooked repo not found.");
	}
	var info = "";	
	req.addListener('data', function(chunk) {
		info += chunk;
	})
	req.addListener('end', function() {
		var infodata;
		try {
			infodata = JSON.parse(info);
		} catch (err) {
			return return_error(res, "Error parsing JSON: " + err);
		}
		var ref = infodata.ref;
		if (!ref) {
			return return_success(res, "Not a push trigger. Skipped.");
		}
		var branch = ref.split("/")[2];
		if (!branch) {
			return return_error(res, "Invalid branch.");
		} else if (branch !== hook_info.branch) {
			return return_success(res, "Branch "+branch+" in repo "+hook+" is not the current branch. Skipped.");		
		} else {
			var return_msg = add_process(hook, hook_info);
			return return_success(res, return_msg);	
		}
	})
	return;
}).listen(config.port);

