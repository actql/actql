// Assertions against production boundaries, shared by the ordinary cases and
// mutation controls. Controlled peers represent I/O outcomes, not a second
// authorization engine, transaction owner or success verifier.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';

export async function authorizationBoundary({requireAuthorizedDispatch}) {
  for (const action of ['deny', 'failure', 'waiting', 'unsupported', undefined]) {
    const decision = Object.freeze({action}), scope = {}, options = {};
    let sends = 0, checks = 0;
    const gate = {async authorize(boundary, actualScope, actualOptions) {
      checks++;
      assert.equal(boundary, 'effect_commit');
      assert.equal(actualScope, scope);
      assert.equal(actualOptions, options);
      return decision;
    }};
    await assert.rejects(async () => {
      await requireAuthorizedDispatch(gate, 'effect_commit', scope, options);
      sends++;
    }, error => error.authorization === decision,
    'authorization: every non-dispatch decision must stop before send');
    assert.equal(checks, 1);
    assert.equal(sends, 0, 'authorization: refused operation must never send');
  }
  const dispatch = Object.freeze({action: 'dispatch'});
  assert.equal(await requireAuthorizedDispatch({authorize: async () => dispatch},
    'effect_commit', {}), dispatch, 'authorization: keep the exact admitted decision');
}

export function unknownCommitBoundary({createSqliteTransaction}) {
  const database = new DatabaseSync(':memory:', {enableForeignKeyConstraints: true});
  try {
    database.exec('CREATE TABLE parent (id INTEGER PRIMARY KEY)');
    database.exec(`CREATE TABLE child (parent_id INTEGER,
      FOREIGN KEY (parent_id) REFERENCES parent(id) DEFERRABLE INITIALLY DEFERRED)`);
    const transaction = createSqliteTransaction(database, 'Boundary');
    let physicalCalls = 0;
    assert.throws(() => transaction.run(() => {
      physicalCalls++;
      database.exec('INSERT INTO child VALUES (7)');
    }), error => {
      assert.equal(error.outcome, 'unknown',
        'Unknown: a failed COMMIT is not resolved by a successful rollback');
      assert.equal(error.code, 'BoundaryCommitOutcomeUnknown');
      assert.equal(error.operation, 'commit');
      assert.equal(error.connectionUsable, true);
      return true;
    });
    assert.equal(physicalCalls, 1, 'Unknown: transaction helper must not retry the body');
    assert.equal(database.isTransaction, false);
    assert.equal(database.prepare('SELECT count(*) AS count FROM child').get().count, 0);
  } finally { database.close(); }
}

export function cleanupBoundary({throwSqliteInitializationFailure}) {
  const database = new DatabaseSync(':memory:');
  const primary = new Error('initialization failed'), closeFailure = new Error('close failed');
  let calls = 0, failure;
  const owner = {close() {
    calls++;
    if (calls <= 2) throw closeFailure;
    database.close();
  }};
  try {
    assert.throws(() => throwSqliteInitializationFailure(owner, primary, 'boundary-db'),
      error => { failure = error; return error.primaryFailure === primary; });
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true,
      'cleanup custody: failed close must retain the original owner');
    assert.deepEqual(failure.cleanupHandle.status().owners, ['boundary-db']);
    assert.equal(failure.cleanupHandle.retry().pending, true,
      'cleanup custody: another failed close must remain pending');
    assert.equal(failure.primaryFailure, primary);
    assert.equal(failure.cleanupHandle.retry().pending, false);
    assert.equal(failure.cleanupPending, false);
    assert.equal(failure.cleanupHandle.retry().pending, false);
    assert.equal(calls, 3, 'cleanup custody: confirmed close must not close twice');
  } finally {
    // Test-owned in-memory database only; never discharge a product Run's custody.
    if (calls < 3) database.close();
  }
}
