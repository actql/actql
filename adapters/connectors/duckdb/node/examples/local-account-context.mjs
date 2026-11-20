// The example Host's current trusted configuration and continuation binding.
// Account identity belongs to Common; Host context identity remains private.
import {contentCid, localAuthorizationContext, readAccountConfiguration} from
  '../../../../host-node/local-account-config.mjs';

export async function localHostAccountContext(config, moon) {
  let configuration;
  let unreadable = false;
  if (config.accountConfig !== undefined) {
    try { configuration = await readAccountConfiguration(config.accountConfig); }
    catch { unreadable = true; }
  }
  if (configuration !== undefined) {
    const original = configuration;
    const account = moon.executionAuthorizationAdmit(original.text);
    const state = JSON.parse(moon.executionAuthorizationAccountJson(account));
    configuration = Object.freeze({...original,
      configurationCid: state.state === 'admitted' ? state.configuration_cid : undefined,
      // Pure immutable configuration, not a cached decision or current grant.
      // Fresh context calls still read the file. Changed observations use the
      // full Common admission rather than borrowing this original's judgment.
      admitConfiguration(actualMoon, wire) {
        if (actualMoon !== moon) throw new Error('ForeignLocalHostAccountRuntime');
        return wire === original.text ? account : moon.executionAuthorizationAdmit(wire);
      },
    });
  }
  const context = localAuthorizationContext(config.principal,
    configuration?.accountId);
  return Object.freeze({
    configuration,
    unreadable,
    context,
    authorizationContextCid: contentCid({
      principal: config.principal,
      context_cid: context.contextCid,
      configuration_cid: configuration?.configurationCid ??
        (configuration !== undefined ? 'rejected' : unreadable ? 'unreadable' : 'missing'),
    }),
  });
}
