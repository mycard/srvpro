$(function(){
    $("body").tooltip({selector: "[data-toggle='tooltip']", trigger: "hover"});
    $("#open_button").click(loadrooms);
    $("#auto_button").click(autoload);
    $("#shout_button").click(shout);
    $("#stop_button").click(stop);
    $("#welcome_button").click(welcome);
    $("#tips_button").click(load_tips);
    $("#dialogues_button").click(load_dialogues);
    $("#ban_button").click(ban_player);
    $("#kick_button").click(kick_room);
    $("#death_button").click(start_death);
    $("#deathcancel_button").click(cancel_death);
    $("#reboot_button").click(reboot);
    var params=parseQueryString();
    $("#ip").val(params["ip"]);
    $("#port").val(params["port"]);
    $("#password").val(params["password"]);
	$("#username").val(params["username"]);
});

function parseQueryString() {
    //http://stackoverflow.com/questions/523266/how-can-i-get-a-specific-parameter-from-location-search
    var str = window.location.search;
    var objURL = {};
    str.replace(
        new RegExp( "([^?=&]+)(=([^&]*))?", "g" ),
        function( $0, $1, $2, $3 ){
            objURL[ $1 ] = $3;
        }
    );
    return objURL;
}

function get_http() { 
    return $("#http").val() + "://" + $("#ip").val() + ($("#port").val() ? (":" + $("#port").val()) : "");
}

function get_value(name) { 
    return encodeURIComponent($(name).val());
}

function loadrooms() {
    var url=get_http() + "/api/getrooms?callback=?"+ (get_value("#username") ? "&username="+get_value("#username") : "") + (get_value("#password") ? "&pass="+get_value("#password") : "");
	//alert(url);
	
	
    $.getJSON(url, listroom);
    $("#open_button").removeClass("btn-success");
}

function autoload() {
    if (window.autoLoad) {
        window.clearInterval(window.autoLoad);
        window.autoLoad=false;
        $("#message_callback").text("OFF");
    }
    else {
        /*if (!get_value("#password")) {
            alert("请输入密码");
            return;
        }*/
        $("#message_callback").text("ON");
        window.autoLoad=window.setInterval(loadrooms,1000);
    }
}

function playerinfo(player, mode) {
    if (!player)
        return "";
    var info = player.name;
    if (player.status) {
        var status = "";
        if (mode == 1)
            status = status + "Score: " + player.status.score + " " ;
        if (mode != 2 || player.pos % 2 == 0)
            status = status + "LP: "+ player.status.lp;
        if (mode != 2)
            status = status + " Cards: "+ player.status.cards;
        if (status != "")
            info = info + " <em>(" + status + ")</em>";
    }
    if (player.ip)
        info = info +"<br><code>IP: " + player.ip + "</code>";
    return info;
}

function listroom(data) {

    $("#open_button").addClass("btn-success");
    $("#num").text(data.rooms.length);
    var tbody=$("<tbody></tbody>");
    for (i in data.rooms) {
        var room=data.rooms[i];
        var tr=$("<tr></tr>");
        
        room.duelers=[];
        room.watchers=[];
        for (j in room.users) {
            if (room.users[j].pos==7) {
                room.watchers.push(room.users[j]);
            }
            else {
                room.duelers.push(room.users[j]);
            }
        }

        
        tr.append($("<td>"+room.roomid+"</td>"));
        tr.append($("<td>"+ ((room.needpass == "true") ? "<span class='glyphicon glyphicon-lock'></span>" : "") + room.roomname+ "</td>"));

        if (room.roommode != 2) {
            tr.append($("<td>"+playerinfo(room.duelers[0], room.roommode)+"</td>"));
            tr.append($("<td>"+playerinfo(room.duelers[1], room.roommode)+"</td>"));
        }
        else {
            tr.append($("<td>"+playerinfo(room.duelers[0], 2)+"<br>"+playerinfo(room.duelers[1], 2)+"</td>"));
            tr.append($("<td>"+playerinfo(room.duelers[2], 2)+"<br>"+playerinfo(room.duelers[3], 2)+"</td>"));
        }
        
        var watchlist="";
        
        if (room.watchers.length) {
            for (j in room.watchers) {
                watchlist+=room.watchers[j].name+"\r\n";
            }
        }
        
        tr.append($("<td>"+ (watchlist ? "<span class='glyphicon glyphicon-eye-open' data-toggle='tooltip' title='" + watchlist + "'></span>" : "") + room.istart +"</td>"));
        
        tbody.append(tr);
    }
    $("#rooms tbody").remove();
    $("#rooms").append(tbody);
}

function shout() {
    $("#message_callback").text('...');
    var url=get_http() + "/api/message?shout=" + get_value("#shout") + "&username="+get_value("#username")+"&pass=" + get_value("#password") + "&callback=?";
    $.getJSON(url, shoutcallback);
}
function stop() {
    if (confirm("Are you sure to stop the server?")) {
        $("#message_callback").text('...');
        var url=get_http() + "/api/message?stop=" + get_value("#shout") +"&username="+get_value("#username")+ "&pass=" + get_value("#password") + "&callback=?";
        $.getJSON(url, shoutcallback);
    }
}
function welcome() {
    if (get_value("#shout").length) {
        $("#message_callback").text('...');
        var url=get_http() + "/api/message?welcome=" + get_value("#shout") + "&username="+get_value("#username")+"&pass=" + get_value("#password") + "&callback=?";
        $.getJSON(url, shoutcallback);
    }
    else {
        $("#message_callback").text('...');
        var url=get_http() + "/api/message?getwelcome=1&pass=" + get_value("#password") + "&username="+get_value("#username")+ "&callback=?";
        $.getJSON(url, shoutcallback);
    }
}
function load_tips() {
    $("#message_callback").text('...');
    var url=get_http() + "/api/message?loadtips=1&pass=" + get_value("#password") + "&username="+get_value("#username") + "&callback=?";
    $.getJSON(url, shoutcallback);
}
function load_dialogues() {
    $("#message_callback").text('...');
    var url=get_http() + "/api/message?loaddialogues=1&pass=" + get_value("#password") +"&username="+get_value("#username") +"&callback=?";
    $.getJSON(url, shoutcallback);
}
function ban_player() {
    if (confirm("Are you sure to ban this player?")) {
        $("#message_callback").text('...');
        var url=get_http() + "/api/message?ban=" + get_value("#shout") + "&pass=" + get_value("#password") +"&username="+get_value("#username") +"&callback=?";
        $.getJSON(url, shoutcallback);
    }
}
function kick_room() {
    if (confirm("Are you sure to terminate this duel?")) {
        $("#message_callback").text('...');
        var url=get_http() + "/api/message?kick=" + get_value("#shout") + "&pass=" + get_value("#password") + "&username="+get_value("#username") +"&callback=?";
        $.getJSON(url, shoutcallback);
    }
}
function start_death() {
    if (confirm("Are you sure to start Extra Duel?")) {
        if (get_value("#shout").length) {
            $("#message_callback").text('...');
            var url=get_http() + "/api/message?death=" + get_value("#shout") + "&pass=" + get_value("#password") +"&username="+get_value("#username") +"&callback=?";
            $.getJSON(url, shoutcallback);
        }
        else {
            $("#message_callback").text('...');
            var url=get_http() + "/api/message?death=all&pass=" + get_value("#password") + "&username="+get_value("#username") +"&callback=?";
            $.getJSON(url, shoutcallback);
        }
    }
}
function cancel_death() {
    if (confirm("Are you sure to cancel Extra Duel?")) {
        if (get_value("#shout").length) {
            $("#message_callback").text('...');
            var url=get_http() + "/api/message?deathcancel=" + get_value("#shout") + "&pass=" + get_value("#password") + "&username="+get_value("#username") +"&callback=?";
            $.getJSON(url, shoutcallback);
        }
        else {
            $("#message_callback").text('...');
            var url=get_http() + "/api/message?deathcancel=all&pass=" + get_value("#password") + "&username="+get_value("#username") +"&callback=?";
            $.getJSON(url, shoutcallback);
        }
    }
}
function reboot() {
    if (confirm("Are you sure to reboot server?")) {
        $("#message_callback").text('...');
        var url=get_http() + "/api/message?reboot=1&pass=" + get_value("#password") + "&username="+get_value("#username") + "&callback=?";
        $.getJSON(url, shoutcallback);
    }
}

function shoutcallback(data) {
    $("#message_callback").text(data[0]);
    if (data[1]) {
        $("#shout").val(data[1]);
    }
}
