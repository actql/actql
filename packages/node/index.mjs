import {connect as connectHost, ClientError} from '@actql/sdk';

export {ClientError, RequestHeld} from '@actql/sdk';

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

export async function connect(options) {
  if ((options?.mode === 'local' || options?.mode === 'hybrid' &&
      options?.owner === 'local') && options.endpoint === undefined) {
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
