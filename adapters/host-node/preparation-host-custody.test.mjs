import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';
import {ledgerUsageSnapshot, ledgerUsageSnapshotHasPendingResources} from '../host-common/runtime-core.mjs';
import {ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';

function declarations(path, names, ports, values) {
  const source = readFileSync(new URL(path, import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const bodies = ast.body.filter(n => n.type === 'FunctionDeclaration' && names.includes(n.id.name));
  assert.equal(bodies.length, names.length);
  return compileFunction(bodies.map(n => source.slice(n.start, n.end)).join('\n') +
    `\nreturn {${names.join(',')}};`, ports)(...values);
}
const {retainDispatchPreparationHost: retain, releaseDispatchPreparationHost: release} = declarations(
  './client-dispatch-owner.mjs', ['retainDispatchPreparationHost', 'releaseDispatchPreparationHost'], ['checked'], [checked]);
const ok = _0 => ({$tag: 1, _0});

test('Host holder uses exact original and returns once after clearing local aliases', () => {
  const prepared = {}, holder = {}, run = {}, request = {}, entry = {};
  let returned = 0;
  const moon = {
    clientProgramInstalledManagedPreparationBorrow(r,p,q) {assert.equal(r,run); assert.equal(p,prepared); assert.equal(q,request); return ok(holder);},
    clientProgramPreparationBorrowRead(h) {assert.equal(h,holder); return prepared;},
    clientProgramPreparationBorrowReturn(h) {assert.equal(h,holder); assert.equal(entry.preparationHostBorrow,undefined); returned++; return ok(false);},
  };
  retain(entry,moon,run,prepared,request,true);
  assert.equal(entry.preparationHostBorrow,holder);
  assert.throws(()=>retain(entry,moon,run,prepared,request,true),/Duplicate/);
  release(entry); release(entry); assert.equal(returned,1);
});
for (const mode of ['foreign', 'missing-custody', 'read-throws']) test(`Host acquisition unwinds ${mode}`, () => {
  let returned=0; const prepared={},entry={};
  const moon={clientProgramInstalledManagedPreparationBorrow:()=>ok({}),
    clientProgramPreparationBorrowRead(){if(mode==='read-throws') throw new Error('ReadFailed'); return mode==='foreign'?{}:prepared;},
    clientProgramPreparationBorrowReturn(){returned++;return ok(false);}};
  assert.throws(()=>retain(entry,moon,{},prepared,{},mode!=='missing-custody'));
  assert.equal(returned,1);assert.equal(entry.preparationHostBorrow,undefined);
});
test('Absent holder refuses without creating substitute custody',()=>{
 for(const moon of [{},{clientProgramInstalledManagedPreparationBorrow:()=>ok(undefined),
   clientProgramPreparationBorrowRead(){assert.fail('Absent holder must not be read');},
   clientProgramPreparationBorrowReturn(){assert.fail('Absent holder must not be returned');}}]){
   const entry={};
   assert.throws(()=>retain(entry,moon,{}, {}, {}, false),/PreparationHostCustodyUnavailable/u);
   release(entry);assert.deepEqual(entry,{});
 }
});

const active = new Set(), released = new WeakSet();
const {preflightSetupCleanup} = declarations('../host-common/strategy.mjs', ['preflightSetupCleanup'],
  ['StrategyHostError','active','releasedPreflightSetups','ledgerUsageSnapshotHasPendingResources'],
  [Error,active,released,ledgerUsageSnapshotHasPendingResources]);
for (const isolated of [true,false]) test(`Preflight retained debit requires nominal isolation=${isolated}`,()=>{
 const setup={},holder={}; let stopped=false,closed=false;
 const usage=ledgerUsageSnapshot(ledgerUsageFields.map(({name})=>name==='reserved_retention_bytes'?30n:0n));
 const core={stop(s){assert.equal(s,setup);stopped=true;},closeOutputs(){assert(stopped);closed=true;},
 usage:()=>usage,
 preparationUsageIsolated(s,h){assert(closed);assert.equal(s,setup);assert.equal(h,holder);return isolated;}};
 active.add(setup); const cleanup=preflightSetupCleanup({core,setup,preparationHolder:holder});
 if(isolated){cleanup.close();assert.equal(cleanup.cleanupPending(),false);assert(released.has(setup));}
 else {assert.throws(()=>cleanup.close(),/CleanupPending/);assert.equal(cleanup.cleanupPending(),true);assert(active.has(setup));}
});
test('Isolation cannot replace physical stop confirmation',()=>{
 let checkedIsolation=false;const cleanup=preflightSetupCleanup({setup:{},preparationHolder:{},core:{
 stop(){throw new Error('StopUnknown');},preparationUsageIsolated(){checkedIsolation=true;return true;}}});
 assert.throws(()=>cleanup.close(),/StopUnknown/);assert.equal(checkedIsolation,false);assert.equal(cleanup.cleanupPending(),true);
});
