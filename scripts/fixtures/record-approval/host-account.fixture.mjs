// Explicit local fixture policy DATA only. The existing Account, Host and Site
// validate it and issue all actual decisions/grants. Reuse the returned SAME
// wire for their configuration identity; equal provider rules in a different
// complete configuration cannot authorize a Host Checkpoint's dispatch.
export function recordApprovalHostAccountConfiguration(canonicalJson, providerWire,
  principal, realizationKey, resultNames = ['main', 'updates']) {
  if (typeof canonicalJson !== 'function' || typeof principal !== 'string' || !principal ||
      typeof realizationKey !== 'string' || !realizationKey || !Array.isArray(resultNames) ||
      resultNames.length < 1 || resultNames.length > 16 || new Set(resultNames).size !== resultNames.length ||
      !Array.from(resultNames).every(name => typeof name === 'string' && /^[A-Za-z_][A-Za-z0-9_]{0,127}$/u.test(name))) {
    throw new TypeError('InvalidRecordApprovalAccountFixture');
  }
  const provider = JSON.parse(providerWire);
  if (!Array.isArray(provider?.entries) || provider.entries.some(entry =>
    ['host-submit', 'host-read'].includes(entry?.entry_id))) {
    throw new TypeError('InvalidRecordApprovalAccountFixture');
  }
  const entries = [...provider.entries,
    {entry_id: 'host-submit', outcome: 'allow', exclusions: [], principal: {any_of: [principal]},
      connection: {any_of: ['actql-remote-host']}, resource: {any_of: [realizationKey]},
      operation: {any_of: ['write']}},
    {entry_id: 'host-read', outcome: 'allow', exclusions: [], principal: {any_of: [principal]},
      connection: {any_of: ['actql-remote-host']}, resource: {any_of: [...resultNames.map(name => `result/${name}`).sort(), 'run']},
      operation: {any_of: ['read']}},
  ].sort((a, b) => a.entry_id < b.entry_id ? -1 : a.entry_id > b.entry_id ? 1 : 0);
  return canonicalJson({...provider, entries});
}
