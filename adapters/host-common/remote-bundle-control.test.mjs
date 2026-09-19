import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';

const control = runtimeCore(moon).remoteBundleControl;
const cid = digit => `sha256:${digit.repeat(64)}`;

const manifest = revision => Object.freeze({
  issuerAuthority: 'bundle-authority-a',
  bundleName: 'local-runtime',
  revision,
  targetTriple: 'aarch64-apple-darwin',
  componentCid: cid('a'),
  componentBytes: 12n,
  connectorRegistration: 'local',
  connectorRevision: revision,
  strategyRevision: 'strategy/1',
});

const commit = transition => control.commitTransition(transition, true);

test('Remote Bundle canonical identity is independent of adapter state', () => {
  const prepared = control.prepare(manifest('local/1'));
  const body = control.json(prepared);
  const admitted = control.admitJson(body, control.identity(prepared));
  assert.equal(control.json(admitted), body);
  assert.deepEqual(control.projection(admitted).slice(1, 5), [
    'bundle-authority-a',
    'local-runtime',
    'local/1',
    'aarch64-apple-darwin',
  ]);
  assert.throws(() => control.admitJson(`${body} `, control.identity(prepared)));
});

test('Remote Bundle drain retains owners and gates reclamation', () => {
  const value = control.prepare(manifest('local/1'));
  const record = control.open(value);
  commit(control.prepareActivate(record));
  commit(control.prepareRetain(record, 2));
  commit(control.prepareDrain(record));
  assert.throws(() => control.prepareRetain(record, 2));
  assert.throws(() => control.prepareReclaim(record));
  commit(control.prepareRelease(record));
  commit(control.prepareReclaim(record));
  assert.deepEqual(control.recordProjection(record), ['5', '3', '0']);
  assert.deepEqual(
    control.recordProjection(control.restore(value, ['4', '2', '0'])),
    ['4', '2', '0'],
  );
});
