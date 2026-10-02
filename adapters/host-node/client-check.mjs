// Public `check` of authored source for one audience. The Host decides which
// installed query names the audience may see with the source's own read
// authorization; absent, denied and undecided names are all left out before
// MoonBit checks anything, so the private distinction never reaches the
// outcome. MoonBit owns checking and the one actql-check-outcome/0.1
// projection.
import {createHmac, randomBytes} from 'node:crypto';
import {validCheckOutcome} from '../../packages/client-wire/index.mjs';
// The common value encoding: String values stay exact (CR, LF and composed
// or decomposed spellings differ); only object member names are canonical.
import {canonicalJson} from '../../packages/sdk/host-port.mjs';

const version = 'actql-check-outcome/0.1';
// Revisions bound into every context reference. A change to what an audience
// may see, or to the projection, must never reuse an earlier reference.
const disclosurePolicy = 'actql-check-disclosure/0.1';
const contextVersion = 'actql-check-context/0.1';
const scope = 'bound_input';

const failed = code => Object.freeze({outcome: 'failed',
  problem: Object.freeze({code}), version});

export function installNodeClientCheck({moon, environment, publication,
  sourceAccess, contextKey = randomBytes(32)}) {
  if (moon === null || typeof moon !== 'object' ||
      typeof moon.clientProgramCheckSource !== 'function' ||
      typeof moon.clientProgramCheckUnavailable !== 'function' ||
      typeof moon.clientProgramCheckCompilerIdentity !== 'function' ||
      typeof moon.clientProgramCheckingEnvironmentCid !== 'function' ||
      environment === undefined ||
      !(contextKey instanceof Uint8Array) || contextKey.byteLength !== 32 ||
      sourceAccess !== undefined &&
        typeof sourceAccess?.authorization?.authorize !== 'function') {
    throw new TypeError('InvalidClientCheckInstallation');
  }
  const environmentCid = moon.clientProgramCheckingEnvironmentCid(environment);
  const compiler = JSON.parse(moon.clientProgramCheckCompilerIdentity());
  const aliases = publication?.aliases ?? [];
  if (publication !== undefined &&
      publication.environmentCid !== environmentCid) {
    throw new TypeError('InvalidClientCheckInstallation');
  }
  const key = Buffer.from(contextKey);

  const unavailable = () => {
    const correlationRef = `corr:${randomBytes(16).toString('hex')}`;
    return JSON.parse(moon.clientProgramCheckUnavailable(correlationRef));
  };

  // The audience-visible names, or undefined when the Host cannot decide
  // visibility at all. The installed source's read tuple is decided once per
  // check, whatever names are published or mentioned, so neither the outcome
  // kind nor the work done depends on them. Only a dispatch decision shows the
  // source's names. A deny, a held or failed decision, or a name whose source
  // has no single installed read tuple hides it exactly as an absent name is
  // hidden, so one undecided source never withholds the rest of the check.
  const readTuple = sourceAccess !== undefined &&
    typeof sourceAccess.sourceRef === 'string' &&
    typeof sourceAccess.resource === 'string';
  const visibleAliases = async signal => {
    if (!readTuple) return [];
    let decision;
    try {
      decision = await sourceAccess.authorization.authorize('acquisition', {
        connection: sourceAccess.connection,
        resource: sourceAccess.resource, operation: 'read',
      }, {subjectCid: environmentCid, signal});
    } catch (cause) {
      // The decision owner itself is unusable (for example closed): the
      // audience's context cannot be established for any name.
      if (signal?.aborted) throw cause;
      return undefined;
    }
    if (decision?.action !== 'dispatch') return [];
    return aliases.filter(alias => alias.sourceRef === sourceAccess.sourceRef)
      .sort((left, right) =>
        left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
  };

  // Keyed by this Host over everything the verdict is about: the audience
  // and its disclosure policy, the exact source and format, the scope, the
  // compiler and checking environment, the visible names and the supplied
  // bindings. Equal requests give an equal reference here; the reference is
  // not a public hash of supplied values.
  const contextRef = (principalId, input, parameters, visible) => {
    const bound = {version: contextVersion, audience: principalId,
      disclosure_policy: disclosurePolicy, projection: version, scope,
      compiler, environment_cid: environmentCid, visible_aliases: visible};
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

  return async ({principalId, input, parameters, signal}) => {
    signal?.throwIfAborted();
    const visible = await visibleAliases(signal);
    signal?.throwIfAborted();
    if (visible === undefined) return unavailable();
    const declarations = input.parameterDeclarations === undefined
      ? undefined : JSON.stringify(input.parameterDeclarations);
    const supplied = parameters === null ? undefined :
      JSON.stringify(parameters);
    const outcome = JSON.parse(moon.clientProgramCheckSource(input.text,
      input.format, environment,
      JSON.stringify({environmentCid, aliases: visible}),
      declarations, supplied,
      contextRef(principalId, input, parameters, visible)));
    return validCheckOutcome(outcome) ? outcome : failed('check_internal');
  };
}
