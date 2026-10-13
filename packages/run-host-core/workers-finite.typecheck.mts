import {createWorkersFiniteRuntime, workersFiniteArtifact,
  type WorkersFiniteConfiguration, type WorkersFiniteCore,
  type WorkersFiniteOriginal, type WorkersFiniteAuthorization} from '@actql/run-host-core/workers-finite';

declare const configuration: WorkersFiniteConfiguration;
declare const original: WorkersFiniteOriginal;
declare const authorization: WorkersFiniteAuthorization;
const runtime = createWorkersFiniteRuntime(17, configuration);
const core: WorkersFiniteCore = runtime.host.core;
const profile: string = core.managedExecutionProfileCid();
const artifactCid: string = workersFiniteArtifact.componentCid;
const artifactBytes: number = workersFiniteArtifact.componentBytes;
const restored = runtime.host.admitMaterials('original body', 'expected Run CID');
const ledger = runtime.host.createLedger();
const setup = runtime.host.open(restored.preparation, {...restored, ledger}, authorization);
const result: Promise<number> = runtime.host.withExecution(setup, authorization,
  execution => execution.completed.length);
void [profile, artifactCid, artifactBytes, result];

// A copied JSON shape cannot stand in for the nominal preparation or Ledger.
// @ts-expect-error opaque preparation cannot be constructed from a plain object
runtime.host.open({}, {...original, ledger}, authorization);
// @ts-expect-error opaque Ledger cannot be constructed from a plain object
runtime.host.open(original.preparation, {...original, ledger: {}}, authorization);
// @ts-expect-error capacity is fixed by installation, never overridden per request
runtime.host.createLedger(configuration.ledger);
// @ts-expect-error caller cannot inject another runtime into the bound gate
runtime.createAuthorizationGate({runtime: {}, context: {principal: 'test', contextCid: 'cid'}, protectedSites: []});
