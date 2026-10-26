// Standard installed Host service owner. This public cut retains the exact
// original Source implementation/Site association; numerical DATA is neither
// a Run admission nor permission. Other service facets extend this SAME owner.
import {openInstalledRowSite, installedRowCredentialOperationSite} from './installed-row-source.mjs';
import {runtimeField, runtimeIsBoxedSome} from '../host-common/compiler-binding.generated.mjs';
import {createInstalledCredentialSourceReader, installedJsonSourceReaderLimitNames,
  installedJsonSourceReaderProfileLimitNames} from './installed-credential-source-reader.mjs';
import {types as nodeTypes} from 'node:util';

const installations = new WeakMap();
const fail = code => {throw Object.assign(new TypeError(code), {code});};

// Snapshot only the existing required Source service methods. The connector
// chooses its own unavailable error and retains its explicit legacy branch.
// This view issues no service, installation, capacity or cleanup observation.
export function captureInstalledSourceServices(receiver, unavailable) {
  if (typeof unavailable !== 'function') throw new TypeError('InvalidInstalledSourceServiceErrorFactory');
  const refuse = () => {throw Reflect.apply(unavailable, undefined, []);};
  if (receiver === null || !['object', 'function'].includes(typeof receiver) || nodeTypes.isProxy(receiver)) refuse();
  const methods = Object.create(null);
  for (const name of ['sourceReaderImplementationProfile', 'sourceReaderImplementation', 'openRowSite', 'createSourceReader']) {
    const field = Object.getOwnPropertyDescriptor(receiver, name);
    if (field === undefined || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') refuse();
    methods[name] = field.value;
  }
  Object.freeze(methods);
  return Object.freeze(function invokeInstalledSourceService(name, ...args) {
    if (typeof name !== 'string' || !Object.hasOwn(methods, name)) refuse();
    return Reflect.apply(methods[name], receiver, args);
  });
}

export function createInstalledHostServices({root, principalId, moon, assertCurrent, receiver}) {
  if (typeof root !== 'string' || !root || typeof principalId !== 'string' || !principalId ||
      !moon || typeof moon !== 'object' || typeof assertCurrent !== 'function') fail('InvalidInstalledHostServices');
  const selected = new WeakMap(), sites = new WeakMap(), siteInstallations = new WeakMap();
  const implementations = new WeakMap(), sourceImplementations = new WeakMap(), sourceProfiles = new WeakMap();
  const publicationOnly = false;
  const sourcePolicy = moon.clientProgramInstalledSourceReaderPolicy;
  const sourceProfile = moon.clientProgramInstalledJsonSourceReaderProfile;
  const sourceCapacity = moon.clientProgramInstalledJsonSourceReaderCapacity;
  const current = () => {
    if (Reflect.apply(assertCurrent, receiver, []) !== undefined) fail('InstalledHostServiceCurrentCheckNotSynchronous');
  };
  current();
  const services = Object.freeze({
    sourceReaderImplementationProfile(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      if (Reflect.ownKeys(fields).length !== 3 || ['installation', 'metadataResponses', 'originUnits'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value, runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const metadata = fields.metadataResponses.value, origin = fields.originUnits.value;
      if (![metadata, origin].every(value => Number.isSafeInteger(value) && value >= 0 && value < 2147483647)) {
        fail('InvalidInstalledSourceReaderSelection');
      }
      const previous = sourceProfiles.get(installation);
      if (previous !== undefined) {
        if (previous.runtimeBundleCid !== runtimeBundleCid || previous.metadata !== metadata || previous.origin !== origin) {
          fail('InstalledSourceReaderSelectionChanged');
        }
        return previous.value;
      }
      if (sourceImplementations.has(installation)) fail('InstalledSourceReaderProfileSelectedLate');
      if (typeof sourceProfile !== 'function') fail('InstalledSourceReaderProfileUnavailable');
      const returned = Reflect.apply(sourceProfile, moon, [metadata, origin]);
      const values = runtimeIsBoxedSome(returned) ? runtimeField(returned, 0) : undefined;
      if (!Array.isArray(values) || values.length !== installedJsonSourceReaderProfileLimitNames.length ||
          values.some(value => !Number.isSafeInteger(value) || value < 1 || value >= 2147483647)) {
        fail('InvalidInstalledSourceReaderProfile');
      }
      const value = Object.freeze(Object.fromEntries(installedJsonSourceReaderProfileLimitNames.map(
        (name, index) => [name, values[index]])));
      current(); sourceProfiles.set(installation, Object.freeze({runtimeBundleCid, metadata, origin, value}));
      return value;
    },
    sourceReaderImplementation(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) {
        fail('InvalidInstalledSourceReaderSelection');
      }
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      if (Reflect.ownKeys(fields).length !== 3 || ['installation', 'limits', 'columnCount'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      if (nodeTypes.isProxy(fields.limits.value ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value, runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const columns = fields.columnCount.value, supplied = Object.getOwnPropertyDescriptors(fields.limits.value ?? {});
      const names = [...installedJsonSourceReaderLimitNames, 'maxSecretBytes'];
      if (names.some(name => !Object.hasOwn(supplied[name] ?? {}, 'value') ||
          !Number.isSafeInteger(supplied[name].value) || supplied[name].value < 1 || supplied[name].value > 2147483647)) {
        fail('InvalidInstalledSourceReaderLimits');
      }
      const profile = sourceProfiles.get(installation);
      if (profile !== undefined && (profile.runtimeBundleCid !== runtimeBundleCid ||
          columns > profile.value.maxColumns || names.some(name => supplied[name].value > profile.value[name]))) {
        fail('InstalledSourceReaderImplementationBoundsExceeded');
      }
      if ([sourcePolicy, sourceCapacity].some(port => typeof port !== 'function')) fail('InstalledSourceReaderRuntimeUnavailable');
      const policy = Reflect.apply(sourcePolicy, moon, []);
      if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
        !Number.isSafeInteger(value) || value < 1 || value > 2147483647) ||
        !Number.isSafeInteger(columns) || columns < 1 || columns > policy[2] ||
        supplied.maxSecretBytes.value > policy[0]) fail('InstalledSourceReaderPolicyUnavailable');
      const limits = Object.freeze(Object.fromEntries(names.map(name => [name, supplied[name].value])));
      const previous = sourceImplementations.get(installation);
      if (previous !== undefined) {
        if (previous.runtimeBundleCid !== runtimeBundleCid || previous.columns !== columns ||
            names.some(name => previous.value.limits[name] !== limits[name])) fail('InstalledSourceReaderSelectionChanged');
        return previous.value;
      }
      const capacity = Reflect.apply(sourceCapacity, moon,
        [installedJsonSourceReaderLimitNames.map(name => limits[name]), columns, limits.maxSecretBytes]);
      if (capacity === undefined || capacity === null) fail('InstalledSourceReaderCapacityUnavailable');
      const value = Object.freeze({capacity, limits, runAcquisitionLimits: Object.freeze({
        maxBindings: policy[1], maxSecretBytes: limits.maxSecretBytes})});
      current(); sourceImplementations.set(installation, Object.freeze({runtimeBundleCid, columns, value}));
      return value;
    },
    createSourceReader(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      const readerField = Object.hasOwn(fields, 'readPages') ? 'readPages' : 'createReader';
      if (Reflect.ownKeys(fields).length !== 4 ||
          ['installation', 'implementation', 'site', readerField].some(name =>
            !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value, implementation = sourceImplementations.get(installation);
      if (implementation === undefined || implementation.value !== fields.implementation.value ||
          implementation.runtimeBundleCid !== selected.get(installation) ||
          siteInstallations.get(fields.site.value) !== installation) fail('ForeignInstalledSourceReaderSelection');
      const originalSite = installedRowCredentialOperationSite(fields.site.value.credential);
      return createInstalledCredentialSourceReader({capacity: implementation.value.capacity,
        originalSite, [readerField]: fields[readerField].value, assertCurrent: current,
        maxResponses: implementation.value.limits.maxPages});
    },
    openRowSite(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationPhysicalUnavailable');
      const presentation = Object.getOwnPropertyDescriptor(options ?? {}, 'secretPresentation');
      if (presentation !== undefined && !Object.hasOwn(presentation, 'value')) {
        fail('InvalidRowSourceSecretPresentation');
      }
      const installation = Object.getOwnPropertyDescriptor(options ?? {}, 'installation')?.value;
      const runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      // The caller supplies provider configuration only. It cannot replace the
      // original Host/runtime/current association with equal or copied DATA.
      const implementation = implementations.get(installation);
      if (implementation?.constructing) fail('InstalledEffectDefinitionSelectionReentry');
      if (implementation !== undefined) implementation.sealed = true;
      return openInstalledRowSite({...options, root, principalId, commonMoon: moon,
        runtimeBundleCid, assertCurrent: current}).then(original => {
          sites.set(original.site, implementation);
          siteInstallations.set(original.site, installation);
        return original;
      });
    },
  });
  installations.set(services, {selected, current, sites, siteInstallations, implementations,
    sourceImplementations, sourceProfiles});
  return services;
}

export function retainInstalledHostServiceInstallation(services, installation, runtimeBundleCid) {
  if (services === undefined) return;
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  original.current();
  if (!installation || typeof installation !== 'object' || !Object.isFrozen(installation) ||
      !/^sha256:[0-9a-f]{64}$/u.test(runtimeBundleCid ?? '')) {
    fail('InvalidInstalledHostServiceInstallation');
  }
  const previous = original.selected.get(installation);
  if (previous !== undefined && previous !== runtimeBundleCid) fail(
    'InstalledHostServiceRuntimeChanged');
  original.selected.set(installation, runtimeBundleCid);
}
