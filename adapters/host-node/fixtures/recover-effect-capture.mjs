// Fresh-process probe for the encrypted completed-computation custody path.
// The parent supplies only public Run identity and test Store configuration.
import {readFileSync} from 'node:fs';
import * as moon from
  '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {recoverCompletedEffectfulComputation} from
  '../../host-common/completed-run-publication.mjs';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from
  '../../store-local/publication-store.mjs';

const input = JSON.parse(readFileSync(0, 'utf8'));
const control = runtimeCore(moon).publicationControl;
const store = await openLocalPublicationStore({
  directory: input.directory,
  storeAuthorityCid: input.storeAuthorityCid,
  capacityBytes: input.capacityBytes,
  maxObjectBytes: input.maxObjectBytes,
  maxObjects: input.maxObjects,
  maxContractNodes: input.maxContractNodes,
  maxContractDepth: input.maxContractDepth,
  privateEvidenceKey: Buffer.alloc(32, 4),
}, control);
try {
  const runDefinition = control.admit('run_definition',
    input.runDefinitionWire, input.limits);
  const recovered = await recoverCompletedEffectfulComputation({
    store, control, runDefinition, contractLimits: input.limits,
  });
  const answer = {
    capturedRunCid: recovered.computation.capturedRun.identity,
    artifactCids: recovered.storedResults.artifacts.map(value =>
      value.identity),
  };
  for (const result of recovered.storedResults.results) {
    if (result.prepared.status().pending) {
      await result.prepared.release();
    }
  }
  process.stdout.write(JSON.stringify(answer));
} finally {
  await store.close();
}
