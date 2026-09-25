// Test and example installation helpers for the execution-authorization gate.
// Every grant here is an explicit admitted account configuration; nothing is
// inferred from a missing configuration.
import {createHash, generateKeyPairSync, sign, verify} from 'node:crypto';
import {createNodeAuthorizationGate} from './authorization.mjs';

export const FIXTURE_CONFIGURATION_CID = `sha256:${'c'.repeat(64)}`;
export const FIXTURE_CONTEXT = Object.freeze({
  principal: 'local-user',
  contextCid: `sha256:${'d'.repeat(64)}`,
});

const every = Object.freeze({all: true});
const selector = value => value === undefined ? every
  : Array.isArray(value) ? {any_of: [...value]} : {any_of: [value]};

// One entry over principal × connection × resource × operation. Omitted
// dimensions are all-target selectors.
export function accountEntry(entryId, outcome, {
  principal, connection, resource, operation, exclusions = [],
} = {}) {
  return {
    entry_id: entryId,
    outcome,
    principal: selector(principal),
    connection: selector(connection),
    resource: selector(resource),
    operation: selector(operation),
    exclusions: exclusions.map(value => ({
      principal: selector(value.principal),
      connection: selector(value.connection),
      resource: selector(value.resource),
      operation: selector(value.operation),
    })),
  };
}

export function accountConfiguration(entries, accountId = 'local-account') {
  return JSON.stringify({
    version: 'actql-execution-account-config/0.1',
    account_id: accountId,
    entries,
  });
}

export function fixtureAuthorization(entries, options = {}) {
  return createNodeAuthorizationGate({
    configuration: accountConfiguration(entries),
    configurationCid: FIXTURE_CONFIGURATION_CID,
    context: FIXTURE_CONTEXT,
    ...options,
  });
}

// Explicit Local profile used by tests and examples that exercise execution,
// not authorization: allow every tuple for this account.
export function allowAllAuthorization(options = {}) {
  return fixtureAuthorization([accountEntry('allow-all', 'allow')], options);
}

export const fixtureSourceAccess = Object.freeze({
  authorization: await allowAllAuthorization(),
});

const fixtureCid = digit => `sha256:${digit.repeat(64)}`;

// Test-side canonical JSON for the ASCII fixture artifacts below: sorted
// keys, no whitespace (the Resolution/approval CIDs of Run#resolution-admission).
const canonical = value => {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
};
const cidOf = value =>
  `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

// Durable deferral over the real SQLite Checkpoint journal. The reviewer and
// Host attestation keys are fixture Ed25519 keys held here; `answer` signs one
// Resolution as the fixture reviewer and commits it through the journal's
// real admission (`submitResolution`).
export async function sqliteDeferral(root, {now = () => Date.now()} = {}) {
  const {openSqliteCheckpointJournal, loadCheckpointRuntime} = await import(
    './sqlite-checkpoint-journal.mjs');
  const reviewer = generateKeyPairSync('ed25519');
  const host = generateKeyPairSync('ed25519');
  const journal = openSqliteCheckpointJournal(root, {
    runtime: await loadCheckpointRuntime(),
    authorizeResolution({resolutionWire, proofPreimage}) {
      const resolution = JSON.parse(resolutionWire);
      if (resolution.proof?.key_id !== 'reviewer-key' ||
          !verify(null, Buffer.from(proofPreimage, 'utf8'), reviewer.publicKey,
            Buffer.from(resolution.proof.signature, 'base64'))) {
        throw new Error('FixtureResolutionUntrusted');
      }
      return {keyId: 'reviewer-key', reviewerId: 'reviewer',
        authorityContextCid: fixtureCid('5'), policyCid: fixtureCid('6'),
        verifiedPreimage: proofPreimage};
    },
    attestResolution: preimage => ({
      hostKeyId: 'host-key',
      signature: sign(null, Buffer.from(preimage, 'utf8'), host.privateKey)
        .toString('base64'),
    }),
    now,
  });
  let sequence = 0;
  return Object.freeze({
    journal,
    authorities: [{keyId: 'reviewer-key', reviewerId: 'reviewer'}],
    binding: {
      authorizationContextCid: FIXTURE_CONTEXT.contextCid,
      environmentBindingCid: fixtureCid('e'),
    },
    // Commit the reviewer's `approved` or `rejected` Resolution of one
    // persisted Checkpoint. Returns the journal's committed result.
    answer(checkpointCid, decision) {
      const checkpoint = journal.inspect(checkpointCid);
      if (checkpoint === undefined) throw new Error('CheckpointNotFound');
      const at = new Date(now()).toISOString();
      let evidence;
      if (decision === 'approved') {
        const approval = {
          version: 'actql-run-scope-approval/0.1',
          prepared_invocation_cid: checkpoint.requiredArtifact.cid,
          review_projection_cid: checkpoint.reviewProjectionCid,
          claim: 'invocation_scope_approved',
          approver: 'reviewer',
          approved_at: at,
          expires_at: checkpoint.expiresAt,
          proof: {scheme: 'ed25519-v1', key_id: 'reviewer-key',
            signature: 'c2lnbmF0dXJl'},
        };
        approval.run_scope_approval_cid = cidOf(approval);
        evidence = {
          version: 'actql-checkpoint-approval-evidence/0.1',
          kind: checkpoint.kind,
          checkpoint_cid: checkpoint.checkpointCid,
          review_projection_cid: checkpoint.reviewProjectionCid,
          compatibility_approval: approval,
        };
      }
      const body = {
        version: 'actql-checkpoint-resolution/0.1',
        resolution_id: `resolution-${checkpoint.checkpointId}-${decision}`,
        checkpoint_id: checkpoint.checkpointId,
        checkpoint_cid: checkpoint.checkpointCid,
        // A preparation Checkpoint precedes its Run.
        ...(checkpoint.prepareAttemptId !== null
          ? {prepare_attempt_id: checkpoint.prepareAttemptId}
          : {run_id: checkpoint.runId, run_definition_cid: fixtureCid('1')}),
        decision,
        actor: 'reviewer',
        decided_at: at,
        required_artifact_cid: checkpoint.requiredArtifact.cid,
        review_projection_cid: checkpoint.reviewProjectionCid,
        ...(evidence ? {approval_evidence_cid: cidOf(evidence)} : {}),
      };
      body.proof = {
        scheme: 'ed25519-v1',
        key_id: 'reviewer-key',
        signature: sign(null, Buffer.from(cidOf(body), 'utf8'),
          reviewer.privateKey).toString('base64'),
      };
      body.resolution_cid = cidOf(body);
      return journal.submitResolution({
        checkpointCid,
        resolutionWire: JSON.stringify(body),
        approvalEvidenceWire: evidence ? JSON.stringify(evidence) : '',
      });
    },
    describe(view) {
      sequence += 1;
      const runId = `run-${sequence}`;
      const created = new Date(now()).toISOString();
      const expires = new Date(now() + 86_400_000).toISOString();
      return {
        priorStatus: 'running',
        declaredResults: ['result'],
        body: {
          checkpoint_id: `authorization-${sequence}`,
          run_id: runId,
          run_definition_cid: fixtureCid('1'),
          continuation_state_cid: fixtureCid('2'),
          subject: {kind: 'run_unit', run_id: runId, unit_id: 'unit-1',
            continuation: 'resume_unit'},
          review_projection_cid: fixtureCid('4'),
          human_summary: `${view.boundary} ${view.tuple.connection}`,
          created_at: created,
          expires_at: expires,
        },
      };
    },
  });
}
