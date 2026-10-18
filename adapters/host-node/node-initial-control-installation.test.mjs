import assert from 'node:assert/strict';
import test from 'node:test';
import {beginInitialControlInstallation, assertInitialControlInstallationCurrent}
  from './node-initial-control-installation.mjs';

// Current selected preload has no complete initial-control operational issuer.
// These are actual absence/refusal cases, not a fixture issuing an admission or
// a positive Host, preparation, physical-capacity or business-Run qualification.
const unavailable = error => error.code === 'NodeInitialControlAdmissionUnavailable';

test('initial control refuses absent operational startup before observing caller fields', () => {
  let observed = 0;
  const originals = Object.defineProperty({}, 'host', {get() {
    observed++;
    throw new Error('CallerIsNotAStartupIssuer');
  }});
  assert.throws(() => beginInitialControlInstallation(originals), unavailable);
  assert.equal(observed, 0);
});

test('bounds runtime references and matching DATA cannot replace the startup issuer', () => {
  const originals = Object.freeze({host: {}, installation: {}, generation: {},
    supplier() {}, moduleLifetime: import.meta, runtime: process,
    maxBytes: 65536, ledger: {}, admitted: true, cid: `sha256:${'0'.repeat(64)}`});
  assert.throws(() => beginInitialControlInstallation(originals), unavailable);
  assert.throws(() => beginInitialControlInstallation({...originals}), unavailable);
});

test('late ordinary import has no synthetic or reusable pending admission', () => {
  for (const originals of [undefined, null, false, {}, {}]) {
    assert.throws(() => beginInitialControlInstallation(originals), unavailable);
  }
});

test('a caller current method cannot authenticate an initial control scope', () => {
  let observed = 0;
  const scope = Object.freeze({assertCurrent() { observed++; }});
  assert.throws(() => assertInitialControlInstallationCurrent(scope, {}), unavailable);
  assert.equal(observed, 0);
});
