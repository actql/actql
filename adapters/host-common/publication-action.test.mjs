import assert from 'node:assert/strict';
import test from 'node:test';
import {publicationAction} from './publication-action.mjs';

test('publication JS bridge rejects undefined numeric actions', () => {
  assert.equal(publicationAction('resultAccess', 0), 'authorize_request');
  assert.equal(publicationAction('existingDelivery', 3), 'invalid');
  for (const code of [-1, 7, 1.5, Number.NaN, undefined]) {
    assert.throws(() => publicationAction('resultAccess', code),
      {name: 'TypeError', message: 'InvalidRunHostPublicationAction'});
  }
  assert.throws(() => publicationAction('unknown', 0),
    {name: 'TypeError', message: 'InvalidRunHostPublicationAction'});
});

test('publication lifecycle actions have explicit JS bridge names and reject gaps',
  () => {
    const cases = Object.freeze({
      setup: ['check_existing_commit', 'validate_existing_evidence',
        'finalize_existing_commit', 'return_existing_commit',
        'check_initial_active', 'persist_contracts', 'create_attempt',
        'enter_attempt_progress', 'invalid'],
      attempt: ['append_preparing', 'check_active', 'append_committing',
        'issue_index', 'commit_index', 'require_reconciliation',
        'reject_missing_index', 'reject_terminal', 'invalid'],
      cancellation: ['rethrow', 'cancel_preparing', 'cancel_committing'],
      finalization: ['finished', 'append_succeeded', 'append_superseded',
        'superseded_confirmed', 'invalid'],
      commitFailure: ['reconcile_commit', 'append_unknown', 'return_unknown',
        'confirm_uncommitted_failure', 'adopt_committed_index', 'invalid'],
      unknownRetry: ['reconcile', 'retry_upstream_cleanup', 'finished',
        'invalid'],
      preparedRelease: ['inspect', 'release', 'advance', 'finished', 'invalid'],
      cleanupOwner: ['inspect', 'retry', 'advance', 'finished', 'invalid'],
      durablePayloadFailure: ['cancel_writer', 'release_prepared',
        'cancel_export', 'finished', 'invalid'],
    });
    for (const [kind, expected] of Object.entries(cases)) {
      for (const [code, action] of expected.entries()) {
        assert.equal(publicationAction(kind, code), action);
      }
      for (const code of [-1, expected.length, 0.5, Number.NaN]) {
        assert.throws(() => publicationAction(kind, code), {
          name: 'TypeError', message: 'InvalidRunHostPublicationAction',
        });
      }
    }
  });
