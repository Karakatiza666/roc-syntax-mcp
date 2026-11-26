## Every snippet the overview page shows, in one app, so the page cannot drift.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	ws: "https://github.com/Karakatiza666/roc-websocket/releases/download/0.0.7/EBNZjRmQ5PZiJAE5UMUFePtQFdb1FnsQX1qagVuiCwM9.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.5/AZpgG3RszEahBa67zc9yCJcAKe4MKw5HucDouNpi727b.tar.zst",
}

import ws.Ws
import cli_ws.WsClient

ask! : Str => Try(Ws.Message, WsClient.Error)
ask! = |text| {
	opened = WsClient.connect!({ url: "ws://127.0.0.1:9001/", protocols: ["echo"] })?
	sent = opened.conn.send!(Text(text))?
	(conn, reply) = sent.receive!()?
	_ = Ws.close_and_wait!(WsClient.ops, conn, 1000, "")?
	Ok(reply)
}

echo_once! : { send! : c, Ws.Message => Try(c, Ws.Error(e)), receive! : c => Try((c, Ws.Message), Ws.Error(e)) }, c => Try(c, Ws.Error(e))
echo_once! = |ws, conn| {
	(conn2, message) = (ws.receive!)(conn)?
	(ws.send!)(conn2, message)
}

main! = |_args| Ok({})
