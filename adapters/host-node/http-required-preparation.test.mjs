import test from 'node:test';
import assert from 'node:assert/strict';
import {createClientHttpHandler} from './client-http.mjs';

test('HTTP ingress requires Request preparation before installing a handler', () => {
  let calls = 0;
  const installation = {
    authenticate() {calls++; return 'principal';},
    authorizeConnection() {calls++; return true;},
  };
  // Missing preparation cannot select an unprepared dispatch route. The
  // rejection is installation failure, not a submitted operation outcome.
  assert.throws(() => createClientHttpHandler(installation),
    {name: 'TypeError', message: 'InvalidClientHostInstallation'});
  assert.equal(calls, 0);
});
