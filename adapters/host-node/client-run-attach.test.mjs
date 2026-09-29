import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientRunAttach} from './client-run-attach.mjs';

const scope = `sha256:${'a'.repeat(64)}`;
const ref = {namespaceId: 'namespace-a', authorityScopeCid: scope,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const requestControl = {clientRequestAdmitRecord() {}};
const publicationControl = {admit() {}};
const request = {principalId: 'principal-a', connection: {mode: 'local'}, ref};

test('attach denies foreign scope, absent Run and current policy revocation',
  async () => {
    let reads = 0;
    const journal = {lookupRunDefinition() {
      reads++;
      return {ref, durability: 'durable', revision: 0,
        runDefinition: {identity: ref.runDefinitionCid}};
    }};
    const install = (authorizedScope, authorizeRun = () => true) =>
      installNodeClientRunAttach({journal, requestControl,
        publicationControl, authorizedScope, authorizeRun});
    await assert.rejects(install(() => ({namespaceId: 'namespace-b',
      authorityScopeCid: scope}))(request),
    {code: 'ClientRunAttachDenied'});
    assert.equal(reads, 0);
    await assert.rejects(install(() => ({namespaceId: 'namespace-a',
      authorityScopeCid: scope}), () => false)(request),
    {code: 'ClientRunAttachDenied'});
    assert.equal(reads, 1);
    const absent = installNodeClientRunAttach({
      journal: {lookupRunDefinition: () => undefined}, requestControl,
      publicationControl,
      authorizedScope: () => ({namespaceId: 'namespace-a',
        authorityScopeCid: scope}),
      authorizeRun: () => assert.fail('absent Run reached policy'),
    });
    await assert.rejects(absent(request), {code: 'ClientRunAttachDenied'});
  });

test('attach returns only the original Run reference and durability',
  async () => {
    const definition = {identity: ref.runDefinitionCid};
    const attached = installNodeClientRunAttach({
      journal: {lookupRunDefinition: () => ({ref,
        durability: 'durable', revision: 4, runDefinition: definition})},
      requestControl, publicationControl,
      authorizedScope: () => ({namespaceId: 'namespace-a',
        authorityScopeCid: scope}),
      authorizeRun: ({runDefinition}) => runDefinition === definition,
    });
    assert.deepEqual(await attached(request),
      {ref, durability: 'durable', revision: 4});
  });
