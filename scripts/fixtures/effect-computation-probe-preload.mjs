// Test-only preload for an actual Host entry, including an installed tarball.
// The parent creates the log. Never truncate it when a Host process restarts.
import {appendFileSync} from 'node:fs';
import {mock} from 'node:test';
import {installEffectComputationProbe} from './effect-computation-probe.mjs';

const entry = process.env.ACTQL_TEST_EFFECT_ENTRY;
const log = process.env.ACTQL_TEST_EFFECT_CALL_LOG;
if (!entry || !log || !entry.startsWith('file:')) {
  throw new TypeError('EffectComputeProbeConfigurationRequired');
}
await installEffectComputationProbe(entry, () => appendFileSync(log, 'compute\n'));
const source = process.env.ACTQL_TEST_ACQUIRED_SOURCE_ENTRY;
if (source !== undefined) {
  if (!source.startsWith('file:')) throw new TypeError('InvalidSourceProbeEntry');
  const actual = await import(source);
  if (typeof actual.openCapturedDuckDBSource !== 'function') {
    throw new TypeError('SourceProbeEntryUnavailable');
  }
  mock.module(source, {namedExports: {...actual,
    openCapturedDuckDBSource(...args) {
      appendFileSync(log, 'source\n');
      return actual.openCapturedDuckDBSource(...args);
    }}});
  appendFileSync(log, 'source-probe\n');
}
appendFileSync(log, 'probe\n');
