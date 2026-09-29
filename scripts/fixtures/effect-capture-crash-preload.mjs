// Test-only process termination at an actual Store commit boundary.
import {writeFileSync} from 'node:fs';
import {mock} from 'node:test';

const savedPath = process.env.ACTQL_TEST_CAPTURE_CRASH_RECORD;
const boundary = process.env.ACTQL_TEST_CAPTURE_CRASH_BOUNDARY;
const before = boundary?.startsWith('before-') === true;
const namespace = before ? boundary.slice(7) : boundary;
if (!savedPath || !['effect-source', 'effect-capture', 'publication-private']
  .includes(namespace)) throw new Error('InvalidCaptureCrashProbe');
let configuration;
let evidence;
const publicationUrl = new URL('../../adapters/host-common/completed-run-publication.mjs',
  import.meta.url).href;
const publication = await import(publicationUrl);
mock.module(publicationUrl, {namedExports: {...publication,
  storeCompletedRunResultSet(options) {
    evidence = {runDefinition: options.runDefinition,
      contractLimits: options.contractLimits};
    return publication.storeCompletedRunResultSet(options);
  }}});
const storeUrl = new URL('../../adapters/store-local/publication-store.mjs',
  import.meta.url).href;
const actual = await import(storeUrl);
mock.module(storeUrl, {namedExports: {...actual,
  async openLocalPublicationStore(options, control, durability) {
    configuration = options;
    const store = await actual.openLocalPublicationStore(options, control, durability);
    return Object.freeze({...store, async commitPhysicalHolding(record, ...args) {
      const stop = () => {
        // Only fixture-generated values are written into this local scratch
        // record. No product secret resolver or real credential is used.
        writeFileSync(savedPath, JSON.stringify({configuration, ...evidence,
          boundary, holding: record}));
        process.exit(77); // Deliberately bypass finally and normal close.
      };
      if (before && evidence && record.namespace === namespace) stop();
      const result = await store.commitPhysicalHolding(record, ...args);
      if (!before && evidence && record.namespace === namespace) stop();
      return result;
    }});
  }}});
