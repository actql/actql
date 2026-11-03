// Public checking observations of authored source or Program for one audience. The Host decides which
// installed query names the audience may see with the source's own read
// authorization; absent, denied and undecided names are all left out before
// MoonBit checks anything, so the private distinction never reaches the
// outcome. MoonBit owns checking and the one actql-check-outcome/0.1
// projection.
import {createHmac, randomBytes} from 'node:crypto';
import {validCheckOutcome, checkReasonSchemaCid, checkOutcomeSchemaCid} from '../../packages/client-wire/index.mjs';
// The common value encoding: String values stay exact (CR, LF and composed
// or decomposed spellings differ); only object member names are canonical.
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {observeSourceSelectorNamespace, sourceSelectorNamespaceObservationFacts,
  observeSourceAliasNamespace, sourceAliasNamespaceObservationFacts} from './source-alias-publication.mjs';

const version = 'actql-check-outcome/0.1';
// Revisions bound into every context reference. A change to what an audience
// may see, or to the projection, must never reuse an earlier reference.
const disclosurePolicy = 'actql-check-disclosure/0.1';
const contextVersion = 'actql-check-context/0.1';

const failed = (code, correlation_ref) => Object.freeze({outcome: 'failed', correlation_ref,
  problem: Object.freeze({code}), reason_schema_cid: checkReasonSchemaCid,
  outcome_schema_cid: checkOutcomeSchemaCid, version});

// Shape validation alone cannot bind an otherwise valid old Owner report to
// this call. Compare the metadata issued to the existing checker before the
// public SDK can associate its opaque revisions with the current snapshot.
const validBoundOutcome = (outcome, context, scope, documents) => {
  const report = outcome?.report ?? outcome?.partial_report;
  return validCheckOutcome(outcome) && (!report ||
    report.context_ref === context &&
    report.scope.kind === scope &&
    report.inputs.length === documents.length && documents.every(expected =>
      report.inputs.some(actual => actual.document_id === expected.document_id &&
        actual.kind === expected.kind && actual.revision === expected.revision &&
        actual.byte_length === expected.byte_length)));
};

export function installNodeClientCheck({moon, environment, publication,
  sourceAccesses = [], tableWriteAccesses = [], namespaceAuthorizationFor,
  updateTargetDisclosure,
  contextKey = randomBytes(32)}) {
  if (moon === null || typeof moon !== 'object' ||
      typeof moon.clientProgramCheckSource !== 'function' ||
      typeof moon.clientProgramCheckProgram !== 'function' ||
      typeof moon.clientProgramCheckUnavailable !== 'function' ||
      typeof moon.clientProgramCheckCompilerIdentity !== 'function' ||
      typeof moon.clientProgramCheckContextIdentity !== 'function' ||
      typeof moon.clientProgramCheckSourceNamespace !== 'function' ||
      typeof moon.clientProgramCheckSourceSelectorNamespace !== 'function' ||
      typeof moon.clientProgramCheckingEnvironmentCid !== 'function' ||
      environment === undefined ||
      !(contextKey instanceof Uint8Array) || contextKey.byteLength !== 32 ||
      !Array.isArray(sourceAccesses) || sourceAccesses.some(access =>
        typeof access?.authorization?.authorize !== 'function') ||
      namespaceAuthorizationFor !== undefined && typeof namespaceAuthorizationFor !== 'function' ||
      !Array.isArray(tableWriteAccesses) || tableWriteAccesses.some(access =>
        typeof access?.authorization?.authorize !== 'function' ||
        !/^sha256:[0-9a-f]{64}$/u.test(access.capabilityCid ?? '') ||
        typeof access.connection !== 'string' || !access.connection ||
        typeof access.resource !== 'string' || !access.resource)) {
    throw new TypeError('InvalidClientCheckInstallation');
  }
  const environmentCid = moon.clientProgramCheckingEnvironmentCid(environment);
  const compiler = JSON.parse(moon.clientProgramCheckCompilerIdentity());
  const checkingContext = JSON.parse(moon.clientProgramCheckContextIdentity(environment));
  const aliases = publication?.aliases ?? [];
  const tableWrites = publication?.tableWrites ?? [];
  const updateTargets = Object.freeze([...(publication?.updateTargets ?? [])]);
  const updateDisclosureMethod = updateTargetDisclosure === undefined ? undefined :
    Object.getOwnPropertyDescriptor(updateTargetDisclosure, 'visibleFor')?.value;
  if ((updateTargetDisclosure !== undefined && typeof updateDisclosureMethod !== 'function') ||
      updateTargets.length > 1024 || updateTargets.some(entry =>
        entry === null || typeof entry !== 'object' || !Object.isFrozen(entry) ||
        Object.keys(entry).sort().join('\0') !==
          'installationBindingCid\0installationOwnerCid\0name\0targetRef')) {
    throw new TypeError('InvalidClientCheckInstallation');
  }
  if (publication !== undefined &&
      publication.environmentCid !== environmentCid) {
    throw new TypeError('InvalidClientCheckInstallation');
  }
  const key = Buffer.from(contextKey);

  // Consult each installed Source's own decision owner, once per check,
  // independently of published or mentioned names. Missing read tuples and
  // unusable owners hide their own names, just like deny/held/failed decisions.
  // They do not establish or revoke the whole check binding: public ingress
  // already authenticated and authorized this call, and installation admitted
  // its checking environment. The checker retains protected obligations and
  // independent disclosable violations under that binding.
  const accesses = sourceAccesses.map(access => ({...access}));
  const aliasesFor = async (sourceAccess, signal) => {
    const readTuple = typeof sourceAccess.sourceRef === 'string' &&
      typeof sourceAccess.resource === 'string';
    if (!readTuple) return null;
    let decision;
    try {
      decision = await sourceAccess.authorization.authorize('acquisition', {
        connection: sourceAccess.connection,
        resource: sourceAccess.resource, operation: 'read',
      }, {subjectCid: environmentCid, signal});
    } catch (cause) {
      if (signal?.aborted) throw cause;
      return undefined;
    }
    if (decision?.action !== 'dispatch') return [];
    return aliases.filter(alias => alias.sourceRef === sourceAccess.sourceRef);
  };
  const visibleAliases = async signal => {
    const portions = [];
    for (const access of accesses) {
      signal?.throwIfAborted();
      portions.push(await aliasesFor(access, signal));
    }
    return portions.flatMap(value => value ?? []).sort((left, right) =>
      left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
  };

  // Table names have their own installed write scopes. A Source read decision
  // cannot disclose or authorize a destination. This preparation decision
  // discloses metadata only; the Effect still requires its ordinary approval
  // and current commit authorization against the sealed operation.
  const writeAccesses = tableWriteAccesses.map(access => ({...access}));
  const visibleTableWrites = async signal => {
    const visibleCapabilities = new Set();
    for (const access of writeAccesses) {
      signal?.throwIfAborted();
      let decision;
      try {
        decision = await access.authorization.authorize('preparation', {
          connection: access.connection, resource: access.resource,
          operation: 'write',
        }, {subjectCid: access.capabilityCid, signal});
      } catch (cause) {
        if (signal?.aborted) throw cause;
        continue;
      }
      if (decision?.action === 'dispatch') visibleCapabilities.add(access.capabilityCid);
    }
    return tableWrites.filter(binding => visibleCapabilities.has(binding.capabilityCid));
  };

  // The installed Effect owner retains currentness and metadata disclosure.
  // Its selected members must be these exact original publication entries;
  // returned JSON, equal CIDs or a Source read decision cannot replace them.
  const visibleUpdateTargets = async (principalId, signal) => {
    if (updateDisclosureMethod === undefined) return [];
    let selected;
    try {
      selected = await Reflect.apply(updateDisclosureMethod, updateTargetDisclosure,
        [Object.freeze({principalId, signal})]);
    } catch (cause) {
      if (signal?.aborted) throw cause;
      return [];
    }
    signal?.throwIfAborted();
    if (!Array.isArray(selected) || selected.length > updateTargets.length ||
        new Set(selected).size !== selected.length ||
        selected.some(entry => !updateTargets.includes(entry))) return [];
    return updateTargets.filter(entry => selected.includes(entry));
  };

  // Keyed by this Host over everything the verdict is about: the audience
  // and its disclosure policy, the exact source and format, the scope, the
  // compiler, both reporting schema identities and public checking selections,
  // the visible names and supplied
  // bindings. Equal requests give an equal reference here; the reference is
  // not a public hash of supplied values.
  const contextRef = (principalId, input, parameters, visible, visibleWrites, visibleUpdates, kind, scope, namespace) => {
    const bound = {version: contextVersion, audience: principalId,
      disclosure_policy: disclosurePolicy, projection: version, scope,
      compiler, reason_schema_cid: checkReasonSchemaCid,
      outcome_schema_cid: checkOutcomeSchemaCid,
      checking_context: checkingContext, visible_aliases: visible,
      ...(namespace === undefined ? {} : {[kind === 'program' ? 'source_selector_namespace' : 'source_namespace']: {
        name: namespace.namespace, revision: namespace.revision, authority: namespace.authority}}),
      ...(visibleWrites.length === 0 ? {} : {visible_table_writes: visibleWrites}),
      ...(visibleUpdates.length === 0 ? {} : {visible_update_targets: visibleUpdates})};
    let preimage;
    try {
      preimage = canonicalJson({...bound,
        ...(kind === 'program' ? {program: {kind: 'structured', received: JSON.stringify(input)}} : {source: {format: input.format, text: input.text},
        parameter_declarations: input.parameterDeclarations ?? null}),
        parameters: kind === 'program' && parameters != null
          ? {kind: 'structured', received: JSON.stringify(parameters)} : parameters ?? null});
    } catch {
      // Input the common encoding cannot represent (colliding member names
      // or ill-formed text) is bound by its exact received spelling.
      preimage = canonicalJson({...bound,
        received: JSON.stringify({input, parameters})});
    }
    return `ctx:${createHmac('sha256', key).update(preimage).digest('hex')}`;
  };

  const revision = (documentId, bytes) => `rev:${createHmac('sha256', key)
    .update('actql-check-input/0.1\0').update(documentId).update('\0')
    .update(bytes).digest('hex')}`;

  const documentBinding = (documentId, kind, bytes) => ({document_id: documentId,
    kind, revision: revision(documentId, bytes), byte_length: Buffer.byteLength(bytes, 'utf8')});

  const check = async (request, projectOriginal) => {
    const {principalId, kind, input, parameters, signal, scope} = request;
    if (!['template_only', 'bound_input'].includes(scope) || !['text', 'program'].includes(kind) ||
        scope === 'template_only' && Object.hasOwn(request, 'parameters')) {
      const error = new TypeError('InvalidCheckRequest');
      error.code = 'InvalidCheckRequest';
      throw error;
    }
    // One opaque reference for this reporting attempt, independent of source,
    // context, authorization and the presence of any protected Source.
    const correlationRef = `corr:${randomBytes(16).toString('hex')}`;
    signal?.throwIfAborted();
    const visible = await visibleAliases(signal);
    const visibleWrites = await visibleTableWrites(signal);
    const visibleUpdates = await visibleUpdateTargets(principalId, signal);
    signal?.throwIfAborted();
    let context = contextRef(principalId, input, parameters, visible, visibleWrites, visibleUpdates, kind, scope);
    if (kind === 'program') {
      const document = JSON.stringify(input);
      const supplied = parameters == null ? undefined : JSON.stringify(parameters);
      const original = documentBinding('program', 'structured', document);
      const bindings = supplied === undefined ? undefined : documentBinding('parameters', 'structured', supplied);
      let namespace;
      if (namespaceAuthorizationFor !== undefined) {
        const binding = Object.freeze({principalId, contextCid: `sha256:${context.slice(4)}`,
          inputs: Object.freeze([original, ...(bindings ? [bindings] : [])]
            .map(value => Object.freeze({...value})))});
        let gate;
        try {
          gate = await namespaceAuthorizationFor({principalId, signal});
          const observation = await observeSourceSelectorNamespace(publication, gate, binding, {signal});
          const facts = sourceSelectorNamespaceObservationFacts(publication, observation, binding);
          if (facts !== undefined) {
            context = contextRef(principalId, input, parameters, visible, visibleWrites, visibleUpdates, kind, scope, facts);
            namespace = moon.clientProgramCheckSourceSelectorNamespace(facts.range,
              facts.namespace, facts.revision, context, original.revision);
          }
        } catch (cause) {
          if (signal?.aborted) throw cause;
          // Insufficient metadata or current authorization cannot prove absence.
        } finally {
          gate?.close();
        }
      }
      const visiblePublication = JSON.stringify({environmentCid, aliases: visible,
        ...(visibleUpdates.length === 0 ? {} : {updateTargets: visibleUpdates}),
        ...(visibleWrites.length === 0 ? {} : {tableWrites: visibleWrites})});
      const wire = projectOriginal === undefined
        ? moon.clientProgramCheckProgram(document, environment, visiblePublication, supplied,
          context, original.revision, bindings?.revision, correlationRef, scope, namespace)
        : projectOriginal(Object.freeze([visiblePublication, context, 'program',
          original.revision, original.byte_length, undefined, 0,
          bindings?.revision, bindings?.byte_length ?? 0, correlationRef, namespace, undefined, supplied]));
      if (projectOriginal !== undefined && wire === undefined) return undefined;
      if (projectOriginal !== undefined && typeof wire !== 'string') throw new TypeError('InvalidOriginalCheckObservation');
      const outcome = JSON.parse(wire);
      if (validBoundOutcome(outcome, context, scope, [original, ...(bindings ? [bindings] : [])])) return outcome;
      if (projectOriginal !== undefined) throw new TypeError('InvalidOriginalCheckObservation');
      return failed('check_internal', correlationRef);
    }
    const declarations = input.parameterDeclarations === undefined
      ? undefined : JSON.stringify(input.parameterDeclarations);
    const supplied = parameters === null ? undefined :
      JSON.stringify(parameters);
    const original = documentBinding('source', 'text', input.text);
    const declared = declarations === undefined ? undefined
      : documentBinding('parameter_declarations', 'structured', declarations);
    const bindings = supplied === undefined ? undefined : documentBinding('parameters', 'structured', supplied);
    let namespace;
    if (namespaceAuthorizationFor !== undefined) {
      // Only original publication/observation custody can reach the common
      // projection. Neither an SDK response nor client JSON supplies this fact.
      const binding = Object.freeze({principalId, contextCid: `sha256:${context.slice(4)}`,
        inputs: Object.freeze([original, ...(declared ? [declared] : []), ...(bindings ? [bindings] : [])]
          .map(value => Object.freeze({...value})))});
      let gate;
      try {
        gate = await namespaceAuthorizationFor({principalId, signal});
        const observation = await observeSourceAliasNamespace(publication, gate, binding, {signal});
        const facts = sourceAliasNamespaceObservationFacts(publication, observation, binding);
        if (facts !== undefined) {
          context = contextRef(principalId, input, parameters, visible, visibleWrites, visibleUpdates, kind, scope, facts);
          namespace = moon.clientProgramCheckSourceNamespace(environment,
            JSON.stringify({environmentCid, aliases: facts.aliases}),
            facts.namespace, facts.revision, context, original.revision);
        }
      } catch (cause) {
        if (signal?.aborted) throw cause;
        // Unavailable metadata/authority is not a proven authoring violation.
      } finally {
        gate?.close();
      }
    }
    const visiblePublication = JSON.stringify({environmentCid, aliases: visible,
      ...(visibleUpdates.length === 0 ? {} : {updateTargets: visibleUpdates}),
      ...(visibleWrites.length === 0 ? {} : {tableWrites: visibleWrites})});
    const wire = projectOriginal === undefined
      ? moon.clientProgramCheckSource(input.text, input.format, environment,
        visiblePublication, declarations, supplied, context, original.revision,
        declared?.revision, bindings?.revision, correlationRef, scope, namespace)
      : projectOriginal(Object.freeze([visiblePublication, context, 'text',
        original.revision, original.byte_length, declared?.revision,
        declared?.byte_length ?? 0, bindings?.revision, bindings?.byte_length ?? 0,
        correlationRef, undefined, namespace, supplied])); // Query-alias and nominal Source selector namespaces stay distinct.
    if (projectOriginal !== undefined && wire === undefined) return undefined;
    if (projectOriginal !== undefined && typeof wire !== 'string') throw new TypeError('InvalidOriginalCheckObservation');
    const outcome = JSON.parse(wire);
    if (validBoundOutcome(outcome, context, scope,
      [original, ...(declared ? [declared] : []), ...(bindings ? [bindings] : [])])) return outcome;
    if (projectOriginal !== undefined) throw new TypeError('InvalidOriginalCheckObservation');
    return failed('check_internal', correlationRef);
  };
  // The ingress's existing connection authorization owner determines whether
  // any report binding can be disclosed. This projection touches neither the
  // authored input nor Source decisions nor the checking environment.
  Object.defineProperty(check, 'unavailable', {value: () =>
    JSON.parse(moon.clientProgramCheckUnavailable(`corr:${randomBytes(16).toString('hex')}`))});
  // Private fixed Host path: share this same installation's fresh audience,
  // namespace and input bindings, while the retained Request supplies the
  // original typed outcome. The public check still uses its existing checker.
  Object.defineProperty(check, 'projectOriginal', {value: (request, project) => {
    if (request.scope !== 'bound_input' || typeof project !== 'function') {
      throw new TypeError('InvalidOriginalCheckObservation');
    }
    return check(request, project);
  }});
  return Object.freeze(check);
}

// Both entrances validate the existing common projection before serialization.
// A missing or corrupt producer is a Host protocol failure, never a report.
export async function projectClientCheckUnavailable(check) {
  const outcome = typeof check?.unavailable === 'function' ? await check.unavailable() : undefined;
  if (!validCheckOutcome(outcome) || outcome.outcome !== 'unavailable') {
    const error = new Error('InvalidClientHostCheckOutcome');
    error.code = 'InvalidClientHostCheckOutcome';
    throw error;
  }
  return outcome;
}
