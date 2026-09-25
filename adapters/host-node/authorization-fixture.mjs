// Test and example installation helpers for the execution-authorization gate.
// Every grant here is an explicit admitted account configuration; nothing is
// inferred from a missing configuration.
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

// Durable deferral over the real SQLite Checkpoint journal. Reviewer
// authentication/attestation ports are fixtures: this helper exercises the
// persist-before-wait path, not Resolution signing.
export async function sqliteDeferral(root, {now = () => Date.now()} = {}) {
  const {openSqliteCheckpointJournal, loadCheckpointRuntime} = await import(
    './sqlite-checkpoint-journal.mjs');
  const journal = openSqliteCheckpointJournal(root, {
    runtime: await loadCheckpointRuntime(),
    authorizeResolution: () => { throw new Error('FixtureResolutionUnsupported'); },
    attestResolution: () => { throw new Error('FixtureResolutionUnsupported'); },
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
          required_artifact: {artifact_cid: view.subject.subject_cid},
          review_projection_cid: fixtureCid('4'),
          human_summary: `${view.boundary} ${view.tuple.connection}`,
          created_at: created,
          expires_at: expires,
        },
      };
    },
  });
}
