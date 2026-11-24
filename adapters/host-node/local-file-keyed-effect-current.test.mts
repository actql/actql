import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {installPreparedProjectLocalFiles} from '../connectors/local/host/installed-project-files.mjs';

import type {TestContext} from 'node:test';

type Install = Parameters<typeof installPreparedProjectLocalFiles>[0];
type HostError = Readonly<{message: string; cause?: Error; primaryFailure?: unknown}>;

const ok = (value?: unknown) => ({$tag: 1, _0: value});
const cid = 'sha256:' + 'a'.repeat(64);

// Imported installer and row-source caller with explicit nominal Core/Account
// ports. This tests handoff and cleanup ordering, not Resource admission,
// authorization, native I/O or a physical cleanup ACK.
async function fixture(t: TestContext, {loseCurrent = false} = {}) {
  const prepared = {}, keyed = {}, intent = {}, request = {}, declaration = {}, managed = {};
  const directRead = {}, coreRead = {}, requirement = {}, capacity = {}, events: string[] = [];
  const stop = new Error('StopAfterOriginalKeyedRead');
  let current = true;
  const facts = (ref: string) => [ref, cid, cid, cid, 'public', cid];
  const raw = (name: string) => ({retainChild() {assert.fail('No native child is opened');},
    close() {events.push(name + '-close'); return {pending: false};}});
  const checkManaged = (value: unknown, owner: unknown, selected: unknown) => {
    assert.strictEqual(value, managed); assert.strictEqual(owner, prepared);
    assert.strictEqual(selected, intent); return ok();
  };
  const moon = {
    clientProgramLocalFileTimestamp: () => '',
    clientProgramResourceReferenceIssuer: () => ({}),
    clientProgramCheckEnvironment: () => ({}),
    clientProgramInstalledEffectManagedRunCheck: checkManaged,
    clientProgramInstalledEffectManagedSourceOccurrence: () => ok({_0: 0, _1: 0, _2: 0}),
    clientProgramInstalledEffectManagedSourceInputKind: () => ok('query'),
    clientProgramInstalledEffectManagedSourceRead: () => ok({_0: directRead, _1: requirement,
      _2: {}, _3: capacity}),
    clientProgramInstalledSourceReadBindEffectProgram: () => ok(),
    clientProgramInstalledSourceReadBindProgram: () => assert.fail('No Pure parent'),
    clientProgramInstalledSourceReadAttachAcquisition: () => assert.fail('No replacement acquisition'),
    clientProgramInstalledSourceReadCheckCurrent: () => ok(),
    clientProgramInstalledSourceReadRetire(value: unknown) {
      assert.strictEqual(value, directRead); events.push('direct-retire'); return ok();
    },
    clientProgramQueryRequirementSourceEvidenceFacts: () => ok(facts('local:files')),
    clientProgramQueryRequirementCid: () => cid,
    clientProgramQueryRequirementInputContractCid: () => cid,
    clientProgramQueryRequirementOutputContractCid: () => cid,
    clientProgramRowSourceTarget: () => ok(['files', 'path']),
    clientProgramEffectRequestScope: () => ({}),
    clientProgramKeyedAcquisitionMatchesEffectProgram(k: unknown, p: unknown) {
      assert.strictEqual(k, keyed); assert.strictEqual(p, prepared); return true;
    },
    clientProgramKeyedRowPrepareCapacity: () => ok(capacity),
    clientProgramKeyedAcquisitionSourceEvidenceFacts: () => ok(facts('local:contents')),
    clientProgramKeyedAcquisitionInputCoordinates: () => ok([0, 0, 0, 0]),
    clientProgramKeyedRowCapacityTarget: () => ok(['contents', 'content']),
    clientRequestProgramCid: () => cid,
    clientRequestParametersCid: () => cid,
    clientProgramInstalledManagedEffectKeyedSourceRead(...args: unknown[]) {
      assert.deepEqual(args, [managed, keyed, request, declaration, 1024, 1024, 1000000]);
      events.push('core-read'); return ok(coreRead);
    },
    clientProgramInstalledManagedKeyedSourceRead() {assert.fail('No Pure content recipe');},
    clientProgramInstalledKeyedSourceReadCheckCurrent(value: unknown) {
      assert.strictEqual(value, coreRead); throw stop;
    },
    clientProgramInstalledKeyedSourceReadAcquisition() {assert.fail('Stop before row acquisition');},
    clientProgramInstalledKeyedSourceReadRetire(value: unknown) {
      assert.strictEqual(value, coreRead); events.push('keyed-retire'); return ok();
    },
  };
  const declared = {views: ['files', 'contents'].map(resource => ({resource,
    source_ref: 'local:' + resource, view_cid: cid, carrier_schema_cid: cid})),
  evidence_schemas: [], evidence_capabilities: [], view_bodies: [], contracts: [],
  catalog: '{}', manifest_entry: '{"connector_id":"local"}'};
  const entry = {connection: 'local', connectorId: 'local', rootPath: '/not-opened', declaration,
    scopeCid: cid, wire: JSON.stringify(declared), queryAliases: [{name: 'local', resource: 'files'}],
    limits: {maxReadBytes: 4096, maxPages: 4, maxPageBytes: 1024,
      maxPageRows: 4, maxFiles: 8, maxFileBytes: 1024}};
  const bundle = {sources: [entry]};
  const profile = await installPreparedProjectLocalFiles({moon,
    preparation: {originalsForRuntime: () => bundle},
    baseEnvironmentWire: canonicalJson(JSON.parse(await readFile(
      new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'))),
    authorizationFor: async () => ({context: {contextCid: cid},
      authorize: async () => ({action: 'dispatch'}), assertAccountCurrent() {}}),
    sourceManaged: {assertCurrent() {if (!current) throw new Error('OriginalCurrentLost');},
      prepareRead: () => raw('direct'),
      prepareKeyedRead(...args: unknown[]) {
        assert.deepEqual(args, [prepared, declaration, managed, request]);
        events.push('retain-physical-duty');
        if (loseCurrent) current = false;
        return raw('keyed');
      }},
  } as unknown as Install).catch((error: HostError) => {throw error.primaryFailure ?? error;});
  t.after(() => profile.close());
  const source = profile.sources[0];
  await source.prepare({preparedEffect: prepared, managedRun: managed, requestIdentity: intent} as Parameters<typeof source.prepare>[0]);
  const selected = await source.prepareKeyed!({preparedEffect: prepared, keyedAcquisition: keyed,
    requestIdentity: intent});
  return {events, stop, profile, invoke: () => source.openKeyed!({preparedEffect: prepared,
    managedRun: managed, keyedAcquisition: keyed, request, ledger: {}, preparedKeyed: selected.prepared})};
}

test('Local File Effect keyed read retains its original child before the existing typed parent port', async t => {
  const f = await fixture(t);
  await assert.rejects(f.invoke, (error: unknown) => (error as HostError).cause === f.stop || error === f.stop);
  assert.deepEqual(f.events.slice(0, 2), ['retain-physical-duty', 'core-read']);
  assert(f.events.indexOf('keyed-close') > f.events.indexOf('core-read'));
  await f.profile.close();
  for (const name of ['direct-close', 'keyed-close']) {
    assert.equal(f.events.filter(value => value === name).length, 1, name);
  }
  const closed = [...f.events];
  await f.profile.close();
  assert.deepEqual(f.events, closed, 'Repeated close cannot reopen or close the original child twice');
});

test('Local File Effect keyed read retains partial child custody when original current is lost', async t => {
  const f = await fixture(t, {loseCurrent: true});
  await assert.rejects(f.invoke, (error: unknown) => /OriginalCurrentLost/u.test((error as HostError).message) ||
    /OriginalCurrentLost/u.test((error as HostError).cause?.message!));
  assert.deepEqual(f.events, ['retain-physical-duty']);
  await f.profile.close();
  assert.deepEqual(f.events, ['retain-physical-duty', 'direct-close', 'direct-retire', 'keyed-close']);
});
