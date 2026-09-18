// Independent adapter-test fixture. Product execution never imports this file;
// the portable run_publication package is the sole product authority for
// canonical identity, contract admission, and publication transitions.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';

const registry = JSON.parse(readFileSync(
  new URL('../../spec/contracts/actql-run-publication.json', import.meta.url),
  'utf8',
));

const identityFields = Object.freeze({
  result_definition: 'result_definition_cid',
  run_invocation: 'invocation_cid',
  result_retention_policy: 'effective_retention_policy_cid',
  durable_result_binding: 'durable_result_binding_cid',
  publication_request: 'publication_request_cid',
  publication_attempt: 'publication_attempt_cid',
  publication_record: 'publication_record_cid',
  manifest_read_grant: 'manifest_read_grant_cid',
  result_read_grant: 'result_read_grant_cid',
  delivery_attempt: 'delivery_attempt_cid',
  delivery_record: 'delivery_record_cid',
  public_index_entry: 'public_index_entry_cid',
});

const fail = (code, path = '$') => {
  throw Object.assign(new Error(code), {code, path});
};

function normalizedText(value, path) {
  if (typeof value.isWellFormed === 'function' && !value.isWellFormed()) {
    fail('InvalidCanonicalText', path);
  }
  return value.normalize('NFC').replace(/\r\n?/gu, '\n');
}

export function canonicalJson(value, path = '$') {
  if (value === null || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number') {
    if (!Number.isFinite(value) || Object.is(value, -0)) {
      fail('InvalidCanonicalNumber', path);
    }
    return JSON.stringify(value);
  }
  if (typeof value === 'string') {
    return JSON.stringify(normalizedText(value, path));
  }
  if (Array.isArray(value)) {
    return `[${value.map((item, index) =>
      canonicalJson(item, `${path}[${index}]`)).join(',')}]`;
  }
  if (value === null || typeof value !== 'object' ||
      Object.getPrototypeOf(value) !== Object.prototype) {
    fail('InvalidCanonicalValue', path);
  }
  const entries = Object.entries(value).map(([key, item]) => [
    normalizedText(key, `${path}.<key>`), item,
  ]);
  if (new Set(entries.map(([key]) => key)).size !== entries.length) {
    fail('CanonicalKeyCollision', path);
  }
  entries.sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  return `{${entries.map(([key, item]) =>
    `${JSON.stringify(key)}:${canonicalJson(item, `${path}.${key}`)}`
  ).join(',')}}`;
}

export function canonicalCid(value) {
  return `sha256:${createHash('sha256').update(canonicalJson(value), 'utf8')
    .digest('hex')}`;
}

function equal(left, right) {
  return canonicalJson(left) === canonicalJson(right);
}

function validateSchema(schema, value, path) {
  if (schema.const !== undefined && !equal(schema.const, value)) {
    fail('PublicationContractConst', path);
  }
  if (schema.enum !== undefined &&
      !schema.enum.some(candidate => equal(candidate, value))) {
    fail('PublicationContractEnum', path);
  }
  if (schema.type === 'object' || schema.required !== undefined ||
      schema.properties !== undefined ||
      schema.additionalProperties !== undefined) {
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.getPrototypeOf(value) !== Object.prototype) {
      fail('PublicationContractType', path);
    }
    for (const key of schema.required ?? []) {
      if (!Object.hasOwn(value, key)) fail('PublicationContractRequired', `${path}.${key}`);
    }
    if (schema.additionalProperties === false) {
      for (const key of Object.keys(value)) {
        if (!Object.hasOwn(schema.properties ?? {}, key)) {
          fail('PublicationContractClosed', `${path}.${key}`);
        }
      }
    }
    for (const [key, child] of Object.entries(schema.properties ?? {})) {
      if (Object.hasOwn(value, key)) validateSchema(child, value[key], `${path}.${key}`);
    }
  } else if (schema.type === 'array') {
    if (!Array.isArray(value)) fail('PublicationContractType', path);
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      fail('PublicationContractMinimum', path);
    }
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      fail('PublicationContractMaximum', path);
    }
    if (schema.uniqueItems === true) {
      const entries = value.map(item => canonicalJson(item));
      if (new Set(entries).size !== entries.length) {
        fail('PublicationContractUnique', path);
      }
    }
    value.forEach((item, index) =>
      validateSchema(schema.items ?? {}, item, `${path}[${index}]`));
  } else if (schema.type === 'string') {
    if (typeof value !== 'string') fail('PublicationContractType', path);
    if (schema.minLength !== undefined &&
        [...value].length < schema.minLength) {
      fail('PublicationContractMinimum', path);
    }
    if (schema.pattern !== undefined && !(new RegExp(schema.pattern, 'u')).test(value)) {
      fail('PublicationContractPattern', path);
    }
  } else if (schema.type === 'integer') {
    if (!Number.isSafeInteger(value)) fail('PublicationContractType', path);
    if (schema.minimum !== undefined && value < schema.minimum) {
      fail('PublicationContractMinimum', path);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      fail('PublicationContractMaximum', path);
    }
  } else if (schema.type === 'boolean' && typeof value !== 'boolean') {
    fail('PublicationContractType', path);
  }
  for (const branch of schema.allOf ?? []) {
    let condition = true;
    try { validateSchema(branch.if ?? {}, value, path); }
    catch { condition = false; }
    if (condition && branch.then) validateSchema(branch.then, value, path);
    if (!condition && branch.else) validateSchema(branch.else, value, path);
  }
  if (schema.not !== undefined) {
    let matched = true;
    try { validateSchema(schema.not, value, path); }
    catch { matched = false; }
    if (matched) fail('PublicationContractNot', path);
  }
}

function copy(value) {
  return JSON.parse(canonicalJson(value));
}

function freeze(value) {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
}

export function publicationContractNames() {
  return Object.freeze(Object.keys(identityFields));
}

export function publicationContractSchema(name) {
  const schema = registry.schemas[name];
  if (!schema || !Object.hasOwn(identityFields, name)) {
    fail('UnknownPublicationContract', `$.${name}`);
  }
  return freeze(copy(schema));
}

export function sealPublicationContract(name, supplied) {
  const schema = registry.schemas[name];
  const identity = identityFields[name];
  if (!schema || !identity || supplied === null ||
      typeof supplied !== 'object' || Array.isArray(supplied)) {
    fail('UnknownPublicationContract', `$.${name}`);
  }
  const body = copy(supplied);
  delete body[identity];
  const sealed = {...body, [identity]: canonicalCid(body)};
  validateSchema(schema, sealed, '$');
  if (Object.hasOwn(supplied, identity) && supplied[identity] !== sealed[identity]) {
    fail('PublicationIdentityMismatch', `$.${identity}`);
  }
  return freeze(sealed);
}

export function admitPublicationContract(name, supplied) {
  const schema = registry.schemas[name];
  const identity = identityFields[name];
  if (!schema || !identity) fail('UnknownPublicationContract', `$.${name}`);
  const body = copy(supplied);
  validateSchema(schema, body, '$');
  const preimage = {...body};
  delete preimage[identity];
  if (body[identity] !== canonicalCid(preimage)) {
    fail('PublicationIdentityMismatch', `$.${identity}`);
  }
  return freeze(body);
}

export function publicationIdentityField(name) {
  const field = identityFields[name];
  if (!field) fail('UnknownPublicationContract', `$.${name}`);
  return field;
}

export function createPublicationContractControlFixture() {
  const tokens = new WeakMap();
  const inspect = (name, value) => {
    const identityField = publicationIdentityField(name);
    const result = Object.freeze({
      name,
      identityField,
      identity: value[identityField],
      wire: canonicalJson(value),
    });
    tokens.set(result, value);
    return result;
  };
  const token = value => {
    const result = tokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign publication contract');
    }
    return result;
  };
  return Object.freeze({
    seal(name, bodyWire) {
      return inspect(name, sealPublicationContract(name, JSON.parse(bodyWire)));
    },
    admit(name, completeWire) {
      return inspect(name,
        admitPublicationContract(name, JSON.parse(completeWire)));
    },
    recordTransition(previous, next, uncommittedConfirmed) {
      const current = token(next);
      const prior = previous === undefined ? undefined : token(previous);
      if (next.name !== 'publication_record' ||
          previous !== undefined && previous.name !== 'publication_record') {
        return false;
      }
      if (prior === undefined) {
        return current.sequence === 0 &&
          !Object.hasOwn(current, 'prior_record_cid') &&
          current.state === 'preparing';
      }
      if (current.publication_attempt_cid !==
          prior.publication_attempt_cid ||
          current.sequence !== prior.sequence + 1 ||
          current.prior_record_cid !== prior.publication_record_cid) {
        return false;
      }
      const allowed = prior.state === 'preparing'
        ? ['preparing', 'committing', 'failed', 'cancelled']
        : ['committing', 'publication_unknown'].includes(prior.state)
          ? ['publication_unknown', 'succeeded', 'failed', 'cancelled']
          : [];
      return allowed.includes(current.state) &&
        (!['committing', 'publication_unknown'].includes(prior.state) ||
          !['failed', 'cancelled'].includes(current.state) ||
          uncommittedConfirmed === true);
    },
    recordAllowsCommit(record) {
      return record.name === 'publication_record' &&
        token(record).state === 'committing';
    },
    effectFreeCommitValid(
      runDefinition,
      invocation,
      definitions,
      artifacts,
      derivations,
      orderings,
      retentions,
      durableBindings,
      manifest,
      receipt,
      capturedRun,
      request,
      attempt,
      indexEntry,
    ) {
      const contracts = [
        runDefinition,
        invocation,
        ...definitions,
        ...artifacts,
        ...derivations,
        ...orderings,
        ...retentions,
        ...durableBindings,
        manifest,
        receipt,
        capturedRun,
        request,
        attempt,
        indexEntry,
      ];
      return contracts.every(contract => token(contract) !== undefined);
    },
    deliveryTransition(previous, next) {
      const current = token(next);
      const prior = previous === undefined ? undefined : token(previous);
      if (next.name !== 'delivery_record' ||
          previous !== undefined && previous.name !== 'delivery_record') {
        return false;
      }
      if (prior === undefined) {
        return current.sequence === 0 &&
          !Object.hasOwn(current, 'prior_record_cid');
      }
      return current.delivery_attempt_cid === prior.delivery_attempt_cid &&
        current.sequence === prior.sequence + 1 &&
        current.prior_record_cid === prior.delivery_record_cid &&
        prior.state === 'streaming' &&
        current.confirmed_byte_count >= prior.confirmed_byte_count;
    },
  });
}
