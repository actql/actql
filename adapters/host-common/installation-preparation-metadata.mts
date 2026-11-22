// Original Credential DATA over one captured Common runtime. This view never
// supplies an operational Host request, current authority, funding or claim.
import {checked} from './runtime-result.mjs';
import {installationPreparationSubjectKeys as subjectKeys,
  installationPreparationSubjectKinds as subjectKinds,
  installationPreparationRequestKeys as requestKeys} from './installation-preparation-fields.generated.mjs';

// Unchecked views preserve the original closed field/parser and WeakMap guards.
type RuntimeView = Readonly<Record<string, unknown>> | null | undefined;
type RetainedOriginal = {value: unknown; subject: unknown; scope?: object};
type OriginalMap = WeakMap<object, RetainedOriginal>;

const names = ['SubjectPrepare', 'SubjectAdmit', 'SubjectWire', 'SubjectCid',
  'SubjectFields', 'ScopePrepare', 'ScopeFields', 'ScopeMatchesSubject',
  'GrantPrepare', 'GrantAdmit', 'GrantWire', 'GrantCid', 'GrantScope',
  'GrantIssuer', 'GrantExpires', 'GrantMaxUses', 'UsePrepare', 'UseAdmit',
  'UseWire', 'UseCid', 'UseProjection', 'UseCheck', 'SignaturePreimage',
  'SignaturePrepare', 'SignatureAdmit', 'SignatureProjection', 'SignatureGrant'];
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const invalid: () => never = () => fail('InvalidInstallationPreparationMetadata');
const integer = (value: unknown) => Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= 2147483647;
const time = (value: unknown) => {
  if (typeof value !== 'bigint' || value < 0n || value > 9223372036854775807n) invalid();
  return value;
};

function data(value: unknown, keys: readonly string[]) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  // Read closed own DATA once. A comma-containing key, inherited original,
  // accessor, symbol or hidden alias cannot replace the complete field vector.
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const actual = Reflect.ownKeys(descriptors);
  if (actual.length !== keys.length || actual.some(key => typeof key !== 'string' || !keys.includes(key))) invalid();
  return Object.fromEntries<unknown>(keys.map(key => {
    const descriptor = descriptors[key];
    if (descriptor === undefined || !descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    return [key, descriptor.value];
  }));
}

function fields(values: unknown, keys: readonly string[], kinds?: readonly string[]) {
  if (!Array.isArray(values) || values.length !== keys.length ||
      values.some(value => typeof value !== 'string')) invalid();
  return Object.freeze(Object.fromEntries(keys.map((key, index) => {
    const kind = kinds?.[index] ?? 'String', value = (values as string[])[index];
    if (kind === 'String') return [key, value];
    if (!/^(?:0|[1-9][0-9]*)$/u.test(value)) invalid();
    const number = kind === 'Int64' ? time(BigInt(value)) : Number(value);
    if (kind !== 'Int64' && !integer(number)) invalid();
    return [key, number];
  })));
}

function stringProjection(value: unknown, length: number) {
  if (!Array.isArray(value) || value.length !== length ||
      value.some(field => typeof field !== 'string')) invalid();
  return Object.freeze([...(value as string[])]);
}

export function createInstallationPreparationMetadata(moon: unknown) {
  const methods = Object.fromEntries(names.map(name => [name,
    (moon as RuntimeView)?.['clientInstallationPreparation' + name]]));
  if (names.some(name => typeof methods[name] !== 'function')) {
    fail('InstallationPreparationRuntimeUnavailable');
  }
  const call = (name: string, ...args: unknown[]) => Reflect.apply(methods[name] as (...args: unknown[]) => unknown, moon, args);
  let subjects = new WeakMap<object, RetainedOriginal>(), scopes = new WeakMap<object, RetainedOriginal>(), grants = new WeakMap<object, RetainedOriginal>();
  let uses = new WeakMap<object, RetainedOriginal>(), envelopes = new WeakMap<object, RetainedOriginal>(), controls = new WeakMap<object, unknown>();
  let retired = false;
  const active = () => {if (retired) fail('InstallationPreparationMetadataRetired');};
  const retain = (map: OriginalMap, value: unknown, subject?: unknown) => {
    const token: object = Object.freeze(Object.create(null));
    map.set(token, {value, subject}); return token;
  };
  const own = (map: OriginalMap, token: unknown, subject?: unknown) => {
    active();
    const original = token !== null && typeof token === 'object' ? map.get(token) : undefined;
    if (original === undefined || (subject !== undefined && original.subject !== subject)) {
      fail('ForeignInstallationPreparationMetadata');
    }
    return original.value;
  };
  const text = (value: unknown) => {if (typeof value !== 'string') invalid(); return value;};
  const subjectFields = (token: unknown) => fields(call('SubjectFields', own(subjects, token)), subjectKeys, subjectKinds);
  const scopeFields = (token: unknown) => fields(call('ScopeFields', own(scopes, token)), requestKeys);
  const rawScope = (token: unknown, subject: unknown) => {
    const value = own(scopes, token, subject);
    if (call('ScopeMatchesSubject', value, own(subjects, subject)) !== true) {
      fail('ForeignInstallationPreparationMetadata');
    }
    return value;
  };
  const view = {
    prepareSubject(original: unknown) {
      active();
      const snapshot = data(original, subjectKeys);
      const args = subjectKeys.map((key, index) => {
        const value = snapshot[key], kind = (subjectKinds as readonly string[])[index];
        if (kind === 'String') return text(value);
        if (kind === 'Int64') return time(value);
        if (!integer(value)) invalid(); return value;
      });
      return retain(subjects, checked(call('SubjectPrepare', ...args)));
    },
    admitSubject(wire: unknown, cid: unknown) {
      active();
      return retain(subjects, checked(call('SubjectAdmit', text(wire), text(cid))));
    },
    subjectWire: (token: unknown) => call('SubjectWire', own(subjects, token)),
    subjectCid: (token: unknown) => call('SubjectCid', own(subjects, token)),
    subjectFields,
    prepareScope(subject: unknown, original: unknown) {
      const value = own(subjects, subject), snapshot = data(original, requestKeys);
      return retain(scopes, checked(call('ScopePrepare', value,
        ...requestKeys.map(key => text(snapshot[key])))), subject);
    },
    scopeFields,
    forSubject(subject: unknown) {
      own(subjects, subject);
      const existing = controls.get(subject as object);
      if (existing !== undefined) return existing as typeof control;
      const registerGrant = (value: unknown) => {
        const scope = call('GrantScope', value);
        if (call('ScopeMatchesSubject', scope, own(subjects, subject)) !== true) {
          fail('ForeignInstallationPreparationMetadata');
        }
        const token = retain(grants, value, subject);
        // Keep the actual grant's scope, not a reconstructed field record.
        grants.get(token as object)!.scope = retain(scopes, scope, subject);
        return token;
      };
      const control = Object.freeze({
        kind: 'installation-metadata', subject,
        prepare(original: unknown) {
          const value = data(original, ['issuerAuthority', 'scope', 'expiresUnixMilliseconds', 'maxUses']);
          if (!integer(value.maxUses)) invalid();
          return registerGrant(checked(call('GrantPrepare', text(value.issuerAuthority),
            rawScope(value.scope, subject), time(value.expiresUnixMilliseconds), value.maxUses)));
        },
        identity: (token: unknown) => call('GrantCid', own(grants, token, subject)) as string,
        json: (token: unknown) => checked(call('GrantWire', own(grants, token, subject))) as string,
        admitJson(wire: unknown, cid: unknown) {
          return registerGrant(checked(call('GrantAdmit', own(subjects, subject), text(wire), text(cid))));
        },
        projection(token: unknown) {
          const grant = own(grants, token, subject);
          return Object.freeze({grantCid: call('GrantCid', grant),
            issuerAuthority: call('GrantIssuer', grant),
            expiresUnixMilliseconds: call('GrantExpires', grant),
            maxUses: call('GrantMaxUses', grant), subject,
            scope: grants.get(token as object)!.scope});
        },
        subjectFields: () => subjectFields(subject),
        scopeFields(token: unknown) {rawScope(token, subject); return scopeFields(token);},
        signaturePreimage: (token: unknown) => checked(call('SignaturePreimage', own(grants, token, subject))) as Uint8Array,
        prepareSignatureEnvelope(token: unknown, key: unknown, signature: unknown) {
          return retain(envelopes, checked(call('SignaturePrepare', own(grants, token, subject),
            text(key), text(signature))), subject);
        },
        admitSignatureEnvelope(original: unknown) {
          const value = data(original, ['version', 'keyId', 'grantCid', 'body', 'signature']);
          return retain(envelopes, checked(call('SignatureAdmit', own(subjects, subject),
            ...['version', 'keyId', 'grantCid', 'body', 'signature'].map(key => text(value[key])))), subject);
        },
        signatureEnvelopeProjection: (token: unknown) => stringProjection(
          call('SignatureProjection', own(envelopes, token, subject)), 6),
        signatureEnvelopeGrant: (token: unknown) => registerGrant(call('SignatureGrant', own(envelopes, token, subject))),
        prepareUse(token: unknown, original: unknown) {
          const value = data(original, ['useId', 'trustedNowMilliseconds', 'usedCount', 'revoked', 'scope']);
          if (!integer(value.usedCount) || typeof value.revoked !== 'boolean') invalid();
          return retain(uses, checked(call('UsePrepare', own(grants, token, subject), text(value.useId),
            time(value.trustedNowMilliseconds), value.usedCount, value.revoked, rawScope(value.scope, subject))), subject);
        },
        useIdentity: (token: unknown) => call('UseCid', own(uses, token, subject)) as string,
        useJson: (token: unknown) => checked(call('UseWire', own(uses, token, subject))) as string,
        admitUse(token: unknown, wire: unknown, cid: unknown) {
          return retain(uses, checked(call('UseAdmit', own(grants, token, subject), text(wire), text(cid))), subject);
        },
        authorizeUse(token: unknown, original: unknown) {
          const value = data(original, ['trustedNowMilliseconds', 'revoked', 'scope']);
          if (typeof value.revoked !== 'boolean') invalid();
          checked(call('UseCheck', own(uses, token, subject), time(value.trustedNowMilliseconds),
            value.revoked, rawScope(value.scope, subject)));
        },
        useProjection: (token: unknown) => stringProjection(call('UseProjection', own(uses, token, subject)), 4),
      });
      controls.set(subject as object, control); return control;
    },
    retireMetadataView() {
      if (retired) return false;
      // Cut this view's aliases only. Original physical key/use/Unknown and
      // escaped wire/response custody remain with their existing Owners.
      retired = true;
      subjects = new WeakMap<object, RetainedOriginal>(); scopes = new WeakMap<object, RetainedOriginal>(); grants = new WeakMap<object, RetainedOriginal>();
      uses = new WeakMap<object, RetainedOriginal>(); envelopes = new WeakMap<object, RetainedOriginal>(); controls = new WeakMap<object, unknown>();
      return true;
    },
  };
  return Object.freeze(view);
}
