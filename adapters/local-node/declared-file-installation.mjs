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
import {installedProjectOriginalsForRuntime} from '../host-node/installed-project-configuration.mjs';

const fail = code => {throw Object.assign(new TypeError(code), {code});};
const registration = 'declared_file', revision = 'declared_file/0.1';
const versions = Object.freeze({source: 'actql-installed-declared-file-source/0.1',
  effect: 'actql-installed-declared-file-effect/0.1'});
const text = value => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !value.includes('\0');

function checkProfile(profile, role) {
  if (!profile || !Object.isFrozen(profile) || profile.version !== versions[role] ||
      !text(profile.connection) || profile.connectorId !== profile.connection ||
      !text(profile.providerNamespace) ||
      Object.keys(profile).sort().join('\0') !==
        ['connection', 'connectorId', 'providerNamespace', 'version'].join('\0')) {
    fail('InvalidDeclaredFileInstallationProfile');
  }
  return profile;
}

const sourceModule = Object.freeze({
  check: profile => checkProfile(profile, 'source'),
  identityParts: profile => [checkProfile(profile, 'source')],
  load: (profile, options) => {
    checkProfile(profile, 'source');
    return createInstalledRowSource(options);
  },
});
const effectModule = Object.freeze({
  check: profile => checkProfile(profile, 'effect'),
  identityParts: profile => [checkProfile(profile, 'effect')],
  load: (profile, options) => {
    checkProfile(profile, 'effect');
    return createInstalledRowEffect(options);
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
  baseEnvironmentWire, runtimeUrl, assertCurrent}) {
  if (typeof assertCurrent !== 'function' || typeof baseEnvironmentWire !== 'string' ||
      services === undefined || runtimeUrl === undefined) fail('DeclaredFileInstallationUnavailable');
  const projectOriginal = installedProjectOriginalsForRuntime(project, moon);
  const count = moon.clientProjectConnectionsCount, name = moon.clientProjectConnectionsName,
    connector = moon.clientProjectConnectionsConnector;
  if (![count, name, connector].every(value => typeof value === 'function')) {
    fail('InstalledProjectRuntimeUnavailable');
  }
  const records = [], flights = new Set(), members = new WeakMap();
  let runtimeFlight, retiring = false, cleanupFlight;
  const current = () => {
    if (retiring) fail('DeclaredFileInstallationClosed');
    if (assertCurrent() !== undefined || installedProjectOriginalsForRuntime(project, moon) !== projectOriginal) {
      fail('ForeignDeclaredFileInstallation');
    }
  };
  async function failRecord(record, cause) {
    if (record.finished || record.context === undefined) return cause;
    if (record.cleanupFlight !== undefined) return record.cleanupFlight;
    record.cleanupFlight = (async () => {
      const failure = await retainBoundInstalledSourceFailure(record.context, cause, record.adapter);
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
    readMetadataUtf8(path, maxBytes) {
      current();
      return metadataReader.readUtf8(path, {maxBytes});
    },
    prepareMetadataInput(projection) {
      current();
      const value = metadataReader.prepareNativeInput(projection);
      current();
      return value;
    },
    begin(connectionOriginal, index, role = 'source') {
      current();
      if (!Object.hasOwn(versions, role) || connectionOriginal?.project !== projectOriginal ||
          connectionOriginal.connections === undefined || !Number.isSafeInteger(index) || index < 0) {
        fail('ForeignDeclaredFileInstallation');
      }
      const previous = records.find(record => record.connections === connectionOriginal &&
        record.index === index && record.role === role);
      if (previous !== undefined) return previous.flight;
      const total = Reflect.apply(count, moon, [connectionOriginal.connections]);
      if (!Number.isSafeInteger(total) || total < 1 || total > 128 || index >= total) {
        fail('InvalidDeclaredFileInstallationProfile');
      }
      const connection = Reflect.apply(name, moon, [connectionOriginal.connections, index]);
      const providerNamespace = Reflect.apply(connector, moon, [connectionOriginal.connections, index]);
      const profile = Object.freeze({version: versions[role], connection,
        connectorId: connection, providerNamespace});
      const entry = installedConnectorForTable(table, role, profile);
      const record = {connections: connectionOriginal, index, role, entry, profile,
        context: undefined, prepared: undefined, adapter: undefined,
        loading: false, finished: false, failed: false, failure: undefined};
      records.push(record);
      // Install the original flight before module loading/current callbacks.
      record.flight = Promise.resolve().then(() => withInstalledSourceLoading(services, async () => {
        current();
        const module = await (role === 'source' ? loadInstalledConnectorModule(entry)
          : loadInstalledEffectModule(entry));
        current();
        const checked = module.check(profile);
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
        const prepare = (method, retainPrepared = true) => (...args) => {
          memberCurrent();
          try {
            const result = Reflect.apply(context[method], context, args);
            if (retainPrepared) record.prepared = result;
            memberCurrent();
            return result;
          } catch (cause) {record.failed = true;record.failure = cause;throw cause;}
        };
        const member = Object.freeze({connection, connectorId: connection, providerNamespace,
          registration: entry.registration, revision: entry.revision,
          runtimeBundleCid, sourceInitialization: context,
          prepareNativeInput: prepare('prepareNativeInput', false),
          prepareNativeDeclaration: prepare('prepareNativeDeclaration'),
          prepareMappings: prepare('prepareMappings'),
          prepareBorrowedDeclaration(sourceMember) {
            const source = members.get(sourceMember);
            if (role !== 'effect' || source?.role !== 'source' ||
                source.connections !== record.connections || source.index !== index) {
              fail('ForeignInstalledSourceConstruction');
            }
            return prepare('prepareBorrowedDeclaration')(source.context);
          },
          async load(options) {
            memberCurrent();
            if (record.loading || record.prepared === undefined) fail('DeclaredFileInstallationAlreadyConstructed');
            record.loading = true;
            // Retain the constructor flight before options or the actual factory
            // can reenter failure. Retirement joins the same pending constructor.
            record.loadFlight = Promise.resolve().then(async () => {
              memberCurrent();
              const prepared = record.prepared;
              const fields = {moon, sourceInitialization: context,
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
            void record.loadFlight.then(() => flights.delete(record.loadFlight),
              () => flights.delete(record.loadFlight));
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
      void record.flight.then(() => flights.delete(record.flight), () => flights.delete(record.flight));
      return record.flight;
    },
    fail(cause) {
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
  return inventory;
}
