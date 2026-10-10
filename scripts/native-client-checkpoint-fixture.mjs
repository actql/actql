import {generateKeyPairSync} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {nativeResolutionFixture} from './fixtures/native-effect-resolution-fixture.mjs';

// Materialize signatures for the original references compiled by Native.
// Neither statuses nor expected rows are obtained from that producer. The
// surrounding bounded test runner owns this child and the heavy-check lock.
export function nativeClientCheckpointFixture(root, env = process.env) {
  const produced = spawnSync(process.execPath, ['--input-type=module', '-e',
    'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("moon",["--target","native","src/platform_native/client_host/run_checkpoint_wbtest.mbt","--index","0"],{cwd:process.cwd()});'],
  {cwd: root, env, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024});
  process.stdout.write(produced.stdout ?? '');
  process.stderr.write(produced.stderr ?? '');
  if (produced.error || produced.signal || produced.status !== 0) {
    throw new Error(`Native Client checkpoint references failed: ${produced.error?.message ?? produced.signal ?? produced.status}`);
  }
  const marker = 'ACTQL_CLIENT_CHECKPOINT ';
  const lines = (produced.stdout ?? '').split('\n');
  const references = [];
  for (const line of lines) {
    let text = line;
    // Moon's JSON runner may put captured output in a structured line.
    try {
      const record = JSON.parse(line);
      for (const value of Object.values(record)) {
        if (typeof value === 'string' && value.includes(marker)) text = value;
      }
    } catch {}
    for (const output of text.split('\n')) {
      const index = output.indexOf(marker);
      if (index >= 0) references.push(output.slice(index + marker.length));
    }
  }
  if (references.length !== 1) throw new Error('Expected one original Native checkpoint reference');
  const signers = {reviewer: generateKeyPairSync('ed25519'), host: generateKeyPairSync('ed25519')};
  const fixtures = {
    APPROVE: nativeResolutionFixture(references[0], signers),
    REJECT: nativeResolutionFixture(references[0], {...signers, decision: 'rejected'}),
    CONFLICT: nativeResolutionFixture(references[0], {...signers, resolutionId: 'another-resolution'}),
  };
  const result = {ACTQL_TEST_CLIENT_HOST_PUBLIC_KEY: fixtures.APPROVE.ACTQL_TEST_EFFECT_HOST_PUBLIC_KEY};
  for (const [mode, fixture] of Object.entries(fixtures)) {
    result[`ACTQL_TEST_CLIENT_${mode}_RESOLUTION_WIRE`] = fixture.ACTQL_TEST_EFFECT_RESOLUTION_WIRE;
    result[`ACTQL_TEST_CLIENT_${mode}_VERIFIED_WIRE`] = fixture.ACTQL_TEST_EFFECT_VERIFIED_WIRE;
  }
  return result;
}
