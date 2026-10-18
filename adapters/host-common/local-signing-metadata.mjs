// Existing Credential metadata over the same runtime's private opaque values.
// This view performs no key access, permission decision, durable claim or sign.
import {checked} from './runtime-result.mjs';

const names = ['clientLocalSigningGrantAdmit', 'clientLocalSigningGrantWire',
  'clientLocalSigningGrantCid', 'clientLocalSigningGrantScope',
  'clientLocalSigningGrantMaxUses', 'clientLocalSigningGrantExpires',
  'clientLocalSigningUsePrepare', 'clientLocalSigningUseAdmit',
  'clientLocalSigningUseWire', 'clientLocalSigningUseCid',
  'clientLocalSigningUseGrantCid', 'clientLocalSigningUseId',
  'clientLocalSigningUseOrdinal', 'clientLocalSigningUseCheck'];
const fail = code => {throw Object.assign(new Error(code), {code});};

export function createLocalSigningMetadata(moon) {
  // Capture the actual callbacks and receiver once, before a physical caller
  // can await anything. A later property replacement cannot switch runtimes.
  const methods = Object.fromEntries(names.map(name => [name, moon?.[name]]));
  if (names.some(name => typeof methods[name] !== 'function')) {
    fail('LocalSigningMetadataRuntimeUnavailable');
  }
  const call = (name, ...args) => Reflect.apply(methods[name], moon, args);
  let grants = new WeakMap(), scopes = new WeakMap(), uses = new WeakMap();
  let retired = false;
  const active = () => {if (retired) fail('LocalSigningMetadataRetired');};
  const retain = (map, value) => {
    const token = Object.freeze(Object.create(null)); map.set(token, value);
    return token;
  };
  const original = (map, token) => {
    active();
    const value = token !== null && typeof token === 'object' ? map.get(token) : undefined;
    if (value === undefined) fail('ForeignLocalSigningMetadata');
    return value;
  };
  const time = value => {
    if (typeof value !== 'bigint' || value < 0n || value > 9223372036854775807n) {
      fail('InvalidLocalSigningMetadataTime');
    }
    return value;
  };
  return Object.freeze({
    admitGrant(wire, cid) {
      active();
      if (typeof wire !== 'string' || typeof cid !== 'string') fail('InvalidLocalSigningMetadata');
      return retain(grants, checked(call('clientLocalSigningGrantAdmit', wire, cid)));
    },
    grantWire: token => checked(call('clientLocalSigningGrantWire', original(grants, token))),
    grantCid: token => call('clientLocalSigningGrantCid', original(grants, token)),
    grantLimits(token) {
      const grant = original(grants, token);
      return Object.freeze({maxUses: call('clientLocalSigningGrantMaxUses', grant),
        expiresAt: call('clientLocalSigningGrantExpires', grant)});
    },
    originalScope(token) {
      return retain(scopes, call('clientLocalSigningGrantScope', original(grants, token)));
    },
    prepareUse(grantToken, {useId, trustedNowMilliseconds, usedCount, revoked, expectedScope}) {
      const grant = original(grants, grantToken), scope = original(scopes, expectedScope);
      if (typeof useId !== 'string' || !Number.isSafeInteger(usedCount) ||
          usedCount < 0 || usedCount > 2147483647 || typeof revoked !== 'boolean') {
        fail('InvalidLocalSigningMetadata');
      }
      return retain(uses, checked(call('clientLocalSigningUsePrepare', grant,
        useId, time(trustedNowMilliseconds), usedCount, revoked, scope)));
    },
    admitUse(grantToken, wire, cid) {
      const grant = original(grants, grantToken);
      if (typeof wire !== 'string' || typeof cid !== 'string') fail('InvalidLocalSigningMetadata');
      return retain(uses, checked(call('clientLocalSigningUseAdmit', grant, wire, cid)));
    },
    useWire: token => checked(call('clientLocalSigningUseWire', original(uses, token))),
    useCid: token => call('clientLocalSigningUseCid', original(uses, token)),
    useProjection(token) {
      const use = original(uses, token);
      return Object.freeze({grantCid: call('clientLocalSigningUseGrantCid', use),
        useId: call('clientLocalSigningUseId', use), ordinal: call('clientLocalSigningUseOrdinal', use)});
    },
    checkUseBinding(token, {trustedNowMilliseconds, revoked, expectedScope}) {
      const use = original(uses, token), scope = original(scopes, expectedScope);
      if (typeof revoked !== 'boolean') fail('InvalidLocalSigningMetadata');
      checked(call('clientLocalSigningUseCheck', use, time(trustedNowMilliseconds), revoked, scope));
    },
    retireMetadataView() {
      if (retired) return false;
      // Cut only this metadata view's references. Physical key/use/Unknown
      // custody and any escaped signed bytes remain with their existing Owner.
      retired = true; grants = new WeakMap(); scopes = new WeakMap(); uses = new WeakMap();
      return true;
    },
  });
}
