import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {sourceAliasBorrowedGeometry} from './source-alias-construction.mjs';
import {aliasRequestGeometry, snapshotAliasRequest, sourceAliasIdentityRow} from './source-alias-request.mjs';
import {isAbsolute} from 'node:path';
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {MAX_INSTALLED_SOURCE_AUTHORITIES} from './installed-source-limits.mjs';
import {installedSourcePublicationFacts} from './installed-source.mjs';

// Process-local custody of metadata admitted by the installed Source loader.
// These associations add no registry, persistent record or execution authority.
const namespaces = new WeakMap();
const observations = new WeakMap();
const publicationOriginals = new WeakMap();
const unresolved = () => Object.freeze({state: 'unresolved'});
const digest = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const validBinding = binding => Object.isFrozen(binding) &&
  typeof binding?.principalId === 'string' && binding.principalId.length > 0 &&
  cid(binding.contextCid) && Array.isArray(binding.inputs) && Object.isFrozen(binding.inputs) &&
  binding.inputs.length > 0 && binding.inputs.length <= 3 &&
  new Set(binding.inputs.map(value => value?.document_id)).size === binding.inputs.length &&
  binding.inputs.filter(value => ['source', 'program'].includes(value?.document_id)).length === 1 &&
  !(binding.inputs.some(value => value?.document_id === 'program') &&
    binding.inputs.some(value => value?.document_id === 'parameter_declarations')) &&
  binding.inputs.every(value => value !== null && typeof value === 'object' && Object.isFrozen(value) &&
    Object.keys(value).sort().join('\0') === 'byte_length\0document_id\0kind\0revision' &&
    ['source', 'program', 'parameter_declarations', 'parameters'].includes(value.document_id) &&
    value.kind === (value.document_id === 'source' ? 'text' : 'structured') &&
    typeof value.revision === 'string' && /^rev:[0-9a-f]{64}$/u.test(value.revision) &&
    Number.isSafeInteger(value.byte_length) && value.byte_length >= 0);

// Host-owned configuration declares the whole participating registration range,
// including an explicitly empty range. A missing or copied registration cannot
// close it. The proof covers the unfiltered installation, never visible aliases.
function admitRegistrationRange(declaration, sources) {
  if (declaration === null || typeof declaration !== 'object' ||
      Object.keys(declaration).sort().join('\0') !== 'name\0profilePaths' ||
      typeof declaration.name !== 'string' || !declaration.name ||
      !declaration.name.isWellFormed() ||
      Buffer.byteLength(declaration.name) > 256 ||
      !Array.isArray(declaration.profilePaths) ||
      declaration.profilePaths.length > MAX_INSTALLED_SOURCE_AUTHORITIES ||
      declaration.profilePaths.some(path => typeof path !== 'string' ||
        Buffer.byteLength(path) > 4096 || !isAbsolute(path)) ||
      new Set(declaration.profilePaths).size !== declaration.profilePaths.length ||
      !Array.isArray(sources) || sources.length > MAX_INSTALLED_SOURCE_AUTHORITIES) {
    throw new TypeError('InvalidSourceNamespaceDeclaration');
  }
  const expected = [...declaration.profilePaths].sort();
  const retained = sources.map(source => ({source, facts: installedSourcePublicationFacts(source)}));
  if (retained.some(value => value.facts === undefined) ||
      retained.length !== expected.length ||
      retained.map(value => value.facts.path).sort().some((path, index) => path !== expected[index])) {
    return undefined;
  }
  return retained.toSorted((left, right) => left.facts.path < right.facts.path ? -1 : left.facts.path > right.facts.path ? 1 : 0);
}

function admitNamespace(declaration, sources, aliases, environmentCid) {
  const range = admitRegistrationRange(declaration, sources);
  if (range === undefined) return undefined;
  const retained = range.map(value => value.facts);
  const ordered = retained.toSorted((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
  let count = 0, bytes = 0;
  for (const value of ordered) {
    count += value.aliases.length;
    bytes += Buffer.byteLength(JSON.stringify(value.aliases));
    if (count > 1024 || bytes > 1024 * 1024) return undefined;
  }
  const allAliases = ordered.flatMap(value => value.aliases);
  const rows = entries => entries.map(sourceAliasIdentityRow).toSorted((left, right) =>
      left[0] < right[0] ? -1 : left[0] > right[0] ? 1 : 0);
  if (JSON.stringify(rows(allAliases)) !== JSON.stringify(rows(aliases))) return undefined;
  return Object.freeze({name: declaration.name,
    revision: digest({version: 'actql-source-namespace/0.1', name: declaration.name,
      environmentCid, registrations: ordered.map(value => ({path: value.path,
        revision: value.revision, aliases: rows(value.aliases)}))}),
    aliases: Object.freeze(allAliases)});
}

// Complete installed selector registrations are a separate domain from query
// aliases. The common Catalog Owner checks every participating environment and
// its exact correspondence to the Host's unfiltered SourceRequestContracts.
function admitSelectorNamespace(declaration, sources, moon, environment, environmentCid) {
  const range = admitRegistrationRange(declaration, sources);
  if (range === undefined) return undefined;
  if (typeof moon.clientProgramCheckSourceSelectorRange !== 'function') {
    throw new TypeError('InvalidSourceSelectorNamespaceInstallation');
  }
  let bytes = 0;
  const registrations = [], identities = [];
  for (const {source, facts} of range) {
    const wire = source.environmentWire;
    if (typeof wire !== 'string') return undefined;
    bytes += Buffer.byteLength(wire);
    if (bytes > 16 * 1024 * 1024) return undefined;
    let admitted;
    try {
      const evidenceCid = JSON.parse(wire).evidence_bundle_cid;
      admitted = moon.clientProgramCheckEnvironment(wire, evidenceCid,
        false, false, true, false, false, false, false);
    } catch { return undefined; }
    if (admitted === undefined) return undefined;
    registrations.push(admitted);
    identities.push({path: facts.path, revision: facts.revision,
      environmentCid: moon.clientProgramCheckingEnvironmentCid(admitted)});
  }
  const catalogRange = moon.clientProgramCheckSourceSelectorRange(environment, registrations);
  if (catalogRange === undefined) return undefined;
  return Object.freeze({name: declaration.name, range: catalogRange,
    revision: digest({version: 'actql-source-selector-namespace/0.1',
      namespace: declaration.name, environmentCid, registrations: identities})});
}

// Installation metadata only. Client requests never supply this publication.
export function splitSourceAliasProfile(profile) {
  if (profile === null || typeof profile !== 'object' || Array.isArray(profile)) {
    throw new TypeError('InvalidInstalledSourceProfile');
  }
  const {queryAliases = [], ...providerProfile} = profile;
  if (!Array.isArray(queryAliases) || queryAliases.length > 1024) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  for (const entry of queryAliases) {
    if (entry !== null && typeof entry === 'object' && Object.hasOwn(entry, 'request')) {
      const request = Object.getOwnPropertyDescriptor(entry, 'request');
      if (!request || !Object.hasOwn(request, 'value')) throw new TypeError('InvalidPublicSourcePublication');
      aliasRequestGeometry(request.value);
    }
  }
  if (Buffer.byteLength(JSON.stringify(queryAliases)) > 1024 * 1024) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  // The profile was parsed by this loader; copy and freeze each metadata row
  // before it becomes shared with the installed Host's preparation closure.
  const aliases = Object.freeze(queryAliases.map(entry => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).filter(key => key !== 'request').sort().join('\0') !==
          ['name', 'schemaContractCid', 'sourceRef', 'sourceViewContractCid'].join('\0') ||
        !['name', 'sourceRef', 'schemaContractCid', 'sourceViewContractCid']
          .every(key => typeof entry[key] === 'string') ||
        entry.name.length === 0 || entry.name.length > 1024 ||
        entry.sourceRef.length === 0 || entry.sourceRef.length > 4096 ||
        ![entry.schemaContractCid, entry.sourceViewContractCid]
          .every(value => /^sha256:[0-9a-f]{64}$/u.test(value))) {
      throw new TypeError('InvalidPublicSourcePublication');
    }
    return Object.freeze({...entry, ...(Object.hasOwn(entry, 'request')
      ? {request: snapshotAliasRequest(entry.request)} : {})});
  }));
  return {providerProfile, queryAliases: aliases};
}

export function sourceAliasPublication(moon, environment, aliases = [], tableWrites = [],
  {namespace, selectorNamespace, installedSources = [], updateTargets = [], storeTargets = []} = {}) {
  // Installed metadata already has one immutable owned snapshot. Validate
  // plain DATA without invoking hooks, then borrow it through publication.
  // Freeze is stability only; Common still checks the original Source owner.
  if (types.isProxy(aliases)) throw new TypeError('InvalidPublicSourcePublication');
  if (Object.isFrozen(aliases)) sourceAliasBorrowedGeometry(aliases);
  else aliases = splitSourceAliasProfile({queryAliases: aliases}).queryAliases;
  if (!Array.isArray(tableWrites) || tableWrites.length > 1024 ||
      Buffer.byteLength(JSON.stringify(tableWrites)) > 1024 * 1024) {
    throw new TypeError('InvalidPublicTableWritePublication');
  }
  if (!Array.isArray(updateTargets) || updateTargets.length > 1024 ||
      Buffer.byteLength(JSON.stringify(updateTargets)) > 1024 * 1024) {
    throw new TypeError('InvalidPublicUpdateTargetPublication');
  }
  updateTargets = Object.freeze(updateTargets.map(entry => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join('\0') !== 'installationBindingCid\0installationOwnerCid\0name\0targetRef' ||
        typeof entry.name !== 'string' || entry.name.length === 0 ||
        entry.name.length > 1024 || !entry.name.isWellFormed() ||
        typeof entry.targetRef !== 'string' || entry.targetRef.length === 0 ||
        entry.targetRef.length > 4096 || !entry.targetRef.isWellFormed() ||
        !cid(entry.installationBindingCid) || !cid(entry.installationOwnerCid)) {
      throw new TypeError('InvalidPublicUpdateTargetPublication');
    }
    return Object.freeze({...entry});
  }));
  if (!Array.isArray(storeTargets) || storeTargets.length > 1024 ||
      Buffer.byteLength(JSON.stringify(storeTargets)) > 1024 * 1024) {
    throw new TypeError('InvalidPublicStoreTargetPublication');
  }
  storeTargets = Object.freeze(storeTargets.map(entry => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join('\0') !== 'installationBindingCid\0installationOwnerCid\0name\0targetRef' ||
        typeof entry.name !== 'string' || entry.name.length === 0 ||
        entry.name.length > 1024 || !entry.name.isWellFormed() ||
        typeof entry.targetRef !== 'string' || entry.targetRef.length === 0 ||
        entry.targetRef.length > 4096 || !entry.targetRef.isWellFormed() ||
        !cid(entry.installationBindingCid) || !cid(entry.installationOwnerCid)) {
      throw new TypeError('InvalidPublicStoreTargetPublication');
    }
    return Object.freeze({...entry});
  }));
  const publication = Object.freeze({
    environmentCid: moon.clientProgramCheckingEnvironmentCid(environment),
    aliases, ...(updateTargets.length === 0 ? {} : {updateTargets}),
    ...(storeTargets.length === 0 ? {} : {storeTargets}),
    ...(tableWrites.length === 0 ? {} : {
      tableWrites: Object.freeze(tableWrites.map(binding => Object.freeze({
        ...binding, expectedTable: binding.expectedTable === null ? null :
          Object.freeze({...binding.expectedTable}),
      }))),
    })});
  const wire = JSON.stringify(publication);
  const preparedEnvironment = typeof moon.clientProgramPreparePublicSourceEnvironment !== 'function'
    ? undefined : moon.clientProgramPreparePublicSourceEnvironment(environment, wire);
  if (preparedEnvironment === undefined) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  const queryAlias = namespace === undefined ? undefined :
    admitNamespace(namespace, installedSources, aliases, publication.environmentCid);
  const sourceSelector = selectorNamespace === undefined ? undefined :
    admitSelectorNamespace(selectorNamespace, installedSources, moon, environment, publication.environmentCid);
  if (queryAlias !== undefined || sourceSelector !== undefined) {
    namespaces.set(publication, Object.freeze({queryAlias, sourceSelector}));
  }
  publicationOriginals.set(publication, {moon, environment,
    original: Object.freeze({wire, preparedEnvironment})});
  return publication;
}

// Only the owned declaration in its original runtime/Environment carries this
// pure preparation. Equal fields or a copied publication do not recover it.
export function sourceAliasPublicationOriginal(moon, environment, publication) {
  const retained = publicationOriginals.get(publication);
  return retained !== undefined && retained.moon === moon && retained.environment === environment
    ? retained.original : undefined;
}

// Cut this declaration's association only. Other legitimate holders of the
// pure Common value remain valid; this is not a physical release ACK.
export function retireSourceAliasPublicationOriginal(moon, environment, publication) {
  const retained = publicationOriginals.get(publication);
  if (retained !== undefined && retained.moon === moon && retained.environment === environment) {
    publicationOriginals.delete(publication);
  }
}

// A current decision in its own short-lived scope: ordinary check/read grants
// do not disclose negative namespace membership. Deferred decisions remain
// unresolved; there is no Checkpoint journal or automatic approval here.
export async function observeSourceAliasNamespace(publication, authorization,
  binding, {signal} = {}) {
  return observeNamespace(publication, authorization, binding, 'queryAlias', signal);
}

export async function observeSourceSelectorNamespace(publication, authorization,
  binding, {signal} = {}) {
  return observeNamespace(publication, authorization, binding, 'sourceSelector', signal);
}

async function observeNamespace(publication, authorization, binding, domain, signal) {
  const proof = namespaces.get(publication)?.[domain];
  if (proof === undefined || typeof authorization?.withContext !== 'function' ||
      !validBinding(binding) || domain === 'sourceSelector' &&
      !binding.inputs.some(input => input.document_id === 'program')) return unresolved();
  const subjectCid = digest({version: 'actql-source-namespace-observation/0.1',
    ...(domain === 'sourceSelector' ? {domain: 'source_selector_registration'} : {}),
    namespace: proof.name, revision: proof.revision, contextCid: binding.contextCid,
    inputs: binding.inputs});
  let scope;
  try {
    scope = authorization.withContext({principal: binding.principalId,
      contextCid: binding.contextCid});
    const decision = await scope.authorize('preparation', {
      connection: 'actql-source-namespace', resource: proof.name,
      operation: 'inspect_absence',
    }, {subjectCid, signal, allowDeferral: false});
    signal?.throwIfAborted();
    const authority = authorizationDispatchFacts(decision);
    if (authority === undefined || authority.principal !== binding.principalId ||
        authority.configurationCid !== scope.configurationCid ||
        decision.boundary !== 'preparation' || decision.subjectCid !== subjectCid ||
        decision.contextCid !== binding.contextCid ||
        decision.tuple?.principal !== binding.principalId ||
        decision.tuple?.connection !== 'actql-source-namespace' ||
        decision.tuple?.resource !== proof.name ||
        decision.tuple?.operation !== 'inspect_absence') return unresolved();
    const observation = Object.freeze({state: 'complete'});
    observations.set(observation, Object.freeze({publication, binding, proof, domain,
      authority: Object.freeze({...authority, contextCid: decision.contextCid,
        entryId: decision.entryId, answeringAuthority: decision.authority})}));
    return observation;
  } catch (cause) {
    if (signal?.aborted) throw cause;
    return unresolved();
  } finally {
    scope?.close();
  }
}

// Only the original observation for this call may supply metadata to the common
// checker. Even an authentic observation cannot be transplanted to a new input,
// namespace or attempt. The returned private facts never go directly on wire.
export function sourceAliasNamespaceObservationFacts(publication, observation, binding) {
  const retained = observations.get(observation);
  return retained?.domain === 'queryAlias' && retained.publication === publication && retained.binding === binding
    ? Object.freeze({namespace: retained.proof.name, revision: retained.proof.revision,
      aliases: retained.proof.aliases, authority: retained.authority}) : undefined;
}

export function sourceSelectorNamespaceObservationFacts(publication, observation, binding) {
  const retained = observations.get(observation);
  return retained?.domain === 'sourceSelector' && retained.publication === publication && retained.binding === binding
    ? Object.freeze({namespace: retained.proof.name, revision: retained.proof.revision,
      range: retained.proof.range, authority: retained.authority}) : undefined;
}
