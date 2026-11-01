import test from 'node:test';
import assert from 'node:assert/strict';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openDeliveryAttemptIndex} from './delivery-attempt-index.mjs';

const schemaSql = 'SELECT sql FROM sqlite_schema WHERE type=? AND name=?';
// Independent current-format order; never derive this oracle from observed SQL.
const expectedReads = [
  ['table', 'completions'],
  ['index', 'completion_receipts'],
  ['table', 'publication_contracts'],
  ['table', 'publication_usage'],
  ['table', 'publication_recovery'],
  ['table', 'pending_publications'],
  ['table', 'native_publication_inventories'],
  ['table', 'native_publication_inventory_usage'],
  ['table', 'metadata_deletion_fences'],
  ['table', 'metadata_deletion_fence_coverage'],
  ['index', 'metadata_deletion_runs'],
  ['table', 'physical_objects'],
  ['table', 'physical_object_usage'],
  ['table', 'physical_object_preparations'],
  ['table', 'publication_attempts'],
  ['table', 'publication_records'],
  ['index', 'publication_attempt_runs'],
  ['table', 'result_deletion_recovery'],
  ['table', 'native_publication_references'],
  ['index', 'native_publication_reference_owners'],
  ['trigger', 'native_publication_references_insert'],
  ['trigger', 'native_publication_references_update'],
  ['table', 'native_publication_indexes'],
  ['table', 'native_publication_materials'],
];
const options = {create: true, maxEntries: 2, maxWireBytes: 4096};

async function fixture() {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'schema-statements-', label: 'actual SQLite schema statement fixture',
  });
  return {scratch, path: join(scratch.path, 'index.sqlite3')};
}

function traceSchema(t) {
  const prepared = [], reads = [], original = DatabaseSync.prototype.prepare;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    // Every prepare and get still executes on the actual original SQLite DB.
    const statement = Reflect.apply(original, this, [sql]);
    if (sql === schemaSql) {
      prepared.push({database: this, statement});
      const get = statement.get;
      t.mock.method(statement, 'get', function(...args) {
        reads.push({statement: this, arguments: args});
        return Reflect.apply(get, this, args);
      });
    }
    return statement;
  });
  return {prepared, reads};
}

test('schema admission reuses one original statement for all 24 ordered live reads', async t => {
  const f = await fixture(), trace = traceSchema(t);
  let index;
  try {
    index = await openDeliveryAttemptIndex(f.path, options);
    assert.deepEqual(trace.reads.map(read => read.arguments), expectedReads);
    assert.equal(trace.reads.length, 24);
    console.log(JSON.stringify({schemaPrepares: trace.prepared.length,
      liveSchemaReads: trace.reads.length, originalDatabases: new Set(
        trace.prepared.map(row => row.database)).size}));
    assert.equal(trace.prepared.length, 1, 'prepare once, not once per schema entry');
    assert.equal(new Set(trace.prepared.map(row => row.database)).size, 1);
    assert(trace.reads.every(read => read.statement === trace.prepared[0].statement));
  } finally {
    if (index !== undefined) assert.equal(index.close(), true);
  }
  assert.equal(trace.prepared[0].database.isOpen, false);
  f.scratch.passed();
});

test('schema admission still refuses exact SQL mismatch and closes the same DB without repair', async t => {
  const f = await fixture();
  const seed = await openDeliveryAttemptIndex(f.path, options);
  assert.equal(seed.close(), true);
  const changedSql = 'CREATE INDEX completion_receipts ON completions(record_cid)';
  const writer = new DatabaseSync(f.path);
  let coverage;
  try {
    coverage = {...writer.prepare('SELECT * FROM coverage WHERE id=1').get()};
    writer.exec('DROP INDEX completion_receipts; ' + changedSql);
  } finally { writer.close(); }
  const trace = traceSchema(t);
  await assert.rejects(openDeliveryAttemptIndex(f.path, {...options, create: false}),
    {code: 'DeliveryAttemptIndexUnavailable'});
  assert.deepEqual(trace.reads.map(read => read.arguments), expectedReads.slice(0, 2));
  assert(trace.prepared.every(row => row.database.isOpen === false));
  const after = new DatabaseSync(f.path, {readOnly: true});
  try {
    assert.equal(after.prepare("SELECT sql FROM sqlite_schema WHERE name='completion_receipts'").get().sql,
      changedSql);
    assert.deepEqual({...after.prepare('SELECT * FROM coverage WHERE id=1').get()}, coverage);
  } finally { after.close(); }
  f.scratch.passed();
});
