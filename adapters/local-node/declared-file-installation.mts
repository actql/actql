// The Host's generic declared-file implementation inventory. Connection names
// select logical Catalog namespaces; configured providers remain separate DATA.
// This entry supplies no Account decision, physical read or Effect approval.
import {createInstalledConnectorTable, installedConnectorForTable,
  loadInstalledConnectorModule, loadInstalledEffectModule,
  verifyInstalledConnectorRegistration} from '../host-node/installed-connectors.mjs';
import {beginInstalledSourceInitialization, finishInstalledSourceInitialization,
  retainInstalledHostServiceInstallation, reserveInstalledSourceRuntimeIdentity,
  retainBoundInstalledSourceFailure, withInstalledSourceLoading, installedSourceConfigurationReader}
  from '../host-node/installed-host-services.mjs';
import {createInstalledRowSource} from '../host-node/installed-row-source.mjs';
import {createInstalledRowEffect} from '../host-node/installed-row-effect.mjs';
import type {loadInstalledProjectConnections} from '../host-node/installed-project-connections.mjs';
import {installedProjectOriginalsForRuntime} from '../host-node/installed-project-configuration.mjs';

type Role = 'source' | 'effect';
type ProjectOriginal = ReturnType<typeof installedProjectOriginalsForRuntime>;
type ConnectionOriginal = ReturnType<Awaited<ReturnType<typeof loadInstalledProjectConnections>>['originalsForRuntime']>;
type Entry = ReturnType<typeof installedConnectorForTable>;
type Context = NonNullable<ReturnType<typeof beginInstalledSourceInitialization>>;
type PreparationMethod = 'prepareNativeInput' | 'prepareNativeDeclaration' | 'prepareMappings' | 'prepareBorrowedDeclaration';
type Prepared = Readonly<{
  declaration?: unknown;
  declared?: unknown;
  environment?: Readonly<{wire: string}>;
  mappings?: unknown;
  commands?: unknown;
}>;
type Profile = Readonly<{
  version: string;
  connection: string;
  connectorId: string;
  providerNamespace: string;
}>;
type Projection<Value> = Readonly<{capacity(): unknown; project(): Value}>;
type Runtime = Readonly<{
  clientProjectConnectionsCount(connections: unknown): number;
  clientProjectConnectionsName(connections: unknown, index: number): string | undefined;
  clientProjectConnectionsConnector(connections: unknown, index: number): string | undefined;
}>;
type InventoryOptions = Readonly<{
  moon: Runtime;
  project: unknown;
  services?: object;
  baseEnvironmentWire: string;
  runtimeUrl?: string | URL;
  assertCurrent(): unknown;
}>;
type InventoryOriginal = Readonly<{
  moon: Runtime;
  projectOriginal: ProjectOriginal;
  current(): void;
}>;
type AdapterOptions = Readonly<Record<string, unknown>>;
type Member = Readonly<{
  connection: string | undefined;
  connectorId: string | undefined;
  providerNamespace: string | undefined;
  registration?: string;
  revision?: string;
  runtimeBundleCid: string;
  sourceInitialization: Context;
  prepareNativeInput: OmitThisParameter<Context['prepareNativeInput']>;
  prepareNativeDeclaration: OmitThisParameter<Context['prepareNativeDeclaration']>;
  prepareMappings: OmitThisParameter<Context['prepareMappings']>;
  prepareBorrowedDeclaration(sourceMember: unknown): ReturnType<Context['prepareBorrowedDeclaration']>;
  load(options: AdapterOptions): Promise<unknown>;
  cleanup(cause: unknown): Promise<unknown>;
}>;
type ConnectionRecord = {
  connections: ConnectionOriginal;
  index: number;
  role: Role;
  entry: Entry;
  profile: Readonly<Partial<Profile>>;
  context?: Context;
  prepared?: Prepared;
  adapter?: unknown;
  identity?: unknown;
  flight?: Promise<Member>;
  loadFlight?: Promise<unknown>;
  cleanupFlight?: Promise<unknown>;
  loading: boolean;
  finished: boolean;
  failed: boolean;
  failure?: unknown;
};

const fail: (code: string) => never = code => {throw Object.assign(new TypeError(code), {code});};
const issuedInventories = new WeakMap<object, InventoryOriginal>();

// Lookup only: the existing Source material remains the construction owner.
export function assertDeclaredFileInstallationInventory(inventory: unknown, moon: unknown, projectOriginal: unknown) {
  const retained = issuedInventories.get(inventory as object);
  if (retained === undefined || retained.moon !== moon || retained.projectOriginal !== projectOriginal) {
    fail('ForeignDeclaredFileInstallation');
  }
  retained.current();
}

const registration = 'declared_file', revision = 'declared_file/0.1';
const versions = Object.freeze({source: 'actql-installed-declared-file-source/0.1',
  effect: 'actql-installed-declared-file-effect/0.1'});
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !value.includes('\0');

function checkProfile(profile: Readonly<Partial<Profile>> | undefined, role: Role): Profile {
  if (!profile || !Object.isFrozen(profile) || profile.version !== versions[role] ||
      !text(profile.connection) || profile.connectorId !== profile.connection ||
      !text(profile.providerNamespace) ||
      Object.keys(profile).sort().join('\0') !==
        ['connection', 'connectorId', 'providerNamespace', 'version'].join('\0')) {
    fail('InvalidDeclaredFileInstallationProfile');
  }
  return profile as Profile;
}

const sourceModule = Object.freeze({
  check: (profile: Readonly<Partial<Profile>>) => checkProfile(profile, 'source'),
  identityParts: (profile: Readonly<Partial<Profile>>) => [checkProfile(profile, 'source')],
  load: (profile: Readonly<Partial<Profile>>, options: AdapterOptions) => {
    checkProfile(profile, 'source');
    return createInstalledRowSource(options as Parameters<typeof createInstalledRowSource>[0]);
  },
});
const effectModule = Object.freeze({
  check: (profile: Readonly<Partial<Profile>>) => checkProfile(profile, 'effect'),
  identityParts: (profile: Readonly<Partial<Profile>>) => [checkProfile(profile, 'effect')],
  load: (profile: Readonly<Partial<Profile>>, options: AdapterOptions) => {
    checkProfile(profile, 'effect');
    return createInstalledRowEffect(options as Parameters<typeof createInstalledRowEffect>[0]);
  },
});
// Normal table admission snapshots the implementation and records its actual
// entries. Never register a copied descriptor or a profile label as a service.
const table = createInstalledConnectorTable([{
  name: registration, registration, revision,
  source: {profileVersion: versions.source, load: async () => sourceModule},
  effect: {profileVersion: versions.effect, load: async () => effectModule},
}]);

export function createDeclaredFileInstallationInventory({moon, project, services,
  baseEnvironmentWire, runtimeUrl, assertCurrent}: InventoryOptions) {
  if (typeof assertCurrent !== 'function' || typeof baseEnvironmentWire !== 'string' ||
      services === undefined || runtimeUrl === undefined) fail('DeclaredFileInstallationUnavailable');
  const projectOriginal = installedProjectOriginalsForRuntime(project, moon);
  const count = moon.clientProjectConnectionsCount, name = moon.clientProjectConnectionsName,
    connector = moon.clientProjectConnectionsConnector;
  if (![count, name, connector].every(value => typeof value === 'function')) {
    fail('InstalledProjectRuntimeUnavailable');
  }
  const records: ConnectionRecord[] = [], flights = new Set<Promise<unknown>>(), members = new WeakMap<object, ConnectionRecord>();
  let runtimeFlight: Promise<string> | undefined, retiring = false, cleanupFlight: Promise<void> | undefined;
  const current = () => {
    if (retiring) fail('DeclaredFileInstallationClosed');
    if (assertCurrent() !== undefined || installedProjectOriginalsForRuntime(project, moon) !== projectOriginal) {
      fail('ForeignDeclaredFileInstallation');
    }
  };
  async function failRecord(record: ConnectionRecord, cause: unknown) {
    if (record.finished || record.context === undefined) return cause;
    if (record.cleanupFlight !== undefined) return record.cleanupFlight;
    record.cleanupFlight = (async () => {
      const failure = await retainBoundInstalledSourceFailure(record.context!, cause, record.adapter);
      finishInstalledSourceInitialization(record.context, record.adapter, failure, true);
      record.finished = true;
      return failure;
    })();
    return record.cleanupFlight;
  }
  const metadataReader = installedSourceConfigurationReader(services);
  if (typeof metadataReader?.readUtf8 !== 'function' ||
      typeof metadataReader?.prepareNativeInput !== 'function') fail('DeclaredFileInstallationUnavailable');
  const inventory = Object.freeze({
    readMetadataUtf8(path: string, maxBytes: number) {
      current();
      return metadataReader.readUtf8(path, {maxBytes});
    },
    prepareMetadataInput<Value extends object & Readonly<{then?: never}>>(projection: Projection<Value>) {
      current();
      const value = metadataReader.prepareNativeInput(projection);
      current();
      return value;
    },
    begin(connectionOriginal: ConnectionOriginal | undefined, index: number, role: Role = 'source') {
      current();
      if (!Object.hasOwn(versions, role) || connectionOriginal?.project !== projectOriginal ||
          connectionOriginal.connections === undefined || !Number.isSafeInteger(index) || index < 0) {
        fail('ForeignDeclaredFileInstallation');
      }
      const previous = records.find(record => record.connections === connectionOriginal &&
        record.index === index && record.role === role);
      if (previous !== undefined) return previous.flight!;
      const total = Reflect.apply(count, moon, [connectionOriginal.connections]);
      if (!Number.isSafeInteger(total) || total < 1 || total > 128 || index >= total) {
        fail('InvalidDeclaredFileInstallationProfile');
      }
      const connection = Reflect.apply(name, moon, [connectionOriginal.connections, index]);
      const providerNamespace = Reflect.apply(connector, moon, [connectionOriginal.connections, index]);
      const profile = Object.freeze({version: versions[role], connection,
        connectorId: connection, providerNamespace});
      const entry = installedConnectorForTable(table, role, profile);
      const record: ConnectionRecord = {connections: connectionOriginal, index, role, entry, profile,
        context: undefined, prepared: undefined, adapter: undefined,
        loading: false, finished: false, failed: false, failure: undefined};
      records.push(record);
      // Install the original flight before module loading/current callbacks.
      record.flight = Promise.resolve().then(() => withInstalledSourceLoading(services, async () => {
        current();
        const module = await (role === 'source' ? loadInstalledConnectorModule(entry)
          : loadInstalledEffectModule(entry));
        current();
        const checked = module.check(profile) as Profile;
        record.identity = await module.identityParts(checked);
        current();
        runtimeFlight ??= Promise.resolve().then(() => {
          const read = reserveInstalledSourceRuntimeIdentity(services);
          if (typeof read !== 'function') fail('InstalledSourceInitializationUnavailable');
          return read(runtimeUrl);
        });
        const runtimeBundleCid = await runtimeFlight;
        current();
        retainInstalledHostServiceInstallation(services, entry, runtimeBundleCid);
        const context = beginInstalledSourceInitialization(services, entry,
          checked.connectorId, baseEnvironmentWire, role);
        if (context === undefined) fail('InstalledSourceInitializationUnavailable');
        record.context = context;
        const memberCurrent = () => {
          current();
          if (record.finished || record.failed) fail('DeclaredFileInstallationClosed');
        };
        const prepare = <Method extends PreparationMethod>(method: Method, retainPrepared = true) =>
          (...args: Parameters<Context[Method]>): ReturnType<Context[Method]> => {
          memberCurrent();
          try {
            const result = Reflect.apply(context[method] as (...args: Parameters<Context[Method]>) =>
              ReturnType<Context[Method]>, context, args);
            if (retainPrepared) record.prepared = result as Prepared;
            memberCurrent();
            return result;
          } catch (cause) {record.failed = true;record.failure = cause;throw cause;}
        };
        const member: Member = Object.freeze({connection, connectorId: connection, providerNamespace,
          registration: entry.registration, revision: entry.revision,
          runtimeBundleCid, sourceInitialization: context,
          prepareNativeInput: prepare('prepareNativeInput', false),
          prepareNativeDeclaration: prepare('prepareNativeDeclaration'),
          prepareMappings: prepare('prepareMappings'),
          prepareBorrowedDeclaration(sourceMember) {
            const source = members.get(sourceMember as object);
            if (role !== 'effect' || source?.role !== 'source' ||
                source.connections !== record.connections || source.index !== index) {
              fail('ForeignInstalledSourceConstruction');
            }
            return prepare('prepareBorrowedDeclaration')(source.context!);
          },
          async load(options) {
            memberCurrent();
            if (record.loading || record.prepared === undefined) fail('DeclaredFileInstallationAlreadyConstructed');
            record.loading = true;
            // Retain the constructor flight before options or the actual factory
            // can reenter failure. Retirement joins the same pending constructor.
            record.loadFlight = Promise.resolve().then(async () => {
              memberCurrent();
              const prepared = record.prepared!;
              const fields: Record<string, unknown> = {moon, sourceInitialization: context,
                declaration: prepared.declaration, declared: prepared.declared,
                environment: prepared.environment, environmentWire: prepared.environment?.wire,
                connectorId: checked.connectorId, connectorRegistration: entry.registration,
                connectorRevision: entry.revision};
              if (role === 'effect') Object.assign(fields, {mappings: prepared.mappings,
                ...(prepared.commands === undefined ? {} : {commands: prepared.commands}),
                runtimeBundleCid, connection});
              for (const key of Object.keys(fields)) {
                if (Object.hasOwn(options, key) && options[key] !== fields[key]) {
                  fail('ForeignInstalledSourceConstruction');
                }
              }
              const adapter = await module.load(checked, {...options, ...fields});
              record.adapter = adapter;
              memberCurrent();
              verifyInstalledConnectorRegistration(entry, adapter);
              finishInstalledSourceInitialization(context, adapter);
              record.finished = true;
              return adapter;
            }).catch(async cause => {
              record.failed = true;record.failure = cause;
              throw await failRecord(record, cause);
            });
            flights.add(record.loadFlight);
            void record.loadFlight.then(() => flights.delete(record.loadFlight!),
              () => flights.delete(record.loadFlight!));
            return record.loadFlight;
          },
          cleanup: cause => failRecord(record, cause),
        });
        members.set(member, record);
        return member;
      })).catch(async cause => {
        record.failed = true;record.failure = cause;
        throw await failRecord(record, cause);
      });
      flights.add(record.flight);
      // Observe failure without issuing a replacement or unhandled rejection.
      void record.flight.then(() => flights.delete(record.flight!), () => flights.delete(record.flight!));
      return record.flight;
    },
    fail(cause: unknown) {
      if (cleanupFlight !== undefined) return cleanupFlight;
      retiring = true;
      cleanupFlight = (async () => {
        await Promise.allSettled([...flights]);
        for (const record of records) await failRecord(record, cause);
      })();
      return cleanupFlight;
    },
  });
  current();
  issuedInventories.set(inventory, {moon, projectOriginal, current});
  return inventory;
}
