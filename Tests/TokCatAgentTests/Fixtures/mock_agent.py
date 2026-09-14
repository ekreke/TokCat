#!/usr/bin/env python3
"""最小 ACP mock agent，供 TokCatAgent 集成测试使用。

- initialize / session/new / session/prompt 的常规路径会流式推送若干
  session/update 通知后再返回 stopReason。
- 当 prompt 文本包含 "permission" 时，会先发一个
  session/request_permission 反向请求，等待客户端响应后回显所选 option。
"""
import json
import sys


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def result(msg_id, res):
    send({"jsonrpc": "2.0", "id": msg_id, "result": res})


def error(msg_id, code, message):
    send({"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}})


def update(session_id, body):
    send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": session_id, "update": body}})


def chunk(session_id, kind, text):
    update(session_id, {"sessionUpdate": kind, "content": {"type": "text", "text": text}})


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        msg = json.loads(line)
        method = msg.get("method")
        msg_id = msg.get("id")
        params = msg.get("params") or {}

        if method == "initialize":
            result(msg_id, {
                "protocolVersion": 1,
                "agentCapabilities": {"loadSession": True},
                "agentInfo": {"name": "mock-agent", "version": "0.0"},
                "authMethods": [],
            })
        elif method == "session/new":
            result(msg_id, {"sessionId": "test-session"})
        elif method == "session/prompt":
            session_id = params.get("sessionId", "test-session")
            text = "".join(block.get("text", "") for block in params.get("prompt", []))
            if "permission" in text:
                send({
                    "jsonrpc": "2.0",
                    "id": "perm-1",
                    "method": "session/request_permission",
                    "params": {
                        "sessionId": session_id,
                        "toolCall": {"toolCallId": "p1", "title": "run rm"},
                        "options": [
                            {"optionId": "allow_once", "name": "Allow", "kind": "allow_once"},
                            {"optionId": "deny", "name": "Deny", "kind": "reject_once"},
                        ],
                    },
                })
                chosen = "none"
                while True:
                    reply = sys.stdin.readline()
                    if not reply:
                        break
                    parsed = json.loads(reply)
                    if parsed.get("id") == "perm-1":
                        chosen = parsed.get("result", {}).get("outcome", {}).get("optionId", "none")
                        break
                chunk(session_id, "agent_message_chunk", "chose:" + chosen)
            else:
                chunk(session_id, "agent_message_chunk", "Hello")
                chunk(session_id, "agent_thought_chunk", "thinking")
                chunk(session_id, "agent_message_chunk", " world")
            result(msg_id, {"stopReason": "end_turn"})
        elif method == "session/cancel":
            pass
        else:
            if msg_id is not None:
                error(msg_id, -32601, "method not found")


if __name__ == "__main__":
    main()
