import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '@actql/sdk/host-port';
import {checked, rowSourceMapping}
  from '@actql/local-node/connector-installation';

const registration = 'external_effect';
const revision = 'external_effect/0.1';
const operation = 'external_effect:events:create';
const updateOperation = 'external_effect:events:update';
const targetOperation = 'external_effect:events:target';
const origin = 'https://external-effect.fixture.invalid';
const assets = new URL('../../../../src/connectors/external_effect/', import.meta.url);
const fail = code => { throw Object.assign(new Error(code), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
    [...keys].sort().join('\0');
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;

export function checkProfile(profile) {
  if (!exact(profile, ['version', 'connectorId', 'accountConfigurationWire',
    'siteProfilePath', ...(profile?.write === undefined ? [] : ['write'])]) ||
      (profile.write !== undefined && profile.write !== 'update') || profile.version !== 'actql-installed-external-effect/0.1' ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire) ||
      !text(profile.siteProfilePath) || !isAbsolute(profile.siteProfilePath)) {
    fail('InvalidExternalEffectProfile');
  }
  return Object.freeze({...profile});
}

export async function identityParts(profile, read) {
  const selected = checkProfile(profile);
  return [{...selected, accountConfigurationWire:
    JSON.parse(selected.accountConfigurationWire)}, await read(selected.siteProfilePath)];
}

function writeDefinition(profile) {
  return profile.write === 'update' ? 'updates.json' : 'writes.json';
}

function sourcesOf(profile) {
  return Object.freeze((profile.write === 'update' ? ['note'] : ['key', 'note']).map(field =>
    Object.freeze({target: field, field, null_behavior: 'reject'})));
}

async function declarationOf(moon, profile) {
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    profile.connectorId, registration, revision,
    await readFile(new URL('catalog-views.json', assets), 'utf8'), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const mapping = rowSourceMapping(moon, declaration,
    await readFile(new URL(writeDefinition(profile), assets), 'utf8'), 'events', sourcesOf(profile), profile.write);
  return {declaration, declared, mapping};
}

export async function publish(profile, {moon}) {
  const selected = checkProfile(profile);
  const {declared, mapping} = await declarationOf(moon, selected);
  return Object.freeze({connectorId: selected.connectorId, catalogCid: declared.catalog_cid,
    mappings: [Object.freeze({resource: 'events', kind: selected.write ?? 'create',
      target: mapping.target, mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid})]});
}

async function siteOf(path, readers) {
  const site = await readers.readJson(path, {maxBytes: 16384});
  if (!exact(site, ['resourceOrigin', 'namespaceId', 'environment', 'siteKey',
    'siteGeneration', 'credentialAuthorityId', 'credentialKeyId',
    'credentialPrivateKeyPath', 'journalRoot']) || site.resourceOrigin !== origin ||
      ![site.credentialPrivateKeyPath, site.journalRoot].every(value =>
        text(value) && isAbsolute(value))) fail('InvalidExternalEffectSite');
  return site;
}

export async function load(profile, {root, principalId, moon, providerMoon,
  baseEnvironmentWire, runtimeBundleCid, resolveSecret, ledgerRoot, installation, construction}) {
  if (typeof construction?.prepareAuthoredDeclaration !== 'function' ||
      typeof construction.prepareMappings !== 'function' ||
      typeof construction.openRowSite !== 'function' ||
      typeof construction.createRowEffect !== 'function' ||
      typeof construction.prepareEffectDriverConstruction !== 'function' ||
      typeof construction.configurationReader?.readOriginalText !== 'function' ||
      typeof construction.configurationReader.readJson !== 'function') {
    fail('ExternalEffectConstructionUnavailable');
  }
  const selected = checkProfile(profile);
  if (typeof providerMoon?.externalEffectRequestJson !== 'function' ||
      typeof providerMoon?.externalEffectObservationJson !== 'function') {
    fail('ExternalEffectProviderMissing');
  }
  const readers = construction.configurationReader;
  const specification = await siteOf(selected.siteProfilePath, readers);
  construction.prepareAuthoredDeclaration(
    await readers.readOriginalText(new URL('catalog-views.json', assets)));
  construction.prepareMappings(await readers.readOriginalText(new URL(writeDefinition(selected), assets)),
    Object.freeze([Object.freeze({resource: 'events', sources: sourcesOf(selected),
      ...(selected.write === undefined ? {} : {operation: selected.write})})]));
  const connection = 'external_effect:events';
  const {site, authorization} = await construction.openRowSite({profile: specification,
    accountConfiguration: selected.accountConfigurationWire, connection,
    resolveSecret: resolveSecret ?? (async () => fail('FixtureSecretUnavailable')),
    responseHeaders: installation?.responseHeaders ?? [], admitsApprovalTarget: () => false});
  const native = captureEffectProvider(providerMoon, selected.write);
  const implementation = construction.prepareEffectDriverConstruction(Object.freeze({
    capacity() {
      return native.externalEffectDriverConstructionCapacity(BigInt(
        origin.length + specification.namespaceId.length));
    },
    project() {return selected.write === 'update'
      ? standardUpdateImplementation(native, specification) : standardCreateImplementation(native, specification);},
  }));
  return await construction.createRowEffect({connection, runtimeBundleCid,
    bindingCid: cid({version: 'actql-external-effect-binding/0.1',
      contextCid: authorization.context.contextCid, specification}),
    ledgerRoot, installation, ...implementation});
}

// Retain the original native methods and receiver before initialization can
// reenter. The standard composer forwards their quantity profile unchanged;
// these are constructor DATA, never a declaration, Run, grant or cleanup ACK.
function captureEffectProvider(provider, kind) {
  if (provider === null || typeof provider !== 'object' || nodeTypes.isProxy(provider)) {
    fail('ExternalEffectProviderMissing');
  }
  const names = ['externalEffectRequestJson', 'externalEffectObservationJson',
    'installedStandardCreateConstructionProfile', 'installedStandardCreateHttpLimits',
    'externalEffectDriverConstructionCapacity',
    ...(kind === 'update' ? ['installedDeclaredUpdateConstructionProfile',
      'installedDeclaredUpdateCaptureConstructionProfile'] : [])];
  return Object.freeze(Object.fromEntries(names.map(name => {
    const field = Object.getOwnPropertyDescriptor(provider, name);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
        nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) {
      fail('ExternalEffectProviderMissing');
    }
    const method = field.value;
    return [name, (...args) => Reflect.apply(method, provider, args)];
  })));
}

function standardCreateImplementation(providerMoon, specification) {
  // The same native limits bound the real send and the standard recipe. The
  // common constructor validates its HTTP bounds; no second capacity table.
  const [maxRequestBytes, maxResponseBytes] = providerMoon.installedStandardCreateHttpLimits();
  const boundaryCid = cid({origin, namespace: specification.namespaceId});
  const write = Object.freeze({kind: 'create', operation, resourceKind: 'event', boundaryCid,
    http: Object.freeze({origin, method: 'POST', path: '/events',
      responseHeaders: Object.freeze([]), maxRequestBytes, maxResponseBytes}),
    request({resource, value}) {
      if (resource !== 'events' || !exact(value, ['key', 'note']) ||
          typeof value.key !== 'string' || typeof value.note !== 'string') {
        fail('InvalidExternalEffectValue');
      }
      const prepared = JSON.parse(providerMoon.externalEffectRequestJson(value.key, value.note));
      if (prepared.refused) fail(prepared.refused);
      // Preserve this provider's original request identity and exact bytes.
      const requestCid = `sha256:${createHash('sha256')
        .update('external_effect:POST:/events\0').update(prepared.body).digest('hex')}`;
      return Object.freeze({method: 'POST', path: '/events', body: prepared.body,
        key: value.key, requestCid});
    },
    classify: ({request, observation}) => JSON.parse(providerMoon.externalEffectObservationJson(
      observation.statusCode, observation.body, request.key)),
  });
  return Object.freeze({providerMoon, write});
}

const updateRecovery = 'external-event-update';
const updateBounds = Object.freeze({maxRequestBytes: 512, maxResponseBytes: 512, maxTargetBytes: 80});
const eventId = value => typeof value === 'string' && /^[a-z0-9-]{1,32}$/u.test(value);
const eventNote = value => typeof value === 'string' && value.length <= 64 && value.isWellFormed();
const eventPath = id => '/events/' + id;
const updateWireCid = wire => 'sha256:' + createHash('sha256').update(wire).digest('hex');

function standardUpdateImplementation(providerMoon, specification) {
  const boundaryCid = cid({origin, namespace: specification.namespaceId, operation: updateOperation});
  const requestCid = request => cid({version: updateRecovery, boundaryCid, ...request});
  const requestOf = (id, note) => {
    if (!eventId(id) || !eventNote(note)) fail('InvalidExternalUpdateValue');
    return Object.freeze({id, note, body: JSON.stringify({note})});
  };
  const original = member => {
    if (member?.kind !== 'update' || member.resource !== 'events') fail('ForeignExternalUpdateMember');
    return [member.effectId, member.memberIndex, member.mapping.mappingCid];
  };
  const write = Object.freeze({
    kind: 'update', operation: updateOperation, transport: updateBounds,
    targetRead: Object.freeze({operation: targetOperation, transport: updateBounds}),
    prepareRequest({member, value, selector}) {
      original(member);
      if (!exact(value, ['note'])) fail('InvalidExternalUpdateValue');
      const request = requestOf(selector, value.note);
      return Object.freeze({request, requestCid: requestCid(request)});
    },
    requestFacts: request => ({target: request.id, value: {note: request.note}}),
    requestCid,
    async observeTargets({member, entries, readTarget}) {
      original(member);
      const observed = [];
      for (const [index, {request}] of entries.entries()) {
        const value = await readTarget(index, {method: 'GET', path: eventPath(request.id)}, response => {
          if (response.statusCode !== 200) fail('ExternalUpdateTargetUnavailable');
          const row = JSON.parse(Buffer.from(response.body).toString('utf8'));
          if (!exact(row, ['id', 'note']) || row.id !== request.id || !eventNote(row.note)) fail('ExternalUpdateTargetUnavailable');
          return Object.freeze({identity: row.id, versionCid: cid(row), before: Object.freeze({note: row.note})});
        }, () => {});
        observed.push(value);
      }
      return observed;
    },
    prepareUpdateWrite(member, request, _current, resourceOrigin, selectedRegistration, signal) {
      original(member);
      if (resourceOrigin !== origin || selectedRegistration !== registration) fail('ForeignExternalUpdateSite');
      signal?.throwIfAborted();
      return {method: 'PUT', path: eventPath(request.id), body: request.body};
    },
    project({request, observation}) {
      if (observation.statusCode !== 200) return {kind: 'unclassified-response'};
      const result = JSON.parse(Buffer.from(observation.body).toString('utf8'));
      if (!exact(result, ['id', 'note']) || result.id !== request.id || result.note !== request.note) {
        return {kind: 'unclassified-response'};
      }
      return {kind: 'typed-success-response', outcome: {state: 'applied', action: 'updated', result: {id: result.id}}};
    },
    footprint: () => ({providerNamespace: registration, resourceKind: 'event', boundaryCid}),
    recoveryEntry({member, entries}) {
      if (entries.length !== 1) fail('InvalidExternalUpdateRecovery');
      const [entry] = entries;
      const wire = canonicalJson([boundaryCid, original(member), entry.request.id, entry.request.note]);
      return {kind: updateRecovery, observationCid: updateWireCid(wire), wire};
    },
    recoverRequests({durable, members, body}) {
      if (members.length !== 1 || body.effects?.[0]?.changes?.length !== 1 ||
          durable.connectorRecovery?.length !== 1) fail('InvalidExternalUpdateRecovery');
      const [saved] = durable.connectorRecovery, [member] = members;
      if (saved.kind !== updateRecovery || saved.memberIndex !== member.memberIndex ||
          typeof saved.wire !== 'string' || Buffer.byteLength(saved.wire) > 1024 ||
          updateWireCid(saved.wire) !== saved.observationCid) fail('InvalidExternalUpdateRecovery');
      const savedRequest = JSON.parse(saved.wire);
      if (!Array.isArray(savedRequest) || savedRequest.length !== 4 || canonicalJson(savedRequest) !== saved.wire ||
          savedRequest[0] !== boundaryCid || canonicalJson(savedRequest[1]) !== canonicalJson(original(member))) {
        fail('InvalidExternalUpdateRecovery');
      }
      return {requests: [[requestOf(savedRequest[2], savedRequest[3])]]};
    },
  });
  return Object.freeze({providerMoon, write, limits: Object.freeze({maxRows: 1, maxMembers: 1})});
}
