// Public `check` of authored source for one audience. The Host decides which
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

const version = 'actql-check-outcome/0.1';
// Revisions bound into every context reference. A change to what an audience
// may see, or to the projection, must never reuse an earlier reference.
const disclosurePolicy = 'actql-check-disclosure/0.1';
const contextVersion = 'actql-check-context/0.1';
const scope = 'bound_input';

const failed = (code, correlation_ref) => Object.freeze({outcome: 'failed', correlation_ref,
  problem: Object.freeze({code}), reason_schema_cid: checkReasonSchemaCid,
  outcome_schema_cid: checkOutcomeSchemaCid, version});

export function installNodeClientCheck({moon, environment, publication,
  sourceAccesses = [], contextKey = randomBytes(32)}) {
  if (moon === null || typeof moon !== 'object' ||
      typeof moon.clientProgramCheckSource !== 'function' ||
      typeof moon.clientProgramCheckUnavailable !== 'function' ||
      typeof moon.clientProgramCheckCompilerIdentity !== 'function' ||
      typeof moon.clientProgramCheckContextIdentity !== 'function' ||
      typeof moon.clientProgramCheckingEnvironmentCid !== 'function' ||
      environment === undefined ||
      !(contextKey instanceof Uint8Array) || contextKey.byteLength !== 32 ||
      !Array.isArray(sourceAccesses) || sourceAccesses.some(access =>
        typeof access?.authorization?.authorize !== 'function')) {
    throw new TypeError('InvalidClientCheckInstallation');
  }
  const environmentCid = moon.clientProgramCheckingEnvironmentCid(environment);
  const compiler = JSON.parse(moon.clientProgramCheckCompilerIdentity());
  const checkingContext = JSON.parse(moon.clientProgramCheckContextIdentity(environment));
  const aliases = publication?.aliases ?? [];
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

  // Keyed by this Host over everything the verdict is about: the audience
  // and its disclosure policy, the exact source and format, the scope, the
  // compiler and public checking selections, the visible names and supplied
  // bindings. Equal requests give an equal reference here; the reference is
  // not a public hash of supplied values.
  const contextRef = (principalId, input, parameters, visible) => {
    const bound = {version: contextVersion, audience: principalId,
      disclosure_policy: disclosurePolicy, projection: version, scope,
      compiler, reason_schema_cid: checkReasonSchemaCid,
      checking_context: checkingContext, visible_aliases: visible};
    let preimage;
    try {
      preimage = canonicalJson({...bound,
        source: {format: input.format, text: input.text},
        parameter_declarations: input.parameterDeclarations ?? null,
        parameters: parameters ?? null});
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

  const check = async ({principalId, input, parameters, signal}) => {
    // One opaque reference for this reporting attempt, independent of source,
    // context, authorization and the presence of any protected Source.
    const correlationRef = `corr:${randomBytes(16).toString('hex')}`;
    signal?.throwIfAborted();
    const visible = await visibleAliases(signal);
    signal?.throwIfAborted();
    const declarations = input.parameterDeclarations === undefined
      ? undefined : JSON.stringify(input.parameterDeclarations);
    const supplied = parameters === null ? undefined :
      JSON.stringify(parameters);
    const outcome = JSON.parse(moon.clientProgramCheckSource(input.text,
      input.format, environment,
      JSON.stringify({environmentCid, aliases: visible}),
      declarations, supplied,
      contextRef(principalId, input, parameters, visible),
      revision('source', input.text),
      declarations === undefined ? undefined : revision('parameter_declarations', declarations),
      supplied === undefined ? undefined : revision('parameters', supplied), correlationRef));
    return validCheckOutcome(outcome) ? outcome : failed('check_internal', correlationRef);
  };
  // The ingress's existing connection authorization owner determines whether
  // any report binding can be disclosed. This projection touches neither the
  // authored input nor Source decisions nor the checking environment.
  Object.defineProperty(check, 'unavailable', {value: () =>
    JSON.parse(moon.clientProgramCheckUnavailable(`corr:${randomBytes(16).toString('hex')}`))});
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
