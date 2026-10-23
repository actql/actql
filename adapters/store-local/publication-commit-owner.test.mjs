import test from 'node:test';
import assert from 'node:assert/strict';
import {createPublicationCommitOwner} from './publication-commit-owner.mjs';

const failure = code => Object.assign(new Error(code), {code});

function fixture() {
  const entry = Object.freeze({public_index_entry_cid: 'entry'});
  const admitted = Object.freeze({identity: 'entry'});
  const key = Object.freeze({runDefinitionCid: 'run'});
  const calls = [];
  let current;
  let pending = true;
  const custody = Object.freeze({
    status: () => ({pending}),
    async resolveConfirmed(confirmed) {
      calls.push('resolve');
      pending = false;
      return {outcome: confirmed === undefined ? 'uncommitted' : 'committed'};
    },
  });
  const operations = {
    async confirm() { calls.push('confirm'); return current; },
    async sameContent() { calls.push('same'); return true; },
    async verifyExistingInventory() { calls.push('inventory'); },
    async stage() { calls.push('stage'); },
    beginCustody() { calls.push('custody'); return custody; },
    async install(markInstalled) {
      calls.push('link');
      markInstalled();
      current = entry;
      calls.push('sync');
    },
    async adoptObjects() { calls.push('objects'); pending = false; },
    async adoptSchemas() { calls.push('schemas'); },
    async adopt() {
      await this.adoptObjects();
      await this.adoptSchemas();
    },
    conflict() { throw failure('PublicationCommitConflict'); },
    makeFailure: (code, cause) => Object.assign(
      new Error(code, {cause}), {code},
    ),
  };
  return {
    entry, admitted, key, operations, calls, custody,
    setCurrent: value => { current = value; },
  };
}

test('existing public commit verifies inventory and adopts without linking',
  async () => {
    const {entry, admitted, key, operations, calls, setCurrent} = fixture();
    setCurrent(entry);
    const result = await createPublicationCommitOwner(
      {entry, admitted, key}, operations,
    ).commit();
    assert.deepEqual(result, {
      entry, committed: false, idempotent: true,
    });
    assert.deepEqual(calls, [
      'confirm', 'same', 'inventory', 'objects', 'schemas',
    ]);
  });

test('a lost response after link retains committed-versus-idempotent identity',
  async () => {
    const {entry, admitted, key, operations, calls} = fixture();
    const syncFailure = failure('EIO');
    const install = operations.install;
    operations.install = async markInstalled => {
      await install(markInstalled);
      throw syncFailure;
    };
    const result = await createPublicationCommitOwner(
      {entry, admitted, key}, operations,
    ).commit();
    assert.deepEqual(result, {
      entry, committed: true, idempotent: false,
    });
    assert.deepEqual(calls, [
      'confirm', 'stage', 'custody', 'link', 'sync', 'confirm', 'same',
      'objects', 'schemas',
    ]);
  });

test('unconfirmed commit retains primary, reconciliation and custody owner',
  async () => {
    const {entry, admitted, key, operations, calls, custody} = fixture();
    const primary = failure('EIO');
    const reconciliation = failure('INDEX_READ_FAILED');
    let confirms = 0;
    operations.confirm = async () => {
      calls.push('confirm');
      if (confirms++ > 0) throw reconciliation;
      return undefined;
    };
    operations.install = async () => { throw primary; };
    await assert.rejects(createPublicationCommitOwner(
      {entry, admitted, key}, operations,
    ).commit(), error => {
      assert.equal(error.code, 'EIO');
      assert.equal(error.primaryFailure, primary);
      assert.equal(error.reconciliationFailure, reconciliation);
      assert.equal(error.cleanupPending, true);
      assert.equal(error.cleanupHandle, custody);
      assert.deepEqual(error.cleanupErrors, [reconciliation]);
      return true;
    });
    assert.deepEqual(calls, ['confirm', 'stage', 'custody', 'confirm']);
    assert.equal(custody.status().pending, true);
  });

test('failure before index installation never acquires prepared custody',
  async () => {
    const {entry, admitted, key, operations, calls} = fixture();
    const primary = failure('INVENTORY_FAILED');
    operations.stage = async () => { throw primary; };
    await assert.rejects(createPublicationCommitOwner(
      {entry, admitted, key}, operations,
    ).commit(), error => error === primary);
    assert.deepEqual(calls, ['confirm']);
  });

test('failed custody construction returns only its staged reservation', async () => {
  const {entry,admitted,key,operations,calls} = fixture();
  const primary = failure('CUSTODY_UNAVAILABLE');
  let held = false;
  operations.stage = async () => {calls.push('stage'); held = true;};
  operations.beginCustody = () => {calls.push('custody'); throw primary;};
  operations.cancelStage = () => {calls.push('cancel-stage'); held = false;};
  await assert.rejects(createPublicationCommitOwner({entry,admitted,key},operations).commit(),error=>error===primary);
  assert.equal(held,false);
  assert.deepEqual(calls,['confirm','stage','custody','cancel-stage']);
});

test('original storage cleanup precedes payload retry using captured methods and receiver', async () => {
  const {entry,admitted,key,operations} = fixture();
  let storagePending = true, payloadPending = true, confirms = 0, release;
  const ordered = [], wait = new Promise(resolve=>{release=resolve;});
  const child = {
    status() {assert.equal(this,child);return {pending:storagePending};},
    async retry() {assert.equal(this,child);await wait;ordered.push('storage');storagePending=false;},
  };
  const primary = Object.assign(failure('NATIVE_REPLY_UNKNOWN'),{outcome:'unknown',cleanupHandle:child});
  const custody = {status:()=>({pending:payloadPending}),async retry(){
    assert.equal(storagePending,false);ordered.push('payload');payloadPending=false;
  }};
  operations.beginCustody = () => custody;
  operations.install = async () => {throw primary;};
  operations.confirm = async () => {if(confirms++===0)return undefined;throw failure('STILL_UNKNOWN');};
  let retained;
  await assert.rejects(createPublicationCommitOwner({entry,admitted,key},operations).commit(),error=>{
    retained=error;return error.outcome==='unknown'&&error.primaryFailure===primary;
  });
  child.status = () => assert.fail('changed storage status was invoked');
  child.retry = () => assert.fail('changed storage retry was invoked');
  const first=retained.cleanupHandle.retry(),second=retained.cleanupHandle.retry();
  assert.equal(first,second);assert.equal(retained.cleanupHandle.status().pending,true);
  release();assert.equal((await first).pending,false);
  assert.deepEqual(ordered,['storage','payload']);
});
