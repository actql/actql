// Original Credential DATA over one captured Common runtime. This view never
// supplies an operational Host request, current authority, funding or claim.
import {checked} from './runtime-result.mjs';
import {installationPreparationSubjectKeys as subjectKeys,
  installationPreparationSubjectKinds as subjectKinds,
  installationPreparationRequestKeys as requestKeys} from './installation-preparation-fields.generated.mjs';

const names = ['SubjectPrepare', 'SubjectAdmit', 'SubjectWire', 'SubjectCid',
  'SubjectFields', 'ScopePrepare', 'ScopeFields', 'ScopeMatchesSubject',
  'GrantPrepare', 'GrantAdmit', 'GrantWire', 'GrantCid', 'GrantScope',
  'GrantIssuer', 'GrantExpires', 'GrantMaxUses', 'UsePrepare', 'UseAdmit',
  'UseWire', 'UseCid', 'UseProjection', 'UseCheck', 'SignaturePreimage',
  'SignaturePrepare', 'SignatureAdmit', 'SignatureProjection', 'SignatureGrant'];
const fail = code => {throw Object.assign(new Error(code), {code});};
const invalid = () => fail('InvalidInstallationPreparationMetadata');
const integer = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
const time = value => {
  if (typeof value !== 'bigint' || value < 0n || value > 9223372036854775807n) invalid();
  return value;
};

function data(value, keys) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  // Read closed own DATA once. A comma-containing key, inherited original,
  // accessor, symbol or hidden alias cannot replace the complete field vector.
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const actual = Reflect.ownKeys(descriptors);
  if (actual.length !== keys.length || actual.some(key => typeof key !== 'string' || !keys.includes(key))) invalid();
  return Object.fromEntries(keys.map(key => {
    const descriptor = descriptors[key];
    if (descriptor === undefined || !descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    return [key, descriptor.value];
  }));
}

function fields(values, keys, kinds) {
  if (!Array.isArray(values) || values.length !== keys.length ||
      values.some(value => typeof value !== 'string')) invalid();
  return Object.freeze(Object.fromEntries(keys.map((key, index) => {
    const kind = kinds?.[index] ?? 'String', value = values[index];
    if (kind === 'String') return [key, value];
    if (!/^(?:0|[1-9][0-9]*)$/u.test(value)) invalid();
    const number = kind === 'Int64' ? time(BigInt(value)) : Number(value);
    if (kind !== 'Int64' && !integer(number)) invalid();
    return [key, number];
  })));
}

function stringProjection(value, length) {
  if (!Array.isArray(value) || value.length !== length ||
      value.some(field => typeof field !== 'string')) invalid();
  return Object.freeze([...value]);
}

export function createInstallationPreparationMetadata(moon) {
  const methods = Object.fromEntries(names.map(name => [name,
    moon?.['clientInstallationPreparation' + name]]));
  if (names.some(name => typeof methods[name] !== 'function')) {
    fail('InstallationPreparationRuntimeUnavailable');
  }
  const call = (name, ...args) => Reflect.apply(methods[name], moon, args);
  let subjects = new WeakMap(), scopes = new WeakMap(), grants = new WeakMap();
  let uses = new WeakMap(), envelopes = new WeakMap(), controls = new WeakMap();
  let retired = false;
  const active = () => {if (retired) fail('InstallationPreparationMetadataRetired');};
  const retain = (map, value, subject) => {
    const token = Object.freeze(Object.create(null));
    map.set(token, {value, subject}); return token;
  };
  const own = (map, token, subject) => {
    active();
    const original = token !== null && typeof token === 'object' ? map.get(token) : undefined;
    if (original === undefined || (subject !== undefined && original.subject !== subject)) {
      fail('ForeignInstallationPreparationMetadata');
    }
    return original.value;
  };
  const text = value => {if (typeof value !== 'string') invalid(); return value;};
  const subjectFields = token => fields(call('SubjectFields', own(subjects, token)), subjectKeys, subjectKinds);
  const scopeFields = token => fields(call('ScopeFields', own(scopes, token)), requestKeys);
  const rawScope = (token, subject) => {
    const value = own(scopes, token, subject);
    if (call('ScopeMatchesSubject', value, own(subjects, subject)) !== true) {
      fail('ForeignInstallationPreparationMetadata');
    }
    return value;
  };
  const view = {
    prepareSubject(original) {
      active();
      const snapshot = data(original, subjectKeys);
      const args = subjectKeys.map((key, index) => {
        const value = snapshot[key], kind = subjectKinds[index];
        if (kind === 'String') return text(value);
        if (kind === 'Int64') return time(value);
        if (!integer(value)) invalid(); return value;
      });
      return retain(subjects, checked(call('SubjectPrepare', ...args)));
    },
    admitSubject(wire, cid) {
      active();
      return retain(subjects, checked(call('SubjectAdmit', text(wire), text(cid))));
    },
    subjectWire: token => call('SubjectWire', own(subjects, token)),
    subjectCid: token => call('SubjectCid', own(subjects, token)),
    subjectFields,
    prepareScope(subject, original) {
      const value = own(subjects, subject), snapshot = data(original, requestKeys);
      return retain(scopes, checked(call('ScopePrepare', value,
        ...requestKeys.map(key => text(snapshot[key])))), subject);
    },
    scopeFields,
    forSubject(subject) {
      own(subjects, subject);
      const existing = controls.get(subject);
      if (existing !== undefined) return existing;
      const registerGrant = value => {
        const scope = call('GrantScope', value);
        if (call('ScopeMatchesSubject', scope, own(subjects, subject)) !== true) {
          fail('ForeignInstallationPreparationMetadata');
        }
        const token = retain(grants, value, subject);
        // Keep the actual grant's scope, not a reconstructed field record.
        grants.get(token).scope = retain(scopes, scope, subject);
        return token;
      };
      const control = Object.freeze({
        kind: 'installation-metadata', subject,
        prepare(original) {
          const value = data(original, ['issuerAuthority', 'scope', 'expiresUnixMilliseconds', 'maxUses']);
          if (!integer(value.maxUses)) invalid();
          return registerGrant(checked(call('GrantPrepare', text(value.issuerAuthority),
            rawScope(value.scope, subject), time(value.expiresUnixMilliseconds), value.maxUses)));
        },
        identity: token => call('GrantCid', own(grants, token, subject)),
        json: token => checked(call('GrantWire', own(grants, token, subject))),
        admitJson(wire, cid) {
          return registerGrant(checked(call('GrantAdmit', own(subjects, subject), text(wire), text(cid))));
        },
        projection(token) {
          const grant = own(grants, token, subject);
          return Object.freeze({grantCid: call('GrantCid', grant),
            issuerAuthority: call('GrantIssuer', grant),
            expiresUnixMilliseconds: call('GrantExpires', grant),
            maxUses: call('GrantMaxUses', grant), subject,
            scope: grants.get(token).scope});
        },
        subjectFields: () => subjectFields(subject),
        scopeFields(token) {rawScope(token, subject); return scopeFields(token);},
        signaturePreimage: token => checked(call('SignaturePreimage', own(grants, token, subject))),
        prepareSignatureEnvelope(token, key, signature) {
          return retain(envelopes, checked(call('SignaturePrepare', own(grants, token, subject),
            text(key), text(signature))), subject);
        },
        admitSignatureEnvelope(original) {
          const value = data(original, ['version', 'keyId', 'grantCid', 'body', 'signature']);
          return retain(envelopes, checked(call('SignatureAdmit', own(subjects, subject),
            ...['version', 'keyId', 'grantCid', 'body', 'signature'].map(key => text(value[key])))), subject);
        },
        signatureEnvelopeProjection: token => stringProjection(
          call('SignatureProjection', own(envelopes, token, subject)), 6),
        signatureEnvelopeGrant: token => registerGrant(call('SignatureGrant', own(envelopes, token, subject))),
        prepareUse(token, original) {
          const value = data(original, ['useId', 'trustedNowMilliseconds', 'usedCount', 'revoked', 'scope']);
          if (!integer(value.usedCount) || typeof value.revoked !== 'boolean') invalid();
          return retain(uses, checked(call('UsePrepare', own(grants, token, subject), text(value.useId),
            time(value.trustedNowMilliseconds), value.usedCount, value.revoked, rawScope(value.scope, subject))), subject);
        },
        useIdentity: token => call('UseCid', own(uses, token, subject)),
        useJson: token => checked(call('UseWire', own(uses, token, subject))),
        admitUse(token, wire, cid) {
          return retain(uses, checked(call('UseAdmit', own(grants, token, subject), text(wire), text(cid))), subject);
        },
        authorizeUse(token, original) {
          const value = data(original, ['trustedNowMilliseconds', 'revoked', 'scope']);
          if (typeof value.revoked !== 'boolean') invalid();
          checked(call('UseCheck', own(uses, token, subject), time(value.trustedNowMilliseconds),
            value.revoked, rawScope(value.scope, subject)));
        },
        useProjection: token => stringProjection(call('UseProjection', own(uses, token, subject)), 4),
      });
      controls.set(subject, control); return control;
    },
    retireMetadataView() {
      if (retired) return false;
      // Cut this view's aliases only. Original physical key/use/Unknown and
      // escaped wire/response custody remain with their existing Owners.
      retired = true;
      subjects = new WeakMap(); scopes = new WeakMap(); grants = new WeakMap();
      uses = new WeakMap(); envelopes = new WeakMap(); controls = new WeakMap();
      return true;
    },
  };
  return Object.freeze(view);
}
