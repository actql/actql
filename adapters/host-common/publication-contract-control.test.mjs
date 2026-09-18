import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {openLocalPublicationStore} from
  '../store-local/publication-store.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = Object.freeze({
  maxWireBytes: 64 * 1024,
  maxNodes: 4096,
  maxDepth: 64,
});

function invocation(control) {
  return control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: cid('1'),
    observation_set_cid: cid('2'),
  }), limits);
}

test('installed publication control uses the portable contract owner', () => {
  const control = runtimeCore(moon).publicationControl;
  const sealed = invocation(control);
  assert.deepEqual(sealed, {
    name: 'run_invocation',
    identityField: 'invocation_cid',
    identity:
      'sha256:49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18',
    wire: '{"invocation_cid":"sha256:' +
      '49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18' +
      '","invocation_template_cid":"' + cid('1') +
      '","observation_set_cid":"' + cid('2') +
      '","version":"actql-run-invocation/0.1"}',
  });
  assert.deepEqual(
    control.admit('run_invocation', sealed.wire, limits),
    sealed,
  );
  assert.throws(
    () => control.recordAllowsCommit(Object.freeze({...sealed})),
    /Foreign publication contract/u,
  );
});

test('local durable Store accepts only MoonBit-admitted contract wire',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-runtime-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const control = runtimeCore(moon).publicationControl;
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cid('a'),
      capacityBytes: 1024 * 1024,
      maxObjectBytes: limits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, control);
    const sealed = invocation(control);
    const stored = await store.putPublicationContract(
      sealed.name, sealed.wire,
    );
    assert.equal(stored.semanticCid, sealed.identity);
    assert.deepEqual(
      await store.readJsonObject(sealed.identity, sealed.name),
      JSON.parse(sealed.wire),
    );
  });
