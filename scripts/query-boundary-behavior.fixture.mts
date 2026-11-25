// Assertions against production boundaries. Controlled peers supply I/O
// outcomes to the installed authorization and transaction owners.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {ExecutionAuthorizationError} from '../adapters/host-common/authorization-gate.mjs';

type Authorization = typeof import('../adapters/host-common/authorization-gate.mjs');
type Sqlite = typeof import('../adapters/host-common/sqlite-transaction.mjs');
type Gate = Parameters<Authorization['requireAuthorizedDispatch']>[0];
type Decision = Awaited<ReturnType<Gate['authorize']>>;
type InitializationFailure = Error & {
  primaryFailure: unknown;
  cleanupPending: boolean;
  cleanupHandle: {status(): {pending: boolean; owners: readonly string[]}; retry(): {pending: boolean}};
};

export async function authorizationBoundary({requireAuthorizedDispatch}: Pick<Authorization, 'requireAuthorizedDispatch'>) {
  const boundary = 'effect_commit';
  const scope = {connection: 'bound-site', resource: 'bound-target', operation: 'write'};
  const tuple = {...scope, principal: 'boundary-test'};
  for (const action of ['deny', 'failure', 'waiting', 'unsupported', undefined] as const) {
    const decision = Object.freeze({action, boundary, tuple}), options = {};
    let sends = 0, checks = 0;
    const gate: Gate = {async authorize(actualBoundary, actualScope, actualOptions) {
      checks++;
      assert.equal(actualBoundary, boundary);
      assert.equal(actualScope, scope);
      assert.equal(actualOptions, options);
      // Also feed the malformed decision with no action through the real boundary.
      return decision as Decision;
    }};
    await assert.rejects(async () => {
      await requireAuthorizedDispatch(gate, boundary, scope, options);
      sends++;
    }, error => error instanceof ExecutionAuthorizationError && error.authorization === decision,
    'authorization: every non-dispatch decision must stop before send');
    assert.equal(checks, 1);
    assert.equal(sends, 0, 'authorization: refused operation must never send');
  }
  const dispatch: Decision = Object.freeze({action: 'dispatch', boundary, tuple});
  assert.equal(await requireAuthorizedDispatch({authorize: async () => dispatch},
    boundary, scope), dispatch, 'authorization: keep the exact admitted decision');
}

export function unknownCommitBoundary({createSqliteTransaction}: Pick<Sqlite, 'createSqliteTransaction'>) {
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
      assert(error instanceof Error && 'outcome' in error && 'code' in error &&
        'operation' in error && 'connectionUsable' in error);
      assert.equal(error.outcome, 'unknown',
        'Unknown: a failed COMMIT is not resolved by a successful rollback');
      assert.equal(error.code, 'BoundaryCommitOutcomeUnknown');
      assert.equal(error.operation, 'commit');
      assert.equal(error.connectionUsable, true);
      return true;
    });
    assert.equal(physicalCalls, 1, 'Unknown: transaction helper must not retry the body');
    assert.equal(database.isTransaction, false);
    const row = database.prepare('SELECT count(*) AS count FROM child').get();
    assert(row);
    assert.equal(row.count, 0);
  } finally { database.close(); }
}

export function cleanupBoundary({throwSqliteInitializationFailure}: Pick<Sqlite, 'throwSqliteInitializationFailure'>) {
  const database = new DatabaseSync(':memory:');
  const primary = new Error('initialization failed'), closeFailure = new Error('close failed');
  let calls = 0;
  let failure: InitializationFailure | undefined;
  const owner = {close() {
    calls++;
    if (calls <= 2) throw closeFailure;
    database.close();
  }};
  try {
    assert.throws(() => throwSqliteInitializationFailure(owner, primary, 'boundary-db'),
      error => {
        assert(error instanceof Error && 'primaryFailure' in error && 'cleanupPending' in error);
        assert('cleanupHandle' in error && error.cleanupHandle && typeof error.cleanupHandle === 'object' &&
          'status' in error.cleanupHandle && typeof error.cleanupHandle.status === 'function' &&
          'retry' in error.cleanupHandle && typeof error.cleanupHandle.retry === 'function');
        failure = error as InitializationFailure;
        return failure.primaryFailure === primary;
      });
    assert(failure);
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
