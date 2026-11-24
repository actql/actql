// Existing Credential metadata over the same runtime's private opaque values.
// This view performs no key access, permission decision, durable claim or sign.
import {checked} from './runtime-result.mjs';

// Captured callback and token views are unchecked DATA; the same Common
// callbacks, WeakMap originals and current/retirement checks remain authoritative.
type RuntimeView = Readonly<Record<string, unknown>> | null | undefined;
type OriginalMap = WeakMap<object, unknown>;

const names = ['clientLocalSigningGrantAdmit', 'clientLocalSigningGrantWire',
  'clientLocalSigningGrantCid', 'clientLocalSigningGrantScope',
  'clientLocalSigningGrantMaxUses', 'clientLocalSigningGrantExpires',
  'clientLocalSigningUsePrepare', 'clientLocalSigningUseAdmit',
  'clientLocalSigningUseWire', 'clientLocalSigningUseCid',
  'clientLocalSigningUseGrantCid', 'clientLocalSigningUseId',
  'clientLocalSigningUseOrdinal', 'clientLocalSigningUseCheck'];
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};

export function createLocalSigningMetadata(moon: unknown) {
  // Capture the actual callbacks and receiver once, before a physical caller
  // can await anything. A later property replacement cannot switch runtimes.
  const methods = Object.fromEntries(names.map(name => [name, (moon as RuntimeView)?.[name]]));
  if (names.some(name => typeof methods[name] !== 'function')) {
    fail('LocalSigningMetadataRuntimeUnavailable');
  }
  const call = (name: string, ...args: unknown[]) => Reflect.apply(methods[name] as (...args: unknown[]) => unknown, moon, args);
  let grants = new WeakMap<object, unknown>(), scopes = new WeakMap<object, unknown>(), uses = new WeakMap<object, unknown>();
  let retired = false;
  const active = () => {if (retired) fail('LocalSigningMetadataRetired');};
  const retain = (map: OriginalMap, value: unknown) => {
    const token: object = Object.freeze(Object.create(null)); map.set(token, value);
    return token;
  };
  const original = (map: OriginalMap, token: unknown) => {
    active();
    const value = token !== null && typeof token === 'object' ? map.get(token) : undefined;
    if (value === undefined) fail('ForeignLocalSigningMetadata');
    return value;
  };
  const time = (value: unknown) => {
    if (typeof value !== 'bigint' || value < 0n || value > 9223372036854775807n) {
      fail('InvalidLocalSigningMetadataTime');
    }
    return value;
  };
  return Object.freeze({
    admitGrant(wire: unknown, cid: unknown) {
      active();
      if (typeof wire !== 'string' || typeof cid !== 'string') fail('InvalidLocalSigningMetadata');
      return retain(grants, checked(call('clientLocalSigningGrantAdmit', wire, cid)));
    },
    grantWire: (token: unknown) => checked(call('clientLocalSigningGrantWire', original(grants, token))),
    grantCid: (token: unknown) => call('clientLocalSigningGrantCid', original(grants, token)),
    grantLimits(token: unknown) {
      const grant = original(grants, token);
      return Object.freeze({maxUses: call('clientLocalSigningGrantMaxUses', grant),
        expiresAt: call('clientLocalSigningGrantExpires', grant)});
    },
    originalScope(token: unknown) {
      return retain(scopes, call('clientLocalSigningGrantScope', original(grants, token)));
    },
    prepareUse(grantToken: unknown, {useId, trustedNowMilliseconds, usedCount, revoked, expectedScope}: {useId: unknown; trustedNowMilliseconds: unknown; usedCount: unknown; revoked: unknown; expectedScope: unknown}) {
      const grant = original(grants, grantToken), scope = original(scopes, expectedScope);
      if (typeof useId !== 'string' || !Number.isSafeInteger(usedCount) ||
          (usedCount as number) < 0 || (usedCount as number) > 2147483647 || typeof revoked !== 'boolean') {
        fail('InvalidLocalSigningMetadata');
      }
      return retain(uses, checked(call('clientLocalSigningUsePrepare', grant,
        useId, time(trustedNowMilliseconds), usedCount, revoked, scope)));
    },
    admitUse(grantToken: unknown, wire: unknown, cid: unknown) {
      const grant = original(grants, grantToken);
      if (typeof wire !== 'string' || typeof cid !== 'string') fail('InvalidLocalSigningMetadata');
      return retain(uses, checked(call('clientLocalSigningUseAdmit', grant, wire, cid)));
    },
    useWire: (token: unknown) => checked(call('clientLocalSigningUseWire', original(uses, token))),
    useCid: (token: unknown) => call('clientLocalSigningUseCid', original(uses, token)),
    useProjection(token: unknown) {
      const use = original(uses, token);
      return Object.freeze({grantCid: call('clientLocalSigningUseGrantCid', use),
        useId: call('clientLocalSigningUseId', use), ordinal: call('clientLocalSigningUseOrdinal', use)});
    },
    checkUseBinding(token: unknown, {trustedNowMilliseconds, revoked, expectedScope}: {trustedNowMilliseconds: unknown; revoked: unknown; expectedScope: unknown}) {
      const use = original(uses, token), scope = original(scopes, expectedScope);
      if (typeof revoked !== 'boolean') fail('InvalidLocalSigningMetadata');
      checked(call('clientLocalSigningUseCheck', use, time(trustedNowMilliseconds), revoked, scope));
    },
    retireMetadataView() {
      if (retired) return false;
      // Cut only this metadata view's references. Physical key/use/Unknown
      // custody and any escaped signed bytes remain with their existing Owner.
      retired = true; grants = new WeakMap<object, unknown>(); scopes = new WeakMap<object, unknown>(); uses = new WeakMap<object, unknown>();
      return true;
    },
  });
}
