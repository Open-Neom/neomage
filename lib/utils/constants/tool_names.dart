// Tool name constants and tool availability sets —
// ported from OpenClaude src/constants/tools.ts.

// ── Tool Names ──
const String bashToolName = 'Bash';
const String fileReadToolName = 'Read';
const String fileWriteToolName = 'Write';
const String fileEditToolName = 'Edit';
const String grepToolName = 'Grep';
const String globToolName = 'Glob';
const String webSearchToolName = 'WebSearch';
const String webFetchToolName = 'WebFetch';
const String agentToolName = 'Agent';
const String sendMessageToolName = 'SendMessage';
const String taskOutputToolName = 'TaskOutput';
const String taskStopToolName = 'TaskStop';
const String taskCreateToolName = 'TaskCreate';
const String taskGetToolName = 'TaskGet';
const String taskListToolName = 'TaskList';
const String taskUpdateToolName = 'TaskUpdate';
const String todoWriteToolName = 'TodoWrite';
const String toolSearchToolName = 'ToolSearch';
const String exitPlanModeToolName = 'ExitPlanMode';
const String enterPlanModeToolName = 'EnterPlanMode';
const String askUserQuestionToolName = 'AskUserQuestion';
const String notebookEditToolName = 'NotebookEdit';
const String skillToolName = 'Skill';
const String syntheticOutputToolName = 'SyntheticOutput';
const String enterWorktreeToolName = 'EnterWorktree';
const String exitWorktreeToolName = 'ExitWorktree';
const String workflowToolName = 'Workflow';
const String cronCreateToolName = 'CronCreate';
const String cronDeleteToolName = 'CronDelete';
const String cronListToolName = 'CronList';

// ── Tool Availability Sets ──

/// Tools disallowed for all agents.
const Set<String> allAgentDisallowedTools = {
  taskOutputToolName,
  exitPlanModeToolName,
  enterPlanModeToolName,
  agentToolName,
  askUserQuestionToolName,
  taskStopToolName,
};

/// Tools allowed for async agents.
const Set<String> asyncAgentAllowedTools = {
  fileReadToolName,
  webSearchToolName,
  todoWriteToolName,
  grepToolName,
  webFetchToolName,
  globToolName,
  bashToolName,
  fileEditToolName,
  fileWriteToolName,
  notebookEditToolName,
  skillToolName,
  syntheticOutputToolName,
  toolSearchToolName,
  enterWorktreeToolName,
  exitWorktreeToolName,
};

/// Tools allowed only for in-process teammates.
const Set<String> inProcessTeammateAllowedTools = {
  taskCreateToolName,
  taskGetToolName,
  taskListToolName,
  taskUpdateToolName,
  sendMessageToolName,
};

/// Tools allowed in coordinator mode.
const Set<String> coordinatorModeAllowedTools = {
  agentToolName,
  taskStopToolName,
  sendMessageToolName,
  syntheticOutputToolName,
};
