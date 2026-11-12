import assert from 'node:assert/strict';
import fs from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {request, requestControl, controls, definition, options}
  from './fixtures/original-plan-journal.mjs';

// Actual SQLite transaction/reopen with explicit typed-control ports. The
// separate MoonBit counter exercises the real checked activation constructor.
function fixture(t, {start = true, afterRecord} = {}) {
  const parent = fileURLToPath(new URL('../../_build/keyed-lookup-journal-fixtures/', import.meta.url));
  fs.mkdirSync(parent, {recursive: true});
  const directory = fs.mkdtempSync(join(parent, 'case-'));
  t.diagnostic(`Fresh keyed Journal fixture retained at ${directory}`);
  const {publication: previous} = controls();
  const preparedEffect = {}, compilation = {}, compiled = {}, graph = {}, activation = {};
  let live = true, records = 0;
  const page = {}, keyedRequest = {};
  const pageRecord = Object.freeze({wire: 'original checked page record',
    batchCid: 'sha256:' + '6'.repeat(64), slotCid: 'sha256:' + '7'.repeat(64),
    activationCid: 'sha256:' + '8'.repeat(64), batchIndex: 0});
  const record = Object.freeze({wire: 'original checked activation record',
    batchCid: 'sha256:' + '6'.repeat(64), slotCid: 'sha256:' + '7'.repeat(64),
    batchIndex: 0, batchCount: 2});
  const publication = Object.freeze({...previous,
    checkClientCompiledEffectRunOwner(c, p, body) {
      assert.strictEqual(c, compiled); assert.strictEqual(p, preparedEffect);
      assert.strictEqual(body, compilation);
    },
    checkClientCompiledRunDefinition(c, d) {assert.strictEqual(c, compiled); assert.equal(d.identity, definition.identity);},
    keyedLookupActivationJournalRecord(a, r, c, d, g) {
      assert.strictEqual(a, activation); assert.strictEqual(r, request);
      assert.strictEqual(c, compiled); assert.strictEqual(d, definition); assert.strictEqual(g, graph);
      records++; afterRecord?.(); return record;
    },
    keyedLookupPageJournalRecord(p, k, r, c, d, g) {
      assert.strictEqual(p, page); assert.strictEqual(k, keyedRequest);
      assert.strictEqual(r, request); assert.strictEqual(c, compiled);
      assert.strictEqual(d, definition); assert.strictEqual(g, graph); return pageRecord;
    },
    keyedLookupPageJournalCurrent(p, k, r, c, d, g) {
      return live && p === page && k === keyedRequest && r === request &&
        c === compiled && d === definition && g === graph;
    },
    keyedLookupActivationJournalCurrent(a, r, c, d, g) {
      return live && a === activation && r === request && c === compiled && d === definition && g === graph;
    }});
  const control = Object.freeze({...requestControl,
    clientRunStartAction: (_identity, _retained, _run, _cid, reserved, current) => !current ? 5 : reserved ? 1 : 0,
    clientRunPhysicalStartWithCancellationAction: (_identity, _retained, _run, _cid, reserved, fresh, current, cancelled) =>
      !current ? 5 : reserved && fresh && !cancelled ? 1 : 0});
  let journal = openClientRequestJournal(directory);
  const accepted = journal.acceptDefinition(request, options, control, publication);
  journal.reserveDispatch(request, {namespaceId: options.namespaceId, currentAuthorization: true}, control, publication);
  if (start) journal.reservePhysicalStart(request, {namespaceId: options.namespaceId,
    ref: accepted.ref, currentAuthorization: true}, control, publication);
  t.after(() => journal.close());
  const selected = {activation, identity: request, preparedEffect, compilation, compiled,
    runDefinition: definition, graph, limits: {maxWireBytes: 65536, maxNodes: 1024, maxDepth: 32}};
  return {directory, selected, publication, control, record, pageRecord,
    adopt: activationRecord => journal.persistOriginalKeyedLookupPage(accepted.ref,
      {...selected, page, keyedRequest, activationRecord: activationRecord ?? record}, control, publication),
    persist: value => journal.persistOriginalKeyedLookupActivation(accepted.ref, value ?? selected, control, publication),
    retire() {live = false;}, records: () => records,
    get journal() {return journal;},
    reopen() {journal.close(); journal = openClientRequestJournal(directory);},
    stored() {
      journal.close();
      const reader = new DatabaseSync(join(directory, 'client-requests.sqlite3'), {readOnly: true});
      try {return reader.prepare('SELECT activation_wire, page_wire, batch_index, batch_count FROM client_keyed_lookup_originals').all();}
      finally {reader.close(); journal = openClientRequestJournal(directory);}
    }};
}

test('original keyed activation commits before caller dispatch and cold duplicate cannot authorize another attempt', t => {
  const prepare = DatabaseSync.prototype.prepare;
  const statements = [];
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    if (/\b(?:FROM|INTO|UPDATE) client_keyed_lookup_originals\b/u.test(sql)) statements.push(sql);
    return Reflect.apply(prepare, this, [sql]);
  });
  const f = fixture(t);
  assert.equal(statements.length, 0, 'Unselected keyed work does not prepare native statements');
  assert.strictEqual(f.persist(), f.record);
  assert.equal(statements.length, 3, 'Only the original activation statements are prepared');
  assert.throws(() => f.persist(), {code: 'ClientKeyedLookupActivationUnresolved'});
  assert.equal(statements.length, 3, 'A duplicate retains the same native statement originals');
  assert.deepEqual(f.stored().map(row => ({...row})), [{activation_wire: f.record.wire,
    page_wire: null, batch_index: 0, batch_count: 2}]);
  f.reopen();
  assert.throws(() => f.persist(), {code: 'ClientKeyedLookupActivationUnresolved'});
  assert.equal(f.stored().length, 1);
});

test('original keyed activation refuses absent first physical-start admission without a durable record', t => {
  const f = fixture(t, {start: false});
  assert.throws(() => f.persist(), {code: 'ClientRunPhysicalStartDenied'});
  assert.deepEqual(f.stored(), []);
});

test('retired original keyed binding refuses before Journal mutation', t => {
  const f = fixture(t); f.retire();
  assert.throws(() => f.persist(), {code: 'ForeignClientKeyedLookupOriginal'});
  assert.deepEqual(f.stored(), []);
});

test('lost keyed activation return preserves the committed original and never grants a replacement attempt', t => {
  const f = fixture(t);
  assert.throws(() => {f.persist(); throw new Error('LostActivationReturn');}, /LostActivationReturn/u);
  f.reopen();
  assert.throws(() => f.persist(), {code: 'ClientKeyedLookupActivationUnresolved'});
  assert.equal(f.stored()[0].activation_wire, f.record.wire);
});


test('original keyed page commits once under the exact durably recorded activation', t => {
  const f = fixture(t); f.persist();
  assert.strictEqual(f.adopt(), f.pageRecord);
  assert.equal(f.stored()[0].page_wire, f.pageRecord.wire);
  f.reopen();
  assert.throws(() => f.adopt(), {code:'ClientKeyedLookupPageUnresolved'});
  assert.equal(f.stored()[0].page_wire, f.pageRecord.wire);
});

test('keyed page cannot adopt absent or substituted activation wire', t => {
  const f = fixture(t);
  assert.throws(() => f.adopt(), {code:'ClientKeyedLookupPageUnresolved'});
  assert.deepEqual(f.stored(), []);
  f.persist();
  assert.throws(() => f.adopt({...f.record, wire:'copied different activation'}),
    {code:'ClientKeyedLookupPageUnresolved'});
  assert.equal(f.stored()[0].page_wire, null);
});

test('retired keyed page keeps the recorded activation unresolved', t => {
  const f = fixture(t); f.persist(); f.retire();
  assert.throws(() => f.adopt(), {code:'ForeignClientKeyedLookupPage'});
  assert.equal(f.stored()[0].page_wire, null);
});
