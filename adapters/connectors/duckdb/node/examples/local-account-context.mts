// The example Host's current trusted configuration and continuation binding.
// Account identity belongs to Common; Host context identity remains private.
import {contentCid, localAuthorizationContext, readAccountConfiguration} from
  '../../../../host-node/local-account-config.mjs';

import type {loadExecutionAuthorizationRuntime} from '../../../../host-node/authorization.mjs';

type AccountRuntime = Pick<Awaited<ReturnType<typeof loadExecutionAuthorizationRuntime>>,
  'executionAuthorizationAdmit' | 'executionAuthorizationAccountJson'>;
type AccountConfiguration = Awaited<ReturnType<typeof readAccountConfiguration>>;
type AdmittedConfiguration = AccountConfiguration & Readonly<{
  configurationCid: string | undefined;
  admitConfiguration(runtime: AccountRuntime, wire: string): ReturnType<AccountRuntime['executionAuthorizationAdmit']>;
}>;
type HostConfig = Readonly<{accountConfig?: string; principal: string}>;

export async function localHostAccountContext(config: HostConfig, moon: AccountRuntime) {
  let configuration: (AccountConfiguration & Partial<AdmittedConfiguration>) | undefined;
  let unreadable = false;
  if (config.accountConfig !== undefined) {
    try { configuration = await readAccountConfiguration(config.accountConfig); }
    catch { unreadable = true; }
  }
  if (configuration !== undefined) {
    const original = configuration;
    const account = moon.executionAuthorizationAdmit(original.text);
    const state = JSON.parse(moon.executionAuthorizationAccountJson(account)) as
      Readonly<{state?: string; configuration_cid?: string}>;
    configuration = Object.freeze<AdmittedConfiguration>({...original,
      configurationCid: state.state === 'admitted' ? state.configuration_cid : undefined,
      // Pure immutable configuration, not a cached decision or current grant.
      // Fresh context calls still read the file. Changed observations use the
      // full Common admission rather than borrowing this original's judgment.
      admitConfiguration(actualMoon: AccountRuntime, wire: string) {
        if (actualMoon !== moon) throw new Error('ForeignLocalHostAccountRuntime');
        return wire === original.text ? account : moon.executionAuthorizationAdmit(wire);
      },
    });
  }
  const context = localAuthorizationContext(config.principal,
    configuration?.accountId);
  return Object.freeze({
    configuration: configuration as AdmittedConfiguration | undefined,
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
