# Agent Manager

Manage multiple local CLI agents in parallel via tmux sessions with cron-friendly scheduling.

- Each agent runs in a separate tmux session for isolation and parallel execution
- Core operations: start, stop, list, monitor (with --follow), assign tasks, and doctor (health check)
- Agents are configured under an agents/ directory with individual config files
- Task assignment pipes instructions directly to an agent's session via heredoc
- Use the monitor command with --follow to tail agent logs in real time
- Schedule recurring agent work via cron jobs calling the manager script
- Requires tmux and python3 as prerequisites
- Agent IDs follow naming convention like EMP_0001 for identification and routing
