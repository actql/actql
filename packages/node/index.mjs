import {resolve} from 'node:path';
import {createRequire} from 'node:module';
import {ClientError, RequestHeld} from '@actql/sdk/_internal/client-errors';

// Remote connections need no Local provider or process-wide bootstrap.
const requireSdk = createRequire(import.meta.url);
let sdk;
function connectHost(...args) {
  sdk ??= requireSdk('@actql/sdk');
  return sdk.connect(...args);
}

export {ClientError, RequestHeld};

// Trusted application options are captured before lazy provider acquisition.
// Keep callbacks and opaque installation originals, rather than cloning their
// backing objects or treating a copied value as authority. Unknown own fields
// and symbols survive for the Host's existing closed validation.
function captureOptions(original, captured = new Map()) {
  const fields = Object.getOwnPropertyDescriptors(original);
  for (const key of Reflect.ownKeys(fields)) {
    const field = fields[key];
    fields[key] = {value: captured.has(key) ? captured.get(key) :
      Reflect.get(original, key), enumerable: field.enumerable,
      configurable: false, writable: false};
  }
  return Object.freeze(Object.create(Object.getPrototypeOf(original), fields));
}

// The standard installation has one fixed Local provider slot. Resolution
// does not load Local code for a connected Host and never installs packages.
async function localProvider() {
  let resolved;
  try {
    resolved = import.meta.resolve('@actql/local-node');
  } catch (cause) {
    if (cause?.code !== 'ERR_MODULE_NOT_FOUND') throw cause;
    throw new ClientError('LocalProviderNotInstalled', {
      hint: 'Install the standard Local provider package before selecting embedded Local.',
      cause,
    });
  }
  // Enable only the existing optional V8 cache before Local's static Host
  // graph loads. This private helper belongs to the same resolved package;
  // it supplies no ActQL admission, checking result, or execution authority.
  const cache = await import(new URL('./adapters/host-node/compile-cache.mjs', resolved));
  cache.enableNodeCompileCache();
  const provider = await import(resolved);
  if (typeof provider.connect !== 'function') {
    throw new ClientError('InvalidLocalProvider');
  }
  return provider;
}

export async function connect(options, stringOptions) {
  if (typeof options === 'string') return connectHost(options, stringOptions);
  const hint = "For embedded Local, use open() without a Host or token. For Remote, use connect({mode: 'remote', endpoint: 'https://host.example/', token: getAccessToken}).";
  if (stringOptions !== undefined) throw new ClientError('InvalidConnectionOptions', {hint});
  let embeddedLocal, mode, owner, endpoint;
  try {
    mode = options?.mode;
    owner = options?.owner;
    endpoint = options?.endpoint;
    embeddedLocal = (mode === 'local' || mode === 'hybrid' &&
      owner === 'local') && endpoint === undefined;
  } catch { throw new ClientError('InvalidConnectionOptions', {hint}); }
  if (embeddedLocal) {
    // Detach this new Host-only value before lazy provider loading. Admission
    // stays with the installed Host; connected Remote loads no Local module.
    try {
      // Only an explicitly captured caller profile can consent to initial
      // Mock setup. A discovered Project profile is not this selection.
      if ('profile' in options && !Object.hasOwn(options, 'profile')) {
        throw new ClientError('InvalidConnectionOptions', {hint});
      }
      options = captureOptions(options, new Map([
        ['mode', mode], ['owner', owner], ['endpoint', endpoint],
      ]));
      let installation = options.installation;
      if (installation !== undefined && installation !== null &&
          typeof installation === 'object' && !Array.isArray(installation)) {
        installation = captureOptions(installation);
        const selected = installation.hostCapacityPolicy;
        // Capture omission as well as selection. Later caller mutations must
        // not choose a different Host policy while the provider is loading.
        let hostCapacityPolicy;
        if (selected !== undefined) {
          // Cloning must not turn an inadmissible class instance or null-
          // prototype object into a plain policy before Host admission.
          if (selected === null || typeof selected !== 'object' ||
              Object.getPrototypeOf(selected) !== Object.prototype) {
            throw new TypeError('PolicyShape');
          }
          hostCapacityPolicy = Object.freeze(structuredClone(selected));
        }
        const fields = Object.getOwnPropertyDescriptors(installation);
        fields.hostCapacityPolicy = {value: hostCapacityPolicy, enumerable: true};
        installation = Object.freeze(Object.create(Object.getPrototypeOf(installation), fields));
      }
      const fields = Object.getOwnPropertyDescriptors(options);
      fields.installation = {value: installation, enumerable: true};
      options = Object.freeze(Object.create(Object.getPrototypeOf(options), fields));
    } catch (error) {
      if (error instanceof ClientError) throw error;
      throw new ClientError('InvalidInstalledHostCapacityPolicy');
    }
    return (await localProvider()).connect(options);
  }
  return connectHost(options);
}

// The new short Local entry chooses a project-local state directory explicitly.
// Existing connect() retains its environment/home-directory defaults.
export async function open(options) {
  if (options === undefined) options = {};
  if (options === null || typeof options !== 'object' || Array.isArray(options) ||
      Reflect.ownKeys(options).some(key => !['stateDir', 'installation',
        'durability', 'consentRefs', 'profile'].includes(key))) {
    throw new ClientError('InvalidOpenOptions');
  }
  options = captureOptions(options);
  if (
      options.stateDir !== undefined &&
        (typeof options.stateDir !== 'string' || !options.stateDir) ||
      options.profile !== undefined &&
        (typeof options.profile !== 'string' || !options.profile) ||
      options.installation !== undefined &&
        (options.installation === null || typeof options.installation !== 'object' ||
        Array.isArray(options.installation) ||
        Object.hasOwn(options.installation, 'directory'))) {
    throw new ClientError('InvalidOpenOptions');
  }
  const stateDir = resolve(options.stateDir ?? '.actql');
  const client = await connect({mode: 'local', owner: 'local',
    ...(Object.hasOwn(options, 'profile') ? {profile: options.profile} : {}),
    ...(options.durability === undefined ? {} : {durability: options.durability}),
    ...(options.consentRefs === undefined ? {} : {consentRefs: options.consentRefs}),
    installation: {...options.installation, directory: stateDir}});
  return Object.freeze({...client, info: Object.freeze({stateDir})});
}
