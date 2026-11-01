import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {openSqliteEffectLedger} from './sqlite-effect-ledger.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const scope = cid('a'), locator = cid('b');
const wires = ['{"state":"prepared"}', '{"state":"dispatching"}', '{"state":"unknown"}'];
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-history-page-'));
  let ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
  t.after(async () => {ledger.close(); await rm(root, {recursive:true, force:true});});
  const append = (position, key = locator) => ledger.append({logicalRequestScopeCid:scope,
    logicalItemLocatorCid:key, expectedRevision:position, entryCid:cid(String(position + 1)),
    entryJson:wires[position]});
  const page = (after = null, options = {}) => ledger.historyPage(locator,
    {after, maxEntries:1, maxWireBytes:1024, ...options});
  return {root, append, page, get ledger() {return ledger;}, restart() {
    ledger.close(); ledger = openSqliteEffectLedger(root, {authorityScopeCid:scope});
  }};
}

test('formal history pages replay bounded original entries after restart without changing the head', async t => {
  const f = await fixture(t);
  f.append(0); f.append(1); f.append(2);
  const first = f.page();
  assert.equal(first.kind, 'page');
  assert.equal(first.generation, cid('1'));
  assert.equal(first.head.revision, 3);
  assert.equal(first.previous, null);
  assert.deepEqual(first.entries.map(row => [row.revision,row.entryJson]), [[1,wires[0]]]);
  const after = {generation:cid('1'), revision:1, entryCid:cid('1')};
  f.restart();
  const second = f.page(after);
  assert.equal(second.previous.entryJson, wires[0]);
  assert.deepEqual(second.entries.map(row => [row.revision,row.entryJson]), [[2,wires[1]]]);
  assert.deepEqual(f.page(after), second, 'reusing the cursor replays the same Owner entries');
  assert.equal(f.ledger.current(locator).revision, 3);
});

for (const alteration of ['generation', 'entryCid', 'revision']) {
  test(`history cursor ${alteration} mismatch cannot replay a different prefix`, async t => {
    const f = await fixture(t); f.append(0); f.append(1);
    const after = {generation:cid('1'), revision:1, entryCid:cid('1')};
    after[alteration] = alteration === 'revision' ? 3 : cid('f');
    assert.deepEqual(f.page(after), {kind:'cursor_mismatch'});
    assert.equal(f.ledger.current(locator).revision, 2);
  });
}

test('a missing previous history is unrecoverable, while a fresh empty history stays empty', async t => {
  const f = await fixture(t);
  assert.deepEqual(f.page({generation:cid('1'), revision:1, entryCid:cid('1')}),
    {kind:'history_unrecoverable'});
  assert.deepEqual(f.page(), {kind:'page', generation:null, head:null, previous:null, entries:[]});
});

test('history wire budget is a limit, never an empty or complete replay', async t => {
  const f = await fixture(t); f.append(0); f.append(1);
  assert.deepEqual(f.page(null, {maxEntries:2, maxWireBytes:1}), {kind:'limit_exceeded'});
  assert.equal(f.ledger.current(locator).revision, 2);
});

test('missing and physically modified historical entries are rejected rather than filled from the head', async t => {
  const f = await fixture(t); f.append(0); f.append(1);
  const database = new DatabaseSync(join(f.root, 'effect-ledger.sqlite3'));
  t.after(() => database.close());
  database.prepare('UPDATE effect_ledger_entries SET entry_json = ? WHERE revision = 1').run('{}');
  assert.throws(() => f.page(), {code:'EffectLedgerIntegrityFailed'});
});

test('history page limits reject zero or unbounded selections before reading', async t => {
  const f = await fixture(t);
  for (const options of [{maxEntries:0}, {maxEntries:1001}, {maxEntries:100001}, {maxWireBytes:0}]) {
    assert.throws(() => f.page(null, options), {code:'InvalidEffectLedgerHistoryPage'});
  }
});

test('bounded scope inventory lists only that logical request and binds a continuation to it',async t=>{
  const f=await fixture(t);f.append(0);
  f.ledger.append({logicalRequestScopeCid:scope,logicalItemLocatorCid:cid('c'),expectedRevision:0,
    entryCid:cid('4'),entryJson:wires[0]});
  f.ledger.append({logicalRequestScopeCid:cid('f'),logicalItemLocatorCid:cid('e'),expectedRevision:0,
    entryCid:cid('5'),entryJson:'{"state":"unknown","private":"foreign"}'});
  const first=f.ledger.currentScopePage(scope,{maxItems:1,maxWireBytes:4096});
  assert.equal(first.kind,'page');assert.equal(first.hasMore,true);
  assert.deepEqual(first.entries.map(row=>row.logicalItemLocatorCid),[locator]);
  const second=f.ledger.currentScopePage(scope,{after:locator,maxItems:1,maxWireBytes:4096});
  assert.equal(second.hasMore,false);
  assert.deepEqual(second.entries.map(row=>row.logicalItemLocatorCid),[cid('c')]);
  assert.deepEqual(f.ledger.currentScopePage(scope,{after:cid('e'),maxItems:1,maxWireBytes:4096}),{kind:'cursor_mismatch'});
  assert.deepEqual(f.ledger.currentScopePage(scope,{maxItems:1,maxWireBytes:1}),{kind:'limit_exceeded'});
  assert(!JSON.stringify(first).includes('foreign'));
});

for (const encoding of ['UTF-16le', 'UTF-16be']) {
  for (const kind of ['history', 'scope']) {
    test(`native-column page bounds keep valid64-byte ${encoding} ${kind} entries`, async t => {
      const root = await mkdtemp(join(tmpdir(), 'actql-effect-native-page-'));
      const setup = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
      try {
        setup.exec(`PRAGMA encoding = '${encoding}'`);
        setup.exec('CREATE TABLE encoding_fixture (value TEXT) STRICT');
      } finally {setup.close();}
      const ledger = openSqliteEffectLedger(root, {authorityScopeCid:scope, maxEntryBytes:64});
      t.after(async () => {ledger.close();await rm(root,{recursive:true,force:true});});
      const exact = '"' + 'x'.repeat(62) + '"';
      for (let index=0;index<2;index++) ledger.append({logicalRequestScopeCid:scope,
        logicalItemLocatorCid:locator,expectedRevision:index,entryCid:cid(String(index+1)),entryJson:exact});
      // Existing page budgets count native SQLite column bytes. Keep that
      // metric and its exact boundary; only the per-entry UTF8 guard differs.
      const bytes = kind === 'history' ? 256 : 128;
      const read = maxWireBytes => kind === 'history'
        ? ledger.historyPage(locator,{after:{generation:cid('1'),revision:1,entryCid:cid('1')},
          maxEntries:1,maxWireBytes})
        : ledger.currentScopePage(scope,{maxItems:1,maxWireBytes});
      const page = read(bytes);
      assert.equal(page.kind,'page');
      assert.equal(page.entries.length,1);
      assert.equal(page.entries[0].entryJson,exact);
      assert.equal(page.entries[0].revision,2);
      if (kind === 'history') assert.equal(page.previous.entryJson,exact);
      assert.deepEqual(read(bytes-1),{kind:'limit_exceeded'});
    });
  }
}
