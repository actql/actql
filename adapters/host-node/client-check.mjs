// Public `check` of authored source for one audience. The Host decides which
// installed query names the audience may see with the source's own read
// authorization; absent and denied names are both left out before MoonBit
// checks anything, so the private distinction never reaches the outcome.
// MoonBit owns checking and the one actql-check-outcome/0.1 projection.
import {createHmac, randomBytes} from 'node:crypto';
import {validCheckOutcome} from '../../packages/client-wire/index.mjs';
import {canonicalJson} from './local-account-config.mjs';

const version = 'actql-check-outcome/0.1';
// Revisions bound into every context reference. A change to what an audience
// may see, or to the projection, must never reuse an earlier reference.
const disclosurePolicy = 'actql-check-disclosure/0.1';
const contextVersion = 'actql-check-context/0.1';

const failed = code => Object.freeze({outcome: 'failed',
  problem: Object.freeze({code}), version});

export function installNodeClientCheck({moon, environment, publication,
  sourceAccess, contextKey = randomBytes(32)}) {
  if (moon === null || typeof moon !== 'object' ||
      typeof moon.clientProgramCheckSource !== 'function' ||
      typeof moon.clientProgramCheckUnavailable !== 'function' ||
      typeof moon.clientProgramCheckingEnvironmentCid !== 'function' ||
      environment === undefined ||
      !(contextKey instanceof Uint8Array) || contextKey.byteLength !== 32 ||
      sourceAccess !== undefined &&
        typeof sourceAccess?.authorization?.authorize !== 'function') {
    throw new TypeError('InvalidClientCheckInstallation');
  }
  const environmentCid = moon.clientProgramCheckingEnvironmentCid(environment);
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

  // The audience-visible names, or undefined when visibility cannot be
  // decided safely. Every published name is decided, whether or not the
  // checked source mentions it, so the outcome kind does not depend on it.
  const visibleAliases = async signal => {
    const visible = [];
    for (const alias of aliases) {
      // Only a name whose source has one installed read tuple is decided
      // here; any other name makes the context unavailable, never visible.
      if (sourceAccess === undefined ||
          typeof sourceAccess.sourceRef !== 'string' ||
          typeof sourceAccess.resource !== 'string' ||
          alias.sourceRef !== sourceAccess.sourceRef) {
        return undefined;
      }
      let decision;
      try {
        decision = await sourceAccess.authorization.authorize('acquisition', {
          connection: sourceAccess.connection,
          resource: sourceAccess.resource, operation: 'read',
        }, {subjectCid: alias.sourceViewContractCid, signal});
      } catch (cause) {
        if (signal?.aborted) throw cause;
        return undefined;
      }
      if (decision.action === 'dispatch') visible.push(alias);
      else if (decision.action !== 'deny') return undefined;
    }
    return visible.sort((left, right) =>
      left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
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
    // Keyed by this Host: equal disclosable context gives an equal reference
    // here, and the reference is not a public hash of supplied values.
    const contextRef = `ctx:${createHmac('sha256', key).update(canonicalJson({
      version: contextVersion, audience: principalId,
      disclosure_policy: disclosurePolicy, environment_cid: environmentCid,
      visible_aliases: visible, format: input.format,
      parameter_declarations: input.parameterDeclarations ?? null,
      parameters: parameters ?? null, projection: version,
    })).digest('hex')}`;
    const outcome = JSON.parse(moon.clientProgramCheckSource(input.text,
      input.format, environment,
      JSON.stringify({environmentCid, aliases: visible}),
      declarations, supplied, contextRef));
    return validCheckOutcome(outcome) ? outcome : failed('check_internal');
  };
}
