import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const groups = JSON.parse(readFileSync(new URL('./ci-native-background-groups.json', import.meta.url)));

test('macOS HTTP packages and original CLI controls use the existing two workers', () => {
  const mac = groups['native-macos'];
  assert.equal(mac.length, 2);
  const packages = mac.flatMap(group => group.steps).find(step => step.id === 'native-http');
  const controls = mac.flatMap(group => group.steps).find(step => step.id === 'native-http-controls');
  assert(packages && controls);
  assert.equal(packages.env.ACTQL_TEST_NATIVE_HTTP_FOCUS, 'http-packages');
  assert.equal(controls.env.ACTQL_TEST_NATIVE_HTTP_FOCUS, 'http-controls');
  assert(mac.find(group => group.steps.includes(packages)) !== mac.find(group => group.steps.includes(controls)));
  assert.notEqual(packages.env.ACTQL_TEST_SCRATCH_ROOT, controls.env.ACTQL_TEST_SCRATCH_ROOT);
  assert.equal(packages.run, controls.run);
  assert.equal(packages.timeoutMinutes, controls.timeoutMinutes);
});

test('the original complete HTTP path remains and both closed phases retain its original cleanup', () => {
  const source = readFileSync(new URL('./test-native-http-client.mjs', import.meta.url), 'utf8');
  assert(source.includes("'http-packages', 'http-controls'"));
  assert(source.includes("focus === 'http-controls' ? []"));
  assert(source.includes("if (focus === 'http-packages') break verification;"));
  assert(source.includes('prepareNativeHttpCompilerScope'));
  assert(source.includes('await standardGateway.close()'));
  assert(source.includes('await effectCheckpointServer?.close()'));
});
