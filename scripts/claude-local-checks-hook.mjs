// Claude Code PreToolUse/Bash adapter, using its documented deny response:
// https://code.claude.com/docs/en/hooks#pretooluse-decision-control
// No allow/ask response and no tool-input or permissions rewriting.
import {hookDecision, runHookAdapter} from './local-checks-hook.mjs';

export function claudeHookResponse(payload) {
  const reason = hookDecision(payload);
  if (reason === null) return null;
  return {hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'deny',
    permissionDecisionReason: reason,
  }};
}

runHookAdapter(import.meta.url, claudeHookResponse, 'Claude Code');
