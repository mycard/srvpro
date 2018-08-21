var moment = require('moment');
var exec = require('child_process').exec;
var check = function() {
	var now = moment();
	if (now.hour() == 4 && now.minute() == 0) {
		console.log("It is time NOW!");
		exec("pm2 restart all");
	}
	else {
		console.log(now.format());
		setTimeout(check, 10000);
	}
}
setTimeout(check, 60000);
