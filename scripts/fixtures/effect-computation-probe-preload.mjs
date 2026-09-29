// Test-only preload for an actual Host entry, including an installed tarball.
// The parent creates the log. Never truncate it when a Host process restarts.
import {appendFileSync} from 'node:fs';
import {installEffectComputationProbe} from './effect-computation-probe.mjs';

const entry = process.env.ACTQL_TEST_EFFECT_ENTRY;
const log = process.env.ACTQL_TEST_EFFECT_CALL_LOG;
if (!entry || !log || !entry.startsWith('file:')) {
  throw new TypeError('EffectComputeProbeConfigurationRequired');
}
await installEffectComputationProbe(entry, () => appendFileSync(log, 'compute\n'));
appendFileSync(log, 'probe\n');
