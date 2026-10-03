// Codex PreToolUse/Bash adapter. Only the supported deny subset is emitted:
// https://learn.chatgpt.com/docs/hooks#pretooluse
// In particular, Codex does not support PreToolUse permissionDecision: "ask".
import {hookDecision, runHookAdapter} from './local-checks-hook.mjs';

export function codexHookResponse(payload) {
  const reason = hookDecision(payload);
  if (reason === null) return null;
  return {hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'deny',
    permissionDecisionReason: reason,
  }};
}

runHookAdapter(import.meta.url, codexHookResponse, 'Codex');
