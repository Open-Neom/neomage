// XML tag constants — ported from NeomClaw src/constants/xml.ts.

// ── Command metadata tags ──
const String commandNameTag = 'command-name';
const String commandMessageTag = 'command-message';
const String commandArgsTag = 'command-args';

// ── Terminal/bash tags ──
const String bashInputTag = 'bash-input';
const String bashStdoutTag = 'bash-stdout';
const String bashStderrTag = 'bash-stderr';
const String localCommandStdoutTag = 'local-command-stdout';
const String localCommandStderrTag = 'local-command-stderr';
const String localCommandCaveatTag = 'local-command-caveat';

/// All terminal-related tags that indicate terminal output, not a user prompt.
const List<String> terminalOutputTags = [
  bashInputTag,
  bashStdoutTag,
  bashStderrTag,
  localCommandStdoutTag,
  localCommandStderrTag,
  localCommandCaveatTag,
];

const String tickTag = 'tick';

// ── Task notification tags ──
const String taskNotificationTag = 'task-notification';
const String taskIdTag = 'task-id';
const String toolUseIdTag = 'tool-use-id';
const String taskTypeTag = 'task-type';
const String outputFileTag = 'output-file';
const String statusTag = 'status';
const String summaryTag = 'summary';
const String reasonTag = 'reason';
const String worktreeTag = 'worktree';
const String worktreePathTag = 'worktreePath';
const String worktreeBranchTag = 'worktreeBranch';

// ── Ultraplan / remote review tags ──
const String ultraplanTag = 'ultraplan';
const String remoteReviewTag = 'remote-review';
const String remoteReviewProgressTag = 'remote-review-progress';

// ── Inter-agent communication tags ──
const String teammateMessageTag = 'teammate-message';
const String channelMessageTag = 'channel-message';
const String channelTag = 'channel';
const String crossSessionMessageTag = 'cross-session-message';

// ── Fork tags ──
const String forkBoilerplateTag = 'fork-boilerplate';
const String forkDirectivePrefix = 'Your directive: ';

// ── Slash command argument patterns ──
const List<String> commonHelpArgs = ['help', '-h', '--help'];
const List<String> commonInfoArgs = [
  'list',
  'show',
  'display',
  'current',
  'view',
  'get',
  'check',
  'describe',
  'print',
  'version',
  'about',
  'status',
  '?',
];
