import {connect as connectHost, ClientError} from '@actql/sdk';

export {ClientError} from '@actql/sdk';

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
    return (await localProvider()).connect(options);
  }
  return connectHost(options);
}
