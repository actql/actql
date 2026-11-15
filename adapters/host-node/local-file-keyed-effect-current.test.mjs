import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
const source = readFileSync(new URL('../connectors/local/host/installed-project-files.mjs', import.meta.url), 'utf8');
let method;
function visit(value) {
  if (!value || typeof value !== 'object') return;
  if (value.type === 'Property' && value.method && value.key.name === 'prepareKeyedSourceRead') {
    assert.equal(method, undefined); method = source.slice(value.start, value.end);
  }
  for (const next of Object.values(value)) {
    if (Array.isArray(next)) next.forEach(visit);
    else if (next && typeof next === 'object') visit(next);
  }
}
visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
function fixture({loseCurrent = false} = {}) {
  const prepared = {}, keyed = {}, request = {}, declaration = {}, value = {}, coreRead = {};
  const run = {prepared, effectful: true, value, reads: new Map()};
  const entry = {declaration}, sharedReads = new Set(), reads = new WeakMap(), events = [];
  const raw = {retainChild() {}, close() {return {pending: false};}};
  let current = true;
  const moon = {clientProgramKeyedAcquisitionMatchesEffectProgram: (k, p) => {
    assert.deepEqual([k, p], [keyed, prepared]); return true;
  }, clientProgramInstalledManagedEffectKeyedSourceRead(...args) {
    assert.deepEqual(args, [value, keyed, request, declaration, 101, 202, 303]);
    events.push('core-read'); return {_0: coreRead};
  }, clientProgramInstalledManagedKeyedSourceRead() {assert.fail('No Pure content recipe or replacement parent');}};
  const ports = {sameRun: p => {assert.strictEqual(p, prepared); if (!current) throw new Error('OriginalCurrentLost'); return run;},
    fail: code => {throw Object.assign(new Error(code), {code});}, entry, sharedReads, reads, moon,
    checked: result => result._0, captureClose: read => {read.close = read.raw.close;},
    sourceManaged: {prepareKeyedRead(...args) {
      assert.deepEqual(args, [prepared, declaration, value, request]);
      events.push('retain-physical-duty'); if (loseCurrent) current = false; return raw;
    }}};
  const invoke = new Function(...Object.keys(ports), 'return ({' + method + '}).prepareKeyedSourceRead;')(...Object.values(ports));
  return {run, sharedReads, events, coreRead, invoke: () => invoke({checkedOwner: prepared,
    keyedAcquisition: keyed, request, declaration, managedRun: value,
    rowLimits: {maxPageBytes: 101, maxTextBytes: 202, maxWork: 303}})};
}

test('Local File Effect keyed read retains the original child and uses its existing typed parent port', () => {
  const f = fixture(); assert.strictEqual(f.invoke(), f.coreRead);
  assert.deepEqual(f.events, ['retain-physical-duty', 'core-read']);
  assert.equal(f.run.reads.size, 1); assert.equal(f.sharedReads.size, 1);
});

test('Local File Effect keyed read retains partial child custody when original current is lost', () => {
  const f = fixture({loseCurrent: true});
  assert.throws(f.invoke, /OriginalCurrentLost/);
  assert.deepEqual(f.events, ['retain-physical-duty']);
  assert.equal(f.run.reads.size, 1); assert.equal(f.sharedReads.size, 1);
});
