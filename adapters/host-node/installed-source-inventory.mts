import {isAbsolute} from 'node:path';
import {installedCanonicalTextConstructionShape} from './installed-check-environment-construction.mjs';
import {composeInstalledInventoryEnvironment} from './installed-funded-environment.mjs';
import {verifyInstalledConnectorBindings} from './installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {captureSourceAliasConstruction,
  sourceMemberCollectionConstructionGeometry, sourceReferenceCollectionConstructionGeometry,
  sourceBindingCollectionConstructionGeometry, sourceAliasCollectionConstructionGeometry,
  sourceCheckpointInventoryConstructionGeometry} from './source-alias-construction.mjs';
import type {ConfigurationReader} from './source-alias-construction.mjs';
import type {splitSourceAliasProfile} from './source-alias-publication.mjs';
import type {createLocalAuthorizationGate} from './local-account-config.mjs';

type SourceConstructor = ReturnType<typeof captureSourceAliasConstruction>;
type SourceSelector = Readonly<{admitsSource: (sourceRef: string) => boolean}>;
type SourceReadAccess = Readonly<{
  sourceRef: string;
  connection?: string;
  resource?: string;
  authorization?: Readonly<{authorize?: unknown}>;
}>;
type ReadableSource<Access extends SourceReadAccess = SourceReadAccess> = Partial<SourceSelector> & Readonly<{
  sourceAccess: Access;
  sourceReadAccesses?: readonly Access[];
  readAuthorization?: Readonly<{accountConfiguration?: unknown; context?: unknown}>;
  ledgerCapacity?: unknown;
}>;
type SourceProfile<Member> = (Member & {sources?: undefined}) | Readonly<{sources: readonly Member[]}>;
type SourcePaths = Readonly<{sourceProfilePath?: string; sourceProfilePaths?: unknown}>;
type CheckpointConfiguration = Readonly<{
  sourceRef: string;
  accountConfiguration: unknown;
  context: unknown;
}>;
type AccountGate = Awaited<ReturnType<typeof createLocalAuthorizationGate>>;
type CheckpointSource = {
  configuration: CheckpointConfiguration;
  gate: AccountGate | undefined;
  resumeGate: AccountGate | undefined;
};
type AuthorizationBinding = {
  source_ref: string;
  configuration_cid: string | null | undefined;
  context_cid: string | undefined;
};
type CheckpointCustody = {
  holder: Readonly<{environment: () => unknown; release: () => unknown}> | undefined;
  retire(): boolean;
};

type EnvironmentOriginal = ReturnType<typeof composeInstalledInventoryEnvironment>;
type EnvironmentInputs = Parameters<typeof composeInstalledInventoryEnvironment>;
type ConnectorBinding = Readonly<{connectorId: string; bindingCid: string}>;
export type InventoryMember = ReadableSource & SourceSelector & Readonly<{
  realizationKey: string;
  environmentWire: string;
  environmentOriginal?: EnvironmentOriginal;
  connectorBindings?: readonly ConnectorBinding[];
  queryAliases: ReturnType<typeof splitSourceAliasProfile>['queryAliases'];
  close: () => unknown;
}>;
export type LoadOptions = Readonly<{
  installationServices?: EnvironmentInputs[0];
  moon: EnvironmentInputs[1];
  baseEnvironmentWire: EnvironmentInputs[2];
  root: string;
  principalId: string;
  runtimeUrl?: string | URL;
  resolveSecret?: unknown;
  connectorTable?: unknown;
}>;
type InventoryLoaderPorts = Readonly<{
  loadInstalledSource: {
    (path: string, options: LoadOptions): Promise<InventoryMember>;
    (path: string | undefined, options: LoadOptions): Promise<InventoryMember | undefined>;
  };
  installedSourceConfigurationReader(services: EnvironmentInputs[0]): ConfigurationReader;
  installedSourceEnvironmentConstructionReader(services: LoadOptions['installationServices'],
    moon: LoadOptions['moon']): unknown;
}>;

// Installation inventory is bounded and inert. Only a checked acquisition
// occurrence selects a member later; installing a binding never reads it.
export function installedSourceReadAccesses<Access extends SourceReadAccess>(source: ReadableSource<Access>) {
  const accesses = source.sourceReadAccesses ?? [source.sourceAccess];
  if (!Array.isArray(accesses) || accesses.length === 0) {
    throw new TypeError('InvalidInstalledSourceReadAccesses');
  }
  if (source.sourceReadAccesses !== undefined) {
    const refs = new Set();
    for (const access of accesses) {
      if (typeof access?.sourceRef !== 'string' ||
          typeof access.connection !== 'string' ||
          access.connection !== source.sourceAccess?.connection ||
          typeof access.resource !== 'string' ||
          access.authorization !== source.sourceAccess?.authorization ||
          typeof source.admitsSource !== 'function' ||
          !source.admitsSource(access.sourceRef) ||
          refs.has(access.sourceRef)) {
        throw new TypeError('InvalidInstalledSourceReadAccesses');
      }
      refs.add(access.sourceRef);
    }
  }
  return accesses;
}

export function installedSourceReadBindings(source: ReadableSource) {
  if (typeof source.sourceAccess?.authorization?.authorize !== 'function' ||
      typeof source.ledgerCapacity !== 'function' ||
      typeof source.admitsSource !== 'function') {
    throw new TypeError('InstalledMultiSourceUnsupported');
  }
  const refs = [];
  for (const access of installedSourceReadAccesses(source)) {
    if (typeof access?.sourceRef !== 'string' ||
        typeof access.connection !== 'string' ||
        typeof access.resource !== 'string' ||
        access.authorization !== source.sourceAccess.authorization ||
        !source.admitsSource(access.sourceRef)) {
      throw new TypeError('InstalledMultiSourceUnsupported');
    }
    refs.push(access.sourceRef);
  }
  if (new Set(refs).size !== refs.length) {
    throw new TypeError('InstalledSourceBindingAmbiguous');
  }
  return refs;
}

export function installedSourcePaths({sourceProfilePath, sourceProfilePaths}: SourcePaths = {},
  fallback = process.env.ACTQL_LOCAL_SOURCE_PROFILE, construct?: SourceConstructor) {
  const select = () => {
    if (sourceProfilePaths !== undefined) {
      if (sourceProfilePath !== undefined || fallback !== undefined ||
          !validPluralSourcePaths(sourceProfilePaths)) {
        throw new TypeError('InvalidInstalledSourceProfiles');
      }
      return Object.freeze([...sourceProfilePaths]);
    }
    const path = sourceProfilePath ?? fallback;
    return path === undefined ? Object.freeze([]) : Object.freeze([path]);
  };
  if (construct === undefined) return select();
  // The normal caller borrows the same detached Host input. Quote the actual
  // returned array and plural validation's temporary array/Set before either
  // constructor; retain an environment-selected path's text on this material.
  const count = Array.isArray(sourceProfilePaths) ? BigInt(sourceProfilePaths.length)
    : sourceProfilePath !== undefined || fallback !== undefined ? 1n : 0n;
  const text = sourceProfilePath === undefined && sourceProfilePaths === undefined &&
    typeof fallback === 'string' ? 2n * BigInt(fallback.length) : 0n;
  return construct({retained: {nodes: count + 1n, text, wire: 0n},
    workspace: {nodes: 2n * count + 2n, text: 0n, wire: 0n}}, select);
}

function validPluralSourcePaths(paths: unknown): paths is readonly string[] {
  return Array.isArray(paths) && paths.length >= 2 &&
    Array.from(paths).every(path => typeof path === 'string' && isAbsolute(path)) &&
    new Set(paths).size === paths.length;
}

// Prepare the plural Checkpoint DATA before completing the SAME initial
// Source material. Account admission/currentness still occurs in Checkpoints;
// these slots and the existing body borrow issue no read or resume permission.
export function prepareInstalledSourceCheckpointInventory(profile: SourceProfile<ReadableSource> | undefined, construct: SourceConstructor) {
  if (profile === undefined) return undefined;
  const members = profile.sources;
  let count = 0n, sourceRefUnits = 0n;
  const sourceRefShape = {output: 0n, normalized: 0n};
  const observe = (source: ReadableSource) => {
    for (const access of installedSourceReadAccesses(source)) {
      count++;
      sourceRefUnits += BigInt(access.sourceRef.length);
      const shape = installedCanonicalTextConstructionShape(access.sourceRef);
      sourceRefShape.output += shape.output;
      sourceRefShape.normalized += shape.normalized;
    }
  };
  if (members === undefined) observe(profile);
  else for (const member of members) observe(member);
  // Preserve the singular installation's existing ordering.
  if (members === undefined && count === 1n) return undefined;
  return construct(sourceCheckpointInventoryConstructionGeometry(count, sourceRefUnits, sourceRefShape), () => {
    const sources: CheckpointConfiguration[] = [], installedSources: CheckpointSource[] = [],
      bindings: AuthorizationBinding[] = [], accesses: SourceReadAccess[] = [], connections = new Set<string | undefined>();
    const retain = (source: ReadableSource) => {
      const authorization = source.readAuthorization;
      // Normal Source installers already own this immutable original context.
      if (authorization?.context !== undefined && !Object.isFrozen(authorization.context)) {
        throw new TypeError('InvalidInstalledSourceCheckpointContext');
      }
      for (const access of installedSourceReadAccesses(source)) {
        accesses.push(access);
        connections.add(access.connection);
        const configuration = Object.freeze({sourceRef: access.sourceRef,
          accountConfiguration: authorization?.accountConfiguration, context: authorization?.context});
        sources.push(configuration);
        installedSources.push({configuration, gate: undefined, resumeGate: undefined});
        bindings.push({source_ref: access.sourceRef, configuration_cid: undefined, context_cid: undefined});
      }
    };
    if (members === undefined) retain(profile);
    else for (const member of members) retain(member);
    // The original Host attaches a real completed-body borrow immediately
    // after Source completion, before later Checkpoint construction. Before
    // that caller enters, no Checkpoint consumer exists. It replaces this
    // cleanup callback before its first await with the actual Account flight.
    const custody: CheckpointCustody = {holder: undefined, retire() {
      if (custody.holder !== undefined) {
        custody.holder.release();
        custody.holder = undefined;
      }
      return true;
    }};
    return Object.freeze({sources: Object.freeze(sources), installedSources, bindings, custody,
      accesses: Object.freeze(accesses), connections: Object.freeze([...connections].sort())});
  });
}

export function createInstalledSourceInventoryLoader({loadInstalledSource,
  installedSourceConfigurationReader, installedSourceEnvironmentConstructionReader}: InventoryLoaderPorts) {
  return async function loadInstalledSources(paths: readonly string[], options: LoadOptions) {
    // Capture the options once: later callbacks cannot switch the admitted
    // service/runtime or revive a missing-services diagnostic path.
    options = Object.freeze({...options});
    installedSourceEnvironmentConstructionReader(options?.installationServices, options?.moon);
    if (paths.length < 2) return loadInstalledSource(paths[0], options);
    if (!validPluralSourcePaths(paths)) {
      throw new TypeError('InvalidInstalledSourceProfiles');
    }
    const configurationReader = options.installationServices === undefined ? undefined
      : installedSourceConfigurationReader(options.installationServices);
    const construct = captureSourceAliasConstruction(configurationReader!, options.moon);
    const {sources, closed} = construct(sourceMemberCollectionConstructionGeometry(BigInt(paths.length)),
      () => ({sources: [] as InventoryMember[], closed: new Set<InventoryMember>()}));
    const close = async () => {
      const failures = [];
      for (const source of sources) {
        if (closed.has(source)) continue;
        try { await source.close(); closed.add(source); }
        catch (error) { failures.push(error); }
      }
      if (failures.length) throw new AggregateError(failures, 'InstalledSourceCleanupPending');
    };
    try {
      for (const path of paths) {
        const source = await loadInstalledSource(path, options);
        sources.push(source);
      }
      // All original member constructors are now retained. Observe their exact
      // inventory before allocating the aggregate membership Set; no provider
      // read can start before this complete duplicate check and composition.
      let references = 0n, bindingCount = 0n;
      for (const source of sources) {
        references += BigInt(source.sourceReadAccesses?.length ?? 1);
        bindingCount += BigInt(source.connectorBindings?.length ?? 0);
      }
      construct(sourceReferenceCollectionConstructionGeometry(references), () => {
        const refs = new Set();
        for (const source of sources) {
        // Each independently installed source must have an exact checked
        // occurrence and an owned capacity before any read may start.
          for (const ref of installedSourceReadBindings(source)) {
            if (refs.has(ref)) throw new TypeError('InstalledSourceBindingAmbiguous');
            refs.add(ref);
          }
        }
        return Object.freeze({});
      });
      let environmentWire: string | undefined, environmentOriginal: EnvironmentOriginal | undefined;
      const bindings = construct(sourceBindingCollectionConstructionGeometry(bindingCount), () => new Map<string, ConnectorBinding>());
      for (const source of sources) {
        if (source.environmentOriginal !== undefined && source.environmentOriginal.wire !== source.environmentWire) {
          throw new TypeError('ForeignInstalledEnvironmentOriginal');
        }
        const combinedOriginal = composeInstalledInventoryEnvironment(options.installationServices!, options.moon,
            options.baseEnvironmentWire, environmentOriginal, source.environmentOriginal ?? source.environmentWire, () => {
              verifyInstalledConnectorBindings(environmentWire === undefined ? undefined
                : {environmentWire, connectorBindings: [...bindings.values()]}, source);
              return source === sources.at(-1);
            });
        const combined = combinedOriginal.wire;
        environmentWire = combined;
        environmentOriginal = combinedOriginal;
        // Validate a member's own duplicates before coalescing matching physical
        // bindings across members. Preserve the original declaration order.
        for (const binding of source.connectorBindings ?? []) {
          if (!bindings.has(binding.connectorId)) {
            bindings.set(binding.connectorId, binding);
          }
        }
      }
      Object.freeze(sources);
      const {queryAliases} = construct(sourceAliasCollectionConstructionGeometry(sources), () => {
        // Every row/request is the original immutable profile snapshot. This
        // stage owns only the aggregate list and duplicate-name collections.
        const queryAliases = Object.freeze(sources.flatMap(source => source.queryAliases));
        if (new Set(queryAliases.map(alias => alias.name)).size !== queryAliases.length) {
          throw new TypeError('InvalidPublicSourcePublication');
        }
        return Object.freeze({queryAliases});
      });
      return Object.freeze({
        realizationKey: sources.every(source =>
          source.realizationKey === 'duckdb-acquired')
          ? 'duckdb-acquired' : 'installed-multi-acquired', environmentWire, environmentOriginal,
        sources: Object.freeze(sources),
        connectorBindings: Object.freeze([...bindings.values()]),
        queryAliases,
        admitsSource: (ref: string) => sources.some(source => source.admitsSource(ref)),
        close,
      });
    } catch (cause) {
      throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: {close}});
    }
  };
}

export function installedSourceFor<Member extends SourceSelector>(profile: SourceProfile<Member> | undefined,
  sourceRef: string) {
  const matches = (profile?.sources ?? (profile === undefined ? [] : [profile]))
    .filter(source => source.admitsSource(sourceRef));
  if (matches.length !== 1) throw new Error('InstalledSourceProgramMismatch');
  return matches[0];
}
