import initialControlPublicDispatch from './initial-control-public-dispatch.cjs';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
import {ClientError, RequestHeld} from '@actql/sdk/_internal/client-errors';

// Only the SDK's original error classes belong to this Client-only prefix.
// Acquire the execution graph only on the unselected route; selected Local
// owns its actual bootstrap and captured SDK images before that acquisition.
const requireSdk = createRequire(import.meta.url);
let sdk;
function connectHost(...args) {
  sdk ??= requireSdk('@actql/sdk');
  return sdk.connect(...args);
}

// Capture the actual early private consumer once, not a later cache export or
// a caller option. Its presence selects an entrance, never an admission. The
// same startup must still refuse before raw acquisition when coverage is absent.
const selectedInitialControlHostPreparation =
  initialControlPublicDispatch.selectedInitialControlHostPreparation;
const applyInitialControl = Reflect.apply;

export {ClientError, RequestHeld};

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
  if (selectedInitialControlHostPreparation !== undefined) {
    // The selected startup must cover original Local input BEFORE facade
    // getters/copy or lazy provider loading. Undefined selects only the
    // existing unselected route, never an admission or an empty input packet.
    const routed = applyInitialControl(selectedInitialControlHostPreparation,
      initialControlPublicDispatch, ['connect', options]);
    if (routed !== undefined) return routed;
  }
  let embeddedLocal;
  try {
    embeddedLocal = (options?.mode === 'local' || options?.mode === 'hybrid' &&
      options?.owner === 'local') && options.endpoint === undefined;
  } catch { throw new ClientError('InvalidConnectionOptions', {hint}); }
  if (embeddedLocal) {
    // Detach this new Host-only value before lazy provider loading. Admission
    // stays with the installed Host; connected Remote loads no Local module.
    try {
      let installation = options.installation;
      if (installation !== undefined && installation !== null &&
          typeof installation === 'object' && !Array.isArray(installation)) {
        const {hostCapacityPolicy: selected, ...rest} = installation;
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
        installation = {...rest, hostCapacityPolicy};
      }
      options = {...options, installation};
    } catch { throw new ClientError('InvalidInstalledHostCapacityPolicy'); }
    return (await localProvider()).connect(options);
  }
  return connectHost(options);
}

// The new short Local entry chooses a project-local state directory explicitly.
// Existing connect() retains its environment/home-directory defaults.
export async function open(options) {
  if (selectedInitialControlHostPreparation !== undefined) {
    return applyInitialControl(selectedInitialControlHostPreparation,
      initialControlPublicDispatch, ['open', options]);
  }
  // Unselected entrances retain their original semantics and independent
  // coverage duties. In particular, no default packet is made on the selected
  // path before its original raw-input acquisition.
  if (options === undefined) options = {};
  if (options === null || typeof options !== 'object' || Array.isArray(options) ||
      Object.keys(options).some(key => !['stateDir', 'installation',
        'durability', 'consentRefs'].includes(key)) ||
      options.stateDir !== undefined &&
        (typeof options.stateDir !== 'string' || !options.stateDir) ||
      options.installation !== undefined &&
        (options.installation === null || typeof options.installation !== 'object' ||
        Array.isArray(options.installation) ||
        Object.hasOwn(options.installation, 'directory'))) {
    throw new ClientError('InvalidOpenOptions');
  }
  const stateDir = resolve(options.stateDir ?? '.actql');
  const client = await connect({mode: 'local', owner: 'local',
    ...(options.durability === undefined ? {} : {durability: options.durability}),
    ...(options.consentRefs === undefined ? {} : {consentRefs: options.consentRefs}),
    installation: {...options.installation, directory: stateDir}});
  return Object.freeze({...client, info: Object.freeze({stateDir})});
}
