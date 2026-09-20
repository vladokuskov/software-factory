{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "__TEAMS__"
  },
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.factory/hooks/session-start.sh", "timeout": 20, "statusMessage": "loading factory context" }] }
    ],
    "PreToolUse": [
      { "matcher": "Edit|Write|NotebookEdit",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.factory/hooks/guard-scope.sh", "timeout": 15, "statusMessage": "checking file scope" }] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.factory/hooks/gate-on-edit.sh", "timeout": 180, "asyncRewake": true, "statusMessage": "running gates" }] }
    ],
    "TaskCreated": [
      { "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.factory/hooks/require-acceptance.sh", "timeout": 15 }] }
    ],
    "TaskCompleted": [
      { "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.factory/hooks/on-task-completed.sh", "timeout": 30 }] }
    ],
    "TeammateIdle": [
      { "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.factory/hooks/teammate-idle.sh", "timeout": 180 }] }
    ]
  }
}
