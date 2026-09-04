#!/usr/bin/env python3
"""Stdio fake for `codex app-server`. Speaks newline-delimited JSON-RPC."""

import json
import sys

APPROVAL_MODE = "--approval" in sys.argv or any(
    arg.endswith("test.mode=approval") for arg in sys.argv
)

THREAD = {
    "id": "thread-1",
    "cliVersion": "0.153.2",
    "createdAt": 0,
    "cwd": "/tmp",
    "ephemeral": False,
    "modelProvider": "openai",
    "preview": "",
    "projectId": None,
    "sessionId": "session-1",
    "source": "appServer",
    "status": {"type": "idle"},
    "turns": [],
    "updatedAt": 0,
}

TURN = {"id": "turn-1", "items": [], "status": "inProgress"}
COMPLETED_TURN = {"id": "turn-1", "items": [], "status": "completed"}

THREAD_START_RESULT = {
    "approvalPolicy": "on-request",
    "approvalsReviewer": "user",
    "cwd": "/tmp",
    "model": "gpt-5.6",
    "modelProvider": "openai",
    "sandbox": {"type": "workspaceWrite"},
    "thread": THREAD,
}

MODEL = {
    "id": "gpt-5.6",
    "displayName": "GPT-5.6",
    "defaultReasoningEffort": "medium",
    "description": "default",
    "hidden": False,
    "isDefault": True,
    "model": "gpt-5.6",
    "supportedReasoningEfforts": [
        {"description": "Medium", "reasoningEffort": "medium"}
    ],
}


def send(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def send_delta_and_completed():
    send(
        {
            "method": "item/agentMessage/delta",
            "params": {
                "delta": "Hello",
                "itemId": "item-msg",
                "threadId": "thread-1",
                "turnId": "turn-1",
            },
        }
    )
    send(
        {
            "method": "turn/completed",
            "params": {"threadId": "thread-1", "turn": COMPLETED_TURN},
        }
    )


def send_approval_request():
    send(
        {
            "id": "approval-1",
            "method": "item/commandExecution/requestApproval",
            "params": {
                "itemId": "item-1",
                "startedAtMs": 0,
                "threadId": "thread-1",
                "turnId": "turn-1",
                "command": "ls -la",
                "cwd": "/tmp",
            },
        }
    )


def handle(msg):
    method = msg.get("method")
    mid = msg.get("id")

    if method is None and mid is not None and "result" in msg:
        decision = (msg.get("result") or {}).get("decision")
        send(
            {
                "method": "turn/completed",
                "params": {
                    "threadId": "thread-1",
                    "turn": {
                        "id": "turn-1",
                        "items": [],
                        "status": "completed",
                        "preview": decision,
                    },
                },
            }
        )
        return

    if method == "initialize":
        send(
            {
                "id": mid,
                "result": {
                    "codexHome": "/tmp/codex",
                    "platformFamily": "unix",
                    "platformOs": "macos",
                    "userAgent": "codex-fake",
                },
            }
        )
        if APPROVAL_MODE:
            send_approval_request()
        return

    if method == "initialized":
        return

    if method == "thread/start":
        send({"id": mid, "result": THREAD_START_RESULT})
        send_delta_and_completed()
        return

    if method == "thread/resume":
        thread = dict(THREAD)
        thread["turns"] = [{"id": "turn-resume", "items": [], "status": "inProgress"}]
        result = dict(THREAD_START_RESULT)
        result["thread"] = thread
        send({"id": mid, "result": result})
        return

    if method == "thread/read":
        thread = dict(THREAD)
        if (msg.get("params") or {}).get("includeTurns"):
            thread["turns"] = [COMPLETED_TURN]
        send({"id": mid, "result": {"thread": thread}})
        return

    if method == "thread/archive":
        send({"id": mid, "result": {}})
        return

    if method == "turn/start":
        send({"id": mid, "result": {"turn": TURN}})
        return

    if method == "turn/interrupt":
        params = msg.get("params") or {}
        turn_id = params.get("turnId")
        thread_id = params.get("threadId")
        if not isinstance(turn_id, str) or not turn_id or turn_id == thread_id:
            send(
                {
                    "id": mid,
                    "error": {"code": -32602, "message": "invalid turnId"},
                }
            )
            return
        send({"id": mid, "result": {"interruptedTurnId": turn_id}})
        return

    if method == "model/list":
        send({"id": mid, "result": {"data": [MODEL]}})
        return

    if mid is not None:
        send(
            {
                "id": mid,
                "error": {"code": -32601, "message": "Method not found: %s" % method},
            }
        )


def main():
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        handle(json.loads(line))


if __name__ == "__main__":
    main()
