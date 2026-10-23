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

const expressionConfiguration: WorkersFiniteConfiguration = {...configuration,
  fragments: {contract: 'installed-fragment', ordered: 'installed-ordered', limits: {
    roots: {max_roots: 10, max_pointer_bytes: 100, max_work: 1000},
    demands: {max_roots: 10, max_nodes: 100, max_work: 1000, max_text_bytes: 100, max_links: 100},
    physical: {max_body_bytes: 1000, max_body_nodes: 100, max_body_depth: 10},
    logical: {max_input_rows: 100n, max_value_bytes: 1000n,
      max_live_value_bytes: 10000n, max_work: 10000n},
    max_input_rows: 100n, max_value_bytes: 1000n}}};
createWorkersFiniteRuntime(0, expressionConfiguration);
// @ts-expect-error an expression contract alone cannot infer preparation/runtime budgets
createWorkersFiniteRuntime(0, {...configuration, fragments: {contract: 'no-limits'}});
const invalidRows: NonNullable<WorkersFiniteConfiguration['fragments']>['limits']['logical'] =
  // @ts-expect-error runtime logical ceilings preserve exact Int64 quantities
  {max_input_rows: 100, max_value_bytes: 1000n, max_live_value_bytes: 10000n, max_work: 10000n};
void invalidRows;
