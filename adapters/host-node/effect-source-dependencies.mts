import {types} from 'node:util';
import {installedEffectDependencyOriginal} from '../host-common/installed-effect-dependency-original.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {retainCompletedEffectDependencyPayloads} from '../host-common/completed-run-publication.mjs';

type Retention = Parameters<typeof retainCompletedEffectDependencyPayloads>[0];
type Limits = Parameters<Retention['control']['admit']>[2];
type Construction = Retention['dependencyConstruction'];
type Artifact = Retention['dependencies'][number]['artifact'] & Readonly<{
  derivationWire: string; orderingWire: string;
}>;
type Body = Readonly<{kind: string; wire: string}>;
type Payload = Readonly<{
  localResultArtifact: Artifact;
  localResultDefinition: Readonly<{wire: string}>;
  localInvocation: Readonly<{wire: string}>;
  localManifest: Readonly<{identity: string; wire: string}>;
  dependencyBodies: readonly Body[];
}> & Pick<Retention['dependencies'][number], 'physical' | 'prepared'>;
type SourceSet = Readonly<{
  dependencies: readonly Readonly<{payload: Payload}>[];
  members: readonly Readonly<{payload: Payload}>[];
}>;
type InventoryControl = Readonly<{
  prepareLocalEffectDependencyInventory(artifacts: readonly Artifact[], bodies: readonly unknown[],
    limits: Limits, construction: Construction, originalArtifacts: readonly Artifact[]): string;
}>;
type InventoryOptions = Readonly<{
  sources: SourceSet; store: Retention['store']; control: InventoryControl;
  contractLimits: Limits; dependencies?: readonly unknown[];
}>;
type RetentionOptions = Pick<Retention, 'execution' | 'store' | 'storedResults' | 'runDefinition'> &
  Readonly<{sources: SourceSet; control: Retention['control'] & InventoryControl}>;
type SetOwner = Readonly<{
  store: unknown; control: unknown; contractLimits: Limits; dependencyConstruction?: Construction;
  runtime: Readonly<{
    clientProgramInstalledEffectDependencyGroupReserve(parent: unknown, prepared: unknown, request: unknown,
      plan: unknown, candidates: number, members: number): unknown;
  }>;
}>;
type CustodyPorts = Readonly<{
  preparedEffectSourceOwners: Pick<WeakMap<object, Readonly<{tableInput: boolean}>>, 'get'>;
  preparedEffectSourceSets: Pick<WeakMap<object, SetOwner>, 'get'>;
  adoptedEffectSourceDependencies: Pick<WeakSet<object>, 'add'>;
}>;

export function createPinnedEffectSourceDependencies({
  preparedEffectSourceOwners, preparedEffectSourceSets, adoptedEffectSourceDependencies,
}: CustodyPorts) {
  // Assemble existing owned Results, never caller-authored roots. Additional
  // acquisition/checked-environment bodies must close those exact references;
  // MoonBit rejects missing, foreign, conflicting or unused dependencies.
  function preparePinnedEffectDependencyInventory({
    sources, store, control, contractLimits, dependencies = [],
  }: InventoryOptions) {
    const owner = preparedEffectSourceSets.get(sources);
    if (owner?.store !== store || owner?.control !== control ||
        !Array.isArray(sources?.dependencies) ||
        !Array.isArray(dependencies) || owner?.dependencyConstruction === undefined && dependencies.length > 4096) {
      throw new TypeError('InvalidEffectDependencySetOwner');
    }
    const construction = owner!.dependencyConstruction;
    if (construction !== undefined) {
      const original = installedEffectDependencyOriginal(construction, owner!.runtime);
      // Count every actual retained candidate before Set/parse/selection/DTO
      // arrays. The optional Manifest can later be omitted by exact imports.
      let candidates = dependencies.length;
      for (const {payload} of sources.dependencies) candidates += payload.dependencyBodies.length + 6;
      checked(owner!.runtime.clientProgramInstalledEffectDependencyGroupReserve(original.parent,
        original.prepared, original.request, original.plan, candidates, sources.members.length));
      original.current();
    }
    const bodies: unknown[] = [], originalArtifacts: Artifact[] = [];
    const aliases = construction === undefined ? undefined : new Set<object>();
    const append = (body: unknown) => {
      // The private acquisition vector is shared by every Result path. Only
      // an identical immutable DATA record can bypass a second wire traversal.
      // Separate objects still receive Core's metered full-wire/CID comparison.
      if (aliases !== undefined && body !== null && typeof body === 'object' &&
          !types.isProxy(body) && Object.isFrozen(body) &&
          (Object.getPrototypeOf(body) === Object.prototype || Object.getPrototypeOf(body) === null)) {
        const kind = Object.getOwnPropertyDescriptor(body, 'kind'),
          wire = Object.getOwnPropertyDescriptor(body, 'wire'),
          cid = Object.getOwnPropertyDescriptor(body, 'cid');
        if (kind && wire && Object.hasOwn(kind, 'value') && Object.hasOwn(wire, 'value') &&
            typeof kind.value === 'string' && typeof wire.value === 'string' &&
            (cid === undefined || Object.hasOwn(cid, 'value') && typeof cid.value === 'string')) {
          if (aliases.has(body)) return;
          aliases.add(body);
        }
      }
      if (construction === undefined && bodies.length >= 4096) throw new RangeError('EffectDependencyEntryLimit');
      bodies.push(body);
    };
    // A Manifest is a dependency only when an actual consumer import names
    // it. The final Effect source Artifact is itself a root, not an import
    // of its own Manifest. MoonBit revalidates every observation/Manifest edge.
    const importedManifests = new Set<unknown>();
    for (const {payload} of sources.dependencies) {
      for (const body of payload.dependencyBodies) {
        if (body.kind === 'result_import_observation') {
          importedManifests.add(JSON.parse(body.wire).producer_local_manifest_cid);
        }
      }
    }
    for (const {payload} of sources.dependencies) {
      originalArtifacts.push(payload.localResultArtifact);
      for (const body of payload.dependencyBodies) append(body);
      const table = preparedEffectSourceOwners.get(payload)?.tableInput === true;
      for (const [kind, wire] of [
        [table ? 'table_input_artifact' : 'result_artifact', payload.localResultArtifact.wire],
        [table ? 'table_input_derivation' : 'derivation_evidence', payload.localResultArtifact.derivationWire],
        [table ? 'table_input_ordering' : 'ordering_evidence', payload.localResultArtifact.orderingWire],
        [table ? 'local_table_input_definition' : 'local_result_definition', payload.localResultDefinition.wire],
        ['local_computation', payload.localInvocation.wire],
      ]) append({kind, wire});
      if (importedManifests.has(payload.localManifest.identity)) {
        append({kind: 'local_manifest', wire: payload.localManifest.wire});
      }
    }
    for (const body of dependencies) append(body);
    return control.prepareLocalEffectDependencyInventory(
      sources.members.map(({payload}) => payload.localResultArtifact),
      bodies, contractLimits, construction,
      originalArtifacts);
  }

  // Only this export set can transfer its payload owners. Public Result names
  // are not invented for upstream-only local Results. Durable capture is a
  // later obligation of the same completed owner.
  function retainPinnedEffectDependencyPayloads({
    sources, execution, store, storedResults, control, runDefinition,
  }: RetentionOptions) {
    const owner = preparedEffectSourceSets.get(sources);
    if (owner === undefined || owner.store !== store || owner.control !== control ||
        !Array.isArray(sources.dependencies)) {
      throw new TypeError('InvalidEffectDependencySetOwner');
    }
    const bindings = retainCompletedEffectDependencyPayloads({execution, store,
      storedResults, control, runDefinition,
      dependencyConstruction: owner.dependencyConstruction,
      dependencyInventoryWire: preparePinnedEffectDependencyInventory({
        sources, store, control, contractLimits: owner.contractLimits,
      }),
      dependencies: sources.dependencies.map(({payload}) => ({
        artifact: payload.localResultArtifact,
        physical: payload.physical, prepared: payload.prepared,
      })),
    });
    adoptedEffectSourceDependencies.add(sources);
    return bindings;
  }
  return {preparePinnedEffectDependencyInventory, retainPinnedEffectDependencyPayloads};
}
