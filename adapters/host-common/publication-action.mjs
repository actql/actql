const actions = Object.freeze({
  resultAccess: Object.freeze([
    'authorize_request', 'resolve_committed_result',
    'check_initial_availability', 'admit_read', 'issue_grant',
    'start_delivery', 'reject',
  ]),
  existingDelivery: Object.freeze([
    'confirm_succeeded_record', 'reject_unresolved_attempt',
    'reject_terminal_attempt', 'invalid',
  ]),
  failureTerminal: Object.freeze(['failed', 'cancelled']),
  recordRetry: Object.freeze(['append_next_record', 'finished', 'invalid']),
  setup: Object.freeze([
    'check_existing_commit', 'validate_existing_evidence',
    'finalize_existing_commit', 'return_existing_commit',
    'check_initial_active', 'persist_contracts', 'create_attempt',
    'enter_attempt_progress', 'invalid',
  ]),
  attempt: Object.freeze([
    'append_preparing', 'check_active', 'append_committing',
    'issue_index', 'commit_index', 'require_reconciliation',
    'reject_missing_index', 'reject_terminal', 'invalid',
  ]),
  cancellation: Object.freeze([
    'rethrow', 'cancel_preparing', 'cancel_committing',
  ]),
  finalization: Object.freeze([
    'finished', 'append_succeeded', 'append_superseded',
    'superseded_confirmed', 'invalid',
  ]),
  commitFailure: Object.freeze([
    'reconcile_commit', 'append_unknown', 'return_unknown',
    'confirm_uncommitted_failure', 'adopt_committed_index', 'invalid',
  ]),
  unknownRetry: Object.freeze([
    'reconcile', 'retry_upstream_cleanup', 'finished', 'invalid',
  ]),
  preparedRelease: Object.freeze([
    'inspect', 'release', 'advance', 'finished', 'invalid',
  ]),
  cleanupOwner: Object.freeze([
    'inspect', 'retry', 'advance', 'finished', 'invalid',
  ]),
  durablePayloadFailure: Object.freeze([
    'cancel_writer', 'release_prepared', 'cancel_export', 'finished',
    'invalid',
  ]),
});

export function publicationAction(kind, code) {
  const names = actions[kind];
  if (names === undefined || !Number.isInteger(code) ||
      code < 0 || code >= names.length) {
    throw new TypeError('InvalidRunHostPublicationAction');
  }
  return names[code];
}
