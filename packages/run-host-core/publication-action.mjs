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
});

export function publicationAction(kind, code) {
  const names = actions[kind];
  if (names === undefined || !Number.isInteger(code) ||
      code < 0 || code >= names.length) {
    throw new TypeError('InvalidRunHostPublicationAction');
  }
  return names[code];
}
