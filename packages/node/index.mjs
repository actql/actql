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
    const installation = options.installation;
    if (installation !== undefined && installation !== null &&
        typeof installation === 'object' && 'hostCapacityPolicy' in installation) {
      try {
        const {hostCapacityPolicy: selected, ...rest} = installation;
        if (selected !== undefined) {
          const hostCapacityPolicy = Object.freeze(structuredClone(selected));
          options = {...options, installation: {...rest, hostCapacityPolicy}};
        }
      } catch { throw new ClientError('InvalidInstalledHostCapacityPolicy'); }
    }
    return (await localProvider()).connect(options);
  }
  return connectHost(options);
}
