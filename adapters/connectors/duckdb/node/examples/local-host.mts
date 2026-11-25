// Local Host for the example application with durable delegated decisions.
//
// This is Reference/Local Host code for the bounded example, not a general
// Program runner. It installs the operator's explicit account configuration,
// the SQLite Checkpoint journal and Host-trusted reviewer keys, and realizes
// the Local delegate default: without an application decision function a
// delegated preparation or acquisition waits in a durable `prepare_attempt`
// Checkpoint (the journal plus `approve`/`reject` are the later answer path).
//
// Preparation is two-phase. The account outcome and any immediate Host answer
// are decided on the invocation request before any path is read, so a denial
// reads and captures nothing. Only when a delegated preparation is deferred
// does the Host capture the operator-supplied Program, Environment and
// Parameter files as immutable content-addressed private evidence
// (caller-supplied input, not a Connector read), record the exact prepared
// invocation and seal the `run_scope` Checkpoint on it; its decision-subject
// binding still names the request. Private evidence is held encrypted through
// the Host storage port (`local-continuation-evidence.mjs`) and retired only
// when its continuation has no remaining need. No source (provider) I/O
// happens before the Checkpoint: both preparation and acquisition
// Checkpoints precede capture of source data, so a resumed continuation reads
// the source once, after its approval. Resumption claims the fenced resume
// intent, revalidates the bound authorization context and environment, reuses
// the captured bytes and the approved decision subjects, creates the Run
// directly in `running` and runs the same continuation.
import {randomUUID, sign, verify, createPrivateKey, createPublicKey,
  generateKeyPairSync} from 'node:crypto';
import {mkdir, readFile, realpath, stat, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join, resolve} from 'node:path';
import {runExample} from './physical-strategy.mjs';
import {openSqliteCheckpointJournal} from
  '../../../../host-node/sqlite-checkpoint-journal.mjs';
import {loadCheckpointRuntime} from '../../../../host-node/checkpoint-runtime.mjs';
import {
  bytesCid,
  canonicalJson,
  contentCid,
  createLocalAuthorizationGate,
} from '../../../../host-node/local-account-config.mjs';
import {localHostAccountContext} from './local-account-context.mjs';
import {ExecutionAuthorizationError, admitResumedDispatch, decisionSubjectCid}
  from '../../../../host-common/authorization-gate.mjs';
import {runtimeCore} from '../../../../host-common/runtime-core.mjs';
import {
  createPrivateEvidenceKey,
  loadPrivateEvidenceKey,
  openContinuationEvidence,
} from '../../../../host-node/local-continuation-evidence.mjs';

import type {KeyObject} from 'node:crypto';
import type {snapshotProcessUsage} from '../../../../host-node/process-accounting.mjs';

type AuthorizationOptions = NonNullable<Parameters<typeof createLocalAuthorizationGate>[0]>;
type Gate = Awaited<ReturnType<typeof createLocalAuthorizationGate>>;
type GateDecision = Awaited<ReturnType<Gate['authorize']>>;
type Deferral = NonNullable<AuthorizationOptions['deferral']>;
type Decide = NonNullable<AuthorizationOptions['decide']>;
type ResumeDecide = (view: Parameters<Decide>[0]) => ReturnType<Decide>;
type Subject = Parameters<Decide>[0]['subject'];
type SubjectFacts = Readonly<Partial<Subject>>;
type ApprovedSubject = Readonly<{subject: SubjectFacts; actor?: string;
  invocation_cid?: string; checkpoint_cid?: string}>;
type Journal = ReturnType<typeof openSqliteCheckpointJournal>;
type CheckpointView = NonNullable<ReturnType<Journal['inspect']>>;
type ResolutionSubmission = Parameters<Journal['submitResolution']>[0];
type ResumeOptions = NonNullable<Parameters<typeof admitResumedDispatch>[2]>;
type Admission = Extract<ReturnType<typeof admitResumedDispatch>, {admission: object}>['admission'];
type ExampleOptions = Parameters<typeof runExample>[0];
type ExampleResult = Awaited<ReturnType<typeof runExample>>;
type InvocationOptions = Readonly<{
  database?: string; environment?: string; environmentCid?: string; program?: string;
  parameters?: string; schema?: string; table?: string; nativeMilliseconds?: string; resident?: boolean;
}>;
type CapturedTexts = NonNullable<NonNullable<ExampleOptions['invocation']>['texts']>;
type TextCapture = {current: CapturedTexts | undefined};
type ConfigurationDocument = Readonly<{
  state_directory?: string; account_config?: string | null; principal?: string;
  reviewers?: readonly Readonly<{key_id: string; reviewer_id: string; public_key: string}>[];
  host_key?: Readonly<{key_id: string; private_key: string}>;
  checkpoint_ttl_ms?: number;
}>;
type Installation = Readonly<{directory: string; accountConfig?: string; reviewer?: string; principal?: string}>;
type ErrorFields = Readonly<{code?: string; runtimeCode?: string;
  priorAdmission?: Readonly<{generation?: number}>}>;
type ApprovalDecision = 'approved' | 'rejected';
type SignerDocument = Readonly<{key_id: string; reviewer_id: string; private_key_pem: string}>;
type Signature = Readonly<{scheme: string; key_id: string; signature: string}>;
type ParsedWire<Value> = Value extends bigint ? string :
  Value extends object ? {[Key in keyof Value]: ParsedWire<Value[Key]>} : Value;

const storeRuntimeUrl = new URL(
  '../../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url);

const DECLARED_RESULTS = Object.freeze(['result']);
const MAX_INPUT_BYTES = 1_000_000;
const SUBJECT_FIELDS = Object.freeze([
  'account_id', 'configuration_cid', 'entry_id', 'principal', 'connection',
  'resource', 'operation', 'boundary', 'subject_cid', 'context_cid',
] as const);
const IDENTIFIER = /^[A-Za-z0-9._:-]{1,128}$/;

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const without = (value: Readonly<Record<string, unknown>>, ...keys: string[]) => Object.fromEntries(
  Object.entries(value).filter(([key]) => !keys.includes(key)));
const plain = <Value,>(value: Value): ParsedWire<Value> => JSON.parse(JSON.stringify(value, (_, item) =>
  typeof item === 'bigint' ? item.toString() : item));

// Host configuration. Relative paths resolve against the configuration file.
export async function loadHostConfig(path: string) {
  if (typeof path !== 'string' || path.length === 0) fail('HostConfigRequired');
  const file = resolve(path);
  const base = dirname(file);
  const at = (value: string | null | undefined) => value === undefined || value === null ? undefined
    : isAbsolute(value) ? value : resolve(base, value);
  let raw: ConfigurationDocument;
  try { raw = JSON.parse(await readFile(file, 'utf8')); }
  catch (error) { fail('InvalidHostConfig', error); }
  if (raw === null || typeof raw !== 'object' ||
      typeof raw.state_directory !== 'string' ||
      !Array.isArray(raw.reviewers) || raw.reviewers.length === 0 ||
      typeof raw.host_key?.key_id !== 'string' ||
      typeof raw.host_key?.private_key !== 'string') {
    fail('InvalidHostConfig');
  }
  const reviewers = await Promise.all(raw.reviewers.map(async reviewer => {
    if (!IDENTIFIER.test(reviewer?.key_id ?? '') ||
        !IDENTIFIER.test(reviewer?.reviewer_id ?? '') ||
        typeof reviewer?.public_key !== 'string') {
      fail('InvalidHostConfig');
    }
    return Object.freeze({
      keyId: reviewer.key_id,
      reviewerId: reviewer.reviewer_id,
      publicKey: createPublicKey(await readFile(at(reviewer.public_key)!)),
    });
  }));
  if (new Set(reviewers.map(item => item.keyId)).size !== reviewers.length) {
    fail('InvalidHostConfig');
  }
  const ttl = raw.checkpoint_ttl_ms ?? 86_400_000;
  if (!Number.isSafeInteger(ttl) || ttl < 1000) fail('InvalidHostConfig');
  return Object.freeze({
    path: file,
    stateDirectory: at(raw.state_directory)!,
    // Absent means no configuration: every protected boundary is denied.
    accountConfig: at(raw.account_config),
    principal: raw.principal ?? 'local-operator',
    reviewers: Object.freeze(reviewers),
    hostKey: Object.freeze({
      keyId: raw.host_key.key_id,
      privateKey: createPrivateKey(await readFile(at(raw.host_key.private_key)!)),
    }),
    checkpointTtlMs: ttl,
  });
}

// Create a minimal Local Host installation: Host attestation key, one
// reviewer key pair and signer file, the private-evidence key in the state
// directory and the Host configuration. The account configuration is
// referenced, never generated here.
export async function initializeLocalHost({directory, accountConfig,
  reviewer = 'reviewer', principal = 'local-operator'}: Installation) {
  if (!IDENTIFIER.test(reviewer)) fail('InvalidReviewerId');
  const root = resolve(directory);
  await mkdir(root, {recursive: true, mode: 0o700});
  const host = generateKeyPairSync('ed25519');
  const signer = generateKeyPairSync('ed25519');
  const pem = (key: KeyObject) => key.export({type: 'pkcs8', format: 'pem'});
  const files = {
    config: join(root, 'host.json'),
    hostKey: join(root, 'host-key.pem'),
    reviewerPublicKey: join(root, `${reviewer}.pub.pem`),
    signer: join(root, `${reviewer}.signer.json`),
    privateEvidenceKey: undefined as string | undefined,
  };
  const create = (path: string, text: string | Buffer) => writeFile(path, text, {flag: 'wx', mode: 0o600});
  await create(files.hostKey, pem(host.privateKey));
  await create(files.reviewerPublicKey,
    signer.publicKey.export({type: 'spki', format: 'pem'}));
  await create(files.signer, JSON.stringify({key_id: `${reviewer}-key`,
    reviewer_id: reviewer, private_key_pem: pem(signer.privateKey)}, null, 2));
  await create(files.config, JSON.stringify({
    state_directory: 'state',
    ...(accountConfig === undefined ? {} : {account_config: resolve(accountConfig)}),
    principal,
    reviewers: [{key_id: `${reviewer}-key`, reviewer_id: reviewer,
      public_key: `${reviewer}.pub.pem`}],
    host_key: {key_id: 'host-key', private_key: 'host-key.pem'},
  }, null, 2));
  files.privateEvidenceKey = await createPrivateEvidenceKey(join(root, 'state'));
  return Object.freeze(files);
}

async function boundedBytes(path: string) {
  if ((await stat(path)).size > MAX_INPUT_BYTES) fail('InputTooLarge');
  const bytes = await readFile(path);
  if (bytes.length > MAX_INPUT_BYTES) fail('InputTooLarge');
  return bytes;
}

const sameSubject = (left: SubjectFacts | undefined, right: SubjectFacts | undefined) =>
  SUBJECT_FIELDS.every(name => left?.[name] === right?.[name]);

// Local Host delegated-decision policy for an approved preparation: a
// verified run-scope approval of prepared invocation X answers exactly the
// acquisition of X's declared source in the same prepare attempt, under the
// same account entry, configuration, context and tuple. It covers no other
// boundary, invocation, tuple or Checkpoint.
function approvedBy(item: ApprovedSubject, subject: Subject) {
  if (sameSubject(item.subject, subject)) return true;
  return item.subject.boundary === 'preparation' &&
    subject.boundary === 'acquisition' &&
    subject.subject_cid === item.invocation_cid &&
    SUBJECT_FIELDS.every(name => name === 'boundary' || name === 'subject_cid' ||
      item.subject[name] === subject[name]);
}

// `coverage(item, subject)` is the Host's delegated-decision coverage policy
// for approved subjects (default `approvedBy`); a Host that answers only the
// exact approved subjects passes `exactApprovedSubject`.
export const exactApprovedSubject = (item: ApprovedSubject, subject: Subject) =>
  sameSubject(item.subject, subject);

export async function openLocalHost(configPath: string, {now = () => Date.now(),
  coverage = approvedBy}: Readonly<{now?: () => number; coverage?: typeof approvedBy}> = {}) {
  if (typeof coverage !== 'function') fail('InvalidApprovalCoverage');
  const config = await loadHostConfig(configPath);
  const state = config.stateDirectory;
  const reviewersByKey = new Map(config.reviewers.map(item => [item.keyId, item]));
  const authorities = config.reviewers.map(({keyId, reviewerId}) =>
    ({keyId, reviewerId}));
  const reviewerIds = config.reviewers.map(item => item.reviewerId);
  const runtime = await loadCheckpointRuntime();
  const privateKey = await loadPrivateEvidenceKey(state);
  const strategyRuntime: Parameters<typeof localHostAccountContext>[1] = await import(storeRuntimeUrl.href);

  // Current trusted context: the admitted configuration text/CID (if any),
  // the context CID and the bound authorization-context CID for resumption.
  const currentContext = () => localHostAccountContext(config, strategyRuntime);
  let context = await currentContext();

  const journal = openSqliteCheckpointJournal(join(state, 'journal'), {
    runtime,
    now,
    // This Host-owned principal/account context is fixed before any answer is
    // admitted; it is never inferred from a caller's approval evidence.
    expectedAuthorityScopeCid: context.context.contextCid,
    // Host authorization port: Host-trusted keys only; the Resolution and
    // its run-scope approval must be signed by the same trusted key.
    authorizeResolution({resolutionWire, approvalEvidenceWire, proofPreimage}) {
      const resolution = JSON.parse(resolutionWire);
      const trusted = reviewersByKey.get(resolution.proof?.key_id);
      if (trusted === undefined) fail('UntrustedReviewerKey');
      if (!verify(null, Buffer.from(proofPreimage, 'utf8'), trusted.publicKey,
        Buffer.from(resolution.proof.signature, 'base64'))) {
        fail('InvalidResolutionSignature');
      }
      if (approvalEvidenceWire !== '') {
        const approval = JSON.parse(approvalEvidenceWire).compatibility_approval;
        const unsigned = contentCid(without(approval, 'run_scope_approval_cid',
          'proof'));
        if (approval?.proof?.key_id !== trusted.keyId ||
            !verify(null, Buffer.from(unsigned, 'utf8'), trusted.publicKey,
              Buffer.from(approval.proof.signature ?? '', 'base64'))) {
          fail('InvalidApprovalSignature');
        }
      }
      return {
        keyId: trusted.keyId,
        reviewerId: trusted.reviewerId,
        authorityContextCid: context.authorizationContextCid,
        policyCid: context.configuration?.configurationCid ??
          contentCid({configuration: 'missing'}),
        verifiedPreimage: proofPreimage,
      };
    },
    attestResolution(preimage) {
      return {
        hostKeyId: config.hostKey.keyId,
        signature: sign(null, Buffer.from(preimage, 'utf8'),
          config.hostKey.privateKey).toString('base64'),
      };
    },
  });

  // Host storage port: captured inputs and Host records are encrypted
  // private evidence in the Local Store, held per continuation.
  const evidence = openContinuationEvidence({
    stateDirectory: state,
    isTerminalRunOutcome: journal.isTerminalRunOutcome,
    ...privateKey,
    contractControl: runtimeCore(strategyRuntime).publicationControl,
    preparation(prepareAttemptId) {
      const current = journal.getPreparation(prepareAttemptId);
      if (current === undefined) return undefined;
      return {status: current.status, runStatus: current.runId === null
        ? undefined : journal.getRunState(current.runId)?.status};
    },
  });

  async function environmentBinding(request: InvocationRequest) {
    let source = null;
    try { source = await realpath(request.database); } catch {}
    return contentCid({environment_cid: request.environment_cid, source,
      schema: request.schema, table: request.table});
  }

  function requestOf(options: InvocationOptions) {
    for (const key of ['database', 'environment', 'program', 'parameters',
      'environmentCid'] as const) {
      if (typeof options?.[key] !== 'string' || options[key]!.length === 0) {
        fail('InvalidInvocation', key);
      }
    }
    return Object.freeze({
      kind: 'local-example-invocation-request',
      database: resolve(options.database!),
      schema: options.schema ?? 'main',
      table: options.table ?? 'records',
      native_ms: options.nativeMilliseconds ?? '5',
      resident: options.resident === true,
      environment_cid: options.environmentCid!,
      program: resolve(options.program!),
      environment: resolve(options.environment!),
      parameters: resolve(options.parameters!),
      principal: config.principal,
    });
  }

  type InvocationRequest = ReturnType<typeof requestOf>;

  const invocationOf = (request: InvocationRequest, requestCid: string, texts: CapturedTexts) => ({
    kind: 'local-example-prepared-invocation',
    request,
    request_cid: requestCid,
    program_cid: bytesCid(Buffer.from(texts.programText, 'utf8')),
    environment_text_cid: bytesCid(Buffer.from(texts.environmentText, 'utf8')),
    parameters_cid: bytesCid(Buffer.from(texts.parameterText, 'utf8')),
  });

  // The private evidence of one prepared invocation: captured input bytes,
  // the request and the prepared invocation that binds them.
  const invocationEvidence = (request: InvocationRequest, read: CapturedTexts) => [
    ...[read.programText, read.environmentText, read.parameterText]
      .map(wire => ({name: 'captured_input', wire})),
    {name: 'invocation_request', wire: canonicalJson(request)},
  ];

  // Second phase of a deferred preparation: read the operator-supplied paths
  // once, capture them and seal the prepared invocation. Called by the gate
  // only on the defer path, after the request subject was decided. The
  // captured bytes are held by `describe`, before the Checkpoint commits.
  function sealerFor(request: InvocationRequest, requestCid: string, texts: TextCapture) {
    return async () => {
      const read = texts.current ?? {
        programText: (await boundedBytes(request.program)).toString('utf8'),
        environmentText: (await boundedBytes(request.environment)).toString('utf8'),
        parameterText: (await boundedBytes(request.parameters)).toString('utf8'),
      };
      texts.current = read;
      return contentCid(invocationOf(request, requestCid, read));
    };
  }

  // The durable deferral of one prepare attempt. `describe` never reads a
  // path: it holds the captured inputs, request and prepared invocation of
  // this attempt, the review projection and the continuation (which records
  // the exact evidence references, their holdings and the key id) as private
  // evidence, and returns the Checkpoint body requiring that prepared
  // invocation. The gate persists it through `journal` before reporting a wait.
  function deferralFor({prepareAttemptId, request, requestCid, texts,
    approved, binding, port}: Readonly<{
    prepareAttemptId: string; request: InvocationRequest; requestCid: string; texts: TextCapture;
    approved: readonly ApprovedSubject[]; binding: Parameters<Journal['claimPreparationResume']>[1]['binding'];
    port: Deferral['journal'];
  }>): Deferral {
    return {
      journal: port,
      authorities,
      binding,
      async describe(view) {
        const read = texts.current;
        if (read === undefined) fail('InputsNotCaptured');
        const invocation = invocationOf(request, requestCid, read);
        const invocationCid = contentCid(invocation);
        const kind = view.boundary === 'preparation' ? 'run_scope' : 'read_access';
        const review = {
          kind: 'local-example-review',
          boundary: view.boundary,
          tuple: plain(view.tuple),
          database: request.database,
          source: `${request.schema}.${request.table}`,
          invocation_cid: invocationCid,
        };
        const reviewCid = contentCid(review);
        const items = [...invocationEvidence(request, read),
          {name: 'prepared_invocation', wire: canonicalJson(invocation)},
          {name: 'review_projection', wire: canonicalJson(review)}];
        const continuation = {
          kind: 'local-example-continuation',
          prepare_attempt_id: prepareAttemptId,
          boundary: view.boundary,
          invocation_cid: invocationCid,
          delegated_subject: plain(view.subject),
          approved: approved.map(plain),
          // Exact evidence references, their holdings and key id.
          evidence: items.map(({name, wire}) =>
            evidence.reference(prepareAttemptId, name, wire)),
        };
        const continuationCid = contentCid(continuation);
        await evidence.hold(prepareAttemptId, requestCid, [...items,
          {name: 'continuation_record', wire: canonicalJson(continuation)}]);
        const created = now();
        return {
          priorStatus: undefined,
          declaredResults: [...DECLARED_RESULTS],
          binding,
          body: {
            checkpoint_id: `${prepareAttemptId}-${view.boundary}`,
            continuation_state_cid: continuationCid,
            subject: {kind: 'prepare_attempt', prepare_attempt_id: prepareAttemptId,
              continuation: 'start_run'},
            kind,
            // Both boundaries require the captured prepared invocation: the
            // gate sealed it on the preparation defer path, and it is the
            // acquisition subject. The gate rejects any other artifact; the
            // exact decision subject is bound separately.
            required_artifact: {artifact_type: kind === 'run_scope'
              ? 'prepared_invocation' : 'read_scope', artifact_cid: invocationCid},
            review_projection_cid: reviewCid,
            human_summary: `${view.boundary === 'preparation' ? 'Prepare' : 'Read'} ` +
              `${request.schema}.${request.table} for the example invocation`,
            created_at: new Date(created).toISOString(),
            expires_at: new Date(created + config.checkpointTtlMs).toISOString(),
          },
        };
      },
    };
  }

  // Counts provider sessions and records every boundary this attempt
  // crossed on an admitted Host permit, so that a continuation persisted at
  // a later boundary resumes past it without asking again.
  function counting(gate: Gate, counts: Counts, permitted: ApprovedSubject[]): Gate {
    return Object.freeze({
      ...gate,
      async authorize(boundary, scope, options) {
        const decision = await gate.authorize(boundary, scope, options);
        // Each acquisition dispatch decision is followed by exactly one
        // source (provider) session; nothing else opens the source.
        if (boundary === 'acquisition' && decision.action === 'dispatch') {
          counts.provider_sessions += 1;
        }
        if (decision.action === 'dispatch' && decision.basis === 'host_permit') {
          const subject = {
            account_id: gate.accountId,
            configuration_cid: gate.configurationCid,
            entry_id: decision.entryId,
            ...decision.tuple,
            boundary,
            subject_cid: decision.subjectCid ?? '',
            context_cid: decision.contextCid,
          };
          if (!permitted.some(item => sameSubject(item.subject, subject))) {
            permitted.push({subject, actor: decision.authority});
          }
        }
        return decision;
      },
    });
  }

  function exampleOptions(request: InvocationRequest) {
    return {
      database: request.database,
      environment: request.environment,
      environmentCid: request.environment_cid,
      program: request.program,
      parameters: request.parameters,
      schema: request.schema,
      table: request.table,
      nativeMilliseconds: request.native_ms,
      resident: request.resident,
    };
  }

  async function completed(result: ExampleResult, runId: string, counts: Counts, extra: object = {}) {
    const report = result.report;
    const failed = report.status !== 'host-tasks-completed' ||
      result.execution.failure !== undefined && result.execution.failure !== null;
    const usage = result.execution.usage() as Pick<ReturnType<typeof snapshotProcessUsage>, 'attempts'>;
    await result.close();
    const run = journal.finishRun(runId, {status: failed ? 'failed' : 'succeeded'});
    return plain({
      status: run!.status,
      run_id: runId,
      result_cid: contentCid(plain(report.internal_output_cids)),
      internal_output_cids: report.internal_output_cids,
      tasks_completed: report.completed.length,
      task_attempts: usage.attempts,
      acquisition_receipts: report.acquisition_evidence?.receipts?.length ?? 0,
      failure: report.failure,
      counters: counts,
      ...extra,
    });
  }

  function refusal(error: ExecutionAuthorizationError, counts: Counts, extra: object = {}) {
    const decision = error.authorization as GateDecision | null | undefined;
    if (decision?.action === 'waiting') {
      const checkpoint = journal.inspect(decision.checkpoint!.checkpointCid);
      return plain({
        status: 'waiting_checkpoint',
        prepare_attempt_id: checkpoint!.prepareAttemptId,
        checkpoint: {
          checkpoint_id: checkpoint!.checkpointId,
          checkpoint_cid: checkpoint!.checkpointCid,
          kind: checkpoint!.kind,
          boundary: decision.boundary,
          expires_at: checkpoint!.expiresAt,
        },
        next_action: {kind: 'resolve_checkpoint',
          checkpoint_id: checkpoint!.checkpointId},
        counters: counts,
        ...extra,
      });
    }
    return plain({
      status: 'refused',
      runtime_code: (error as ErrorFields).runtimeCode,
      code: (error as ErrorFields).code,
      boundary: decision?.boundary,
      reason: decision?.reason,
      counters: counts,
      ...extra,
    });
  }

  const newCounts = () => ({provider_sessions: 0, continuation_starts: 0});

  type Counts = ReturnType<typeof newCounts>;

  return Object.freeze({
    journal,
    config,

    // Run one example invocation. Allow runs to completion; a deferred
    // delegated decision returns `waiting_checkpoint` with no provider I/O.
    async run(options: InvocationOptions, {signal, decide, answeringAuthorities}: Readonly<{
      signal?: AbortSignal; decide?: Decide; answeringAuthorities?: readonly string[];
    }> = {}) {
      context = await currentContext();
      if (context.unreadable) {
        return plain({status: 'refused', runtime_code: 'ACTQL_E_ACCOUNT_CONFIG_INVALID',
          code: 'ACTQL_E_ACCOUNT_CONFIG_INVALID', boundary: 'preparation',
          reason: 'configuration_unreadable', counters: newCounts()});
      }
      const request = requestOf(options);
      const requestCid = contentCid(request);
      const prepareAttemptId = `prepare-${randomUUID()}`;
      const texts: TextCapture = {current: undefined};
      const counts = newCounts();
      const binding = {
        authorizationContextCid: context.authorizationContextCid,
        environmentBindingCid: await environmentBinding(request),
      };
      const permitted: ApprovedSubject[] = [];
      let gate;
      try {
        gate = counting(await createLocalAuthorizationGate({
          accountConfiguration: context.configuration?.text,
          configurationCid: context.configuration?.configurationCid,
          admitConfiguration: context.configuration?.admitConfiguration,
          context: context.context,
          decide,
          answeringAuthorities: answeringAuthorities ?? [],
          deferral: deferralFor({prepareAttemptId, request, requestCid, texts,
            approved: permitted, binding, port: journal}),
        }), counts, permitted);
      } catch (error) {
        return plain({status: 'refused', runtime_code: (error as ErrorFields).runtimeCode ??
          'ACTQL_E_ACCOUNT_CONFIG_INVALID', code: (error as ErrorFields).code,
        boundary: 'preparation', reason: 'configuration_rejected', counters: counts});
      }
      let runId: string | undefined;
      try {
        const result = await runExample({
          ...exampleOptions(request),
          signal,
          authorization: gate,
          invocation: {
            requestCid,
            seal: sealerFor(request, requestCid, texts),
            identify(read) {
              texts.current = read;
              return contentCid(invocationOf(request, requestCid, read));
            },
          },
          continuation: {
            beforeRun() {
              runId = `run-${randomUUID()}`;
              journal.createRun({runId, declaredResults: [...DECLARED_RESULTS]});
            },
          },
        });
        return await completed(result, runId!, counts);
      } catch (error) {
        if (runId !== undefined) {
          journal.finishRun(runId, {status: 'failed'});
          return plain({status: 'failed', run_id: runId, code: (error as ErrorFields).code,
            counters: counts});
        }
        // Evidence held for a Checkpoint that was never committed has no
        // remaining need; a committed Checkpoint keeps it.
        await evidence.abandon(prepareAttemptId);
        if (error instanceof ExecutionAuthorizationError) return refusal(error, counts);
        throw error;
      }
    },

    // Safe metadata of every waiting Checkpoint. No review contents.
    list() {
      journal.expire();
      return journal.listPending().map(view => plain(view));
    },

    inspect(reference: string) {
      const view = journal.inspect(reference);
      if (view === undefined) return undefined;
      return plain({
        checkpoint: view,
        preparation: view.prepareAttemptId === null ? undefined
          : journal.getPreparation(view.prepareAttemptId),
        run: view.runId === null ? undefined : journal.getRunState(view.runId),
      });
    },

    status(reference: string) {
      if (typeof reference !== 'string' || reference.length === 0) {
        fail('InvalidReference');
      }
      const run = journal.getRunState(reference);
      if (run !== undefined) return plain({run: run.runState});
      const preparation = journal.getPreparation(reference);
      if (preparation !== undefined) {
        return plain({preparation, run: preparation.runId === null ? undefined
          : journal.getRunState(preparation.runId)!.runState});
      }
      const view = journal.inspect(reference);
      if (view !== undefined) return this.inspect(reference);
      return undefined;
    },

    // Answer one or more waiting Checkpoints with the signer's Host-trusted
    // key. Each Checkpoint receives its own Resolution and, for approval,
    // its own run-scope approval evidence; results are per item.
    async answer(references: readonly string[], decision: ApprovalDecision,
      {signer, decidedAt}: Readonly<{signer?: unknown; decidedAt?: string}> = {}) {
      if (decision !== 'approved' && decision !== 'rejected') fail('InvalidDecision');
      if (!Array.isArray(references) || references.length === 0) {
        fail('CheckpointReferenceRequired');
      }
      const key = parseSigner(signer as SignerDocument | null | undefined);
      const decided = decidedAt ?? new Date(now()).toISOString();
      const results = new Array<Readonly<{reference: string; status: string; reason?: string}>>(references.length);
      const items: ResolutionSubmission[] = [];
      const positions: [number, string][] = [];
      references.forEach((reference, index) => {
        let view;
        try { view = journal.inspect(reference); }
        catch (error) {
          results[index] = {reference, status: 'invalid', reason: (error as ErrorFields).code};
          return;
        }
        if (view === undefined) {
          results[index] = {reference, status: 'invalid',
            reason: 'CheckpointNotFound'};
          return;
        }
        items.push({checkpointCid: view.checkpointCid,
          ...resolutionFor(view, decision, key, decided)});
        positions.push([index, reference]);
      });
      if (items.length > 0) {
        const answered = await journal.submitResolutions(items);
        answered.forEach((item, position) => {
          const [index, reference] = positions[position];
          results[index] = {reference, ...item};
        });
      }
      return plain(results);
    },

    cancel(reference: string) {
      let target = reference;
      const preparation = typeof reference === 'string'
        ? journal.getPreparation(reference) : undefined;
      if (preparation !== undefined) {
        if (preparation.checkpointCid === null) {
          return plain({outcome: 'not_waiting', preparation});
        }
        target = preparation.checkpointCid;
      }
      return plain(journal.cancelCheckpoint(target));
    },

    // Resume an approved preparation continuation after any restart.
    async resume(reference: string, {claimant = `host-${process.pid}-${randomUUID()}`,
      leaseMs = 60_000, signal, decide, holdAfterClaimMs = 0}: Readonly<{
      claimant?: string; leaseMs?: number; signal?: AbortSignal; decide?: ResumeDecide; holdAfterClaimMs?: number;
    }> = {}) {
      journal.expire();
      let prepareAttemptId = reference;
      if (journal.getPreparation(reference) === undefined) {
        const view = journal.inspect(reference);
        if (view?.prepareAttemptId == null) fail('PreparationNotFound');
        prepareAttemptId = view.prepareAttemptId;
      }
      const held = await evidence.open(prepareAttemptId);
      const requestCid = held.requestCid;
      const request = await held.record('invocation_request', requestCid) as InvocationRequest;
      if (contentCid(request) !== requestCid) fail('ArtifactIntegrityFailed');
      context = await currentContext();
      const binding = {
        authorizationContextCid: context.authorizationContextCid,
        environmentBindingCid: await environmentBinding(request),
      };
      const counts = newCounts();
      const claimed = journal.claimPreparationResume(prepareAttemptId,
        {claimant, leaseMs, binding});
      if (claimed.action === 'invalidated') {
        return plain({status: 'ended', prepare_attempt_id: prepareAttemptId,
          run_created: false, terminal_error_code: claimed.terminalErrorCode,
          counters: counts});
      }
      if (claimed.action !== 'claimed') {
        return plain({status: claimed.action, prepare_attempt_id: prepareAttemptId,
          counters: counts});
      }
      counts.continuation_starts += 1;
      const fence = {claim: claimed.claim};
      if (holdAfterClaimMs > 0) {
        await new Promise(done => setTimeout(done, holdAfterClaimMs));
      }
      // A superseded claimant is reported in one form, `stale_claim`,
      // wherever the fence refuses it: here when it tries to end the
      // continuation (for example after the winner's terminal exit retired
      // the private evidence it could no longer read).
      const staleClaim = (code: string | undefined) => plain({status: 'stale_claim',
        prepare_attempt_id: prepareAttemptId, code, counters: counts});
      const end = async (status: 'failed' | 'cancelled', extra: object) => {
        try {
          journal.completeResume(fence.claim, {status});
        } catch (error) {
          if ((error as ErrorFields | null | undefined)?.code === 'ResumeClaimStale') return staleClaim((error as ErrorFields).code);
          throw error;
        }
        return plain({status: 'ended', prepare_attempt_id: prepareAttemptId,
          run_created: false, end_reason: status, counters: counts, ...extra});
      };
      let continuation: Readonly<{invocation_cid: string; delegated_subject: Subject; approved: readonly ApprovedSubject[]}>;
      let texts: CapturedTexts;
      try {
        continuation = await held.record('continuation_record',
          claimed.continuationStateCid) as typeof continuation;
        const invocation = await held.record('prepared_invocation',
          continuation.invocation_cid) as ReturnType<typeof invocationOf>;
        const input = async (cid: string) =>
          (await held.bytes('captured_input', cid)).toString('utf8');
        texts = {
          programText: await input(invocation.program_cid),
          environmentText: await input(invocation.environment_text_cid),
          parameterText: await input(invocation.parameters_cid),
        };
        if (invocation.request_cid !== requestCid ||
            contentCid(invocationOf(request, requestCid, texts)) !==
              continuation.invocation_cid) {
          fail('ArtifactIntegrityFailed');
        }
        // The approved Checkpoint must require exactly this captured
        // prepared invocation and bind exactly the delegated decision
        // subject (for preparation, the request) it was deferred on.
        const sealed = journal.inspect(claimed.checkpointCid);
        if (sealed?.requiredArtifact.cid !== continuation.invocation_cid ||
            sealed.decisionSubjectCid !==
              await decisionSubjectCid(continuation.delegated_subject)) {
          fail('ResolutionSubjectMismatch');
        }
      } catch (error) {
        return end('failed', {code: (error as ErrorFields).code ?? 'ContinuationUnavailable'});
      }
      // The approved subjects of this attempt, each with its answering actor
      // and, for a reviewer approval, the Checkpoint it answered.
      const answer = journal.resolutionOf(claimed.checkpointCid);
      const approved: ApprovedSubject[] = [...continuation.approved, {subject:
        continuation.delegated_subject, actor: answer!.actor,
      invocation_cid: continuation.invocation_cid,
      checkpoint_cid: claimed.checkpointCid}];
      // Approvals this attempt answered before the claimed Checkpoint are
      // each checked on their own at the Host trusted time: an earlier
      // approval whose permission lapsed authorizes no new work, even while
      // the claimed Checkpoint's approval is current. (The claimed approval
      // is checked by the admission itself.)
      const earlierApprovalsCurrent = () => {
        const seen = new Set([claimed.checkpointCid]);
        for (const item of approved) {
          const cid = item.checkpoint_cid;
          if (cid === undefined || seen.has(cid)) continue;
          seen.add(cid);
          const approval = journal.committedApprovalAt(cid);
          if (approval.authority !== item.actor) {
            fail('ResolutionNotCommitted');
          }
          if (!approval.current) fail('ApprovalExpired');
        }
      };
      const port: Deferral['journal'] = {
        persistCheckpoint: ({body, authorities: reviewers, binding: bound,
          decisionSubjectCid, requestedClaims, configurationCid}) =>
          // A preparation claim completed with a successor Checkpoint returns
          // the committed waiting receipt, as opposed to a Run or terminal exit.
          journal.completeResume(fence.claim, {checkpoint: {body,
            authorities: reviewers, binding: bound, decisionSubjectCid,
            requestedClaims, configurationCid}}) as Awaited<ReturnType<Deferral['journal']['persistCheckpoint']>>,
        submitResolution: (item: ResolutionSubmission) => journal.submitResolution(item),
      };
      // An approved subject is permitted only through the common resumed
      // admission: the live claim, the committed approval still valid at the
      // Host trusted time and the claims its evidence established.
      let admission: Admission | undefined;
      let admissionRefusal: string | undefined;
      const configurationCid = context.configuration?.configurationCid;
      const admit = (options: ResumeOptions) => {
        const admitted = admitResumedDispatch(journal, {claim: {
          checkpointCid: claimed.checkpointCid, claim: fence.claim}},
        {configurationCid, ...options});
        if (admitted.detail !== undefined) {
          admissionRefusal = admitted.detail;
          fail(admitted.detail);
        }
        return admitted;
      };
      const resumeDecide: Decide = view => {
        const match = approved.find(item => coverage(item, view.subject));
        // An earlier immediate permit (no Checkpoint) was the Host's own
        // answer for this attempt. When the Host supplies a decision
        // function at resume it answers again, so a current reject or defer
        // holds; without one only the same exact subject is reused.
        if (match !== undefined && match.checkpoint_cid === undefined &&
            decide !== undefined) {
          return decide(view);
        }
        if (match !== undefined) {
          try { earlierApprovalsCurrent(); }
          catch (error) {
            admissionRefusal = (error as ErrorFields).code;
            throw error;
          }
          const admitted = admit({requiredClaims: view.requiredClaims});
          admission = admitted.admission;
          return {decision: 'permit', subject: view.subject,
            authority: match.actor, claims: [...admitted.claims]};
        }
        return decide !== undefined ? decide(view)
          : {decision: 'defer', subject: view.subject};
      };
      const gate = counting(await createLocalAuthorizationGate({
        accountConfiguration: context.configuration?.text,
        configurationCid: context.configuration?.configurationCid,
        admitConfiguration: context.configuration?.admitConfiguration,
        context: context.context,
        decide: resumeDecide,
        answeringAuthorities: [...new Set([...reviewerIds,
          ...approved.map(item => item.actor)])],
        deferral: deferralFor({prepareAttemptId, request, requestCid,
          texts: {current: texts}, approved, binding, port}),
      }), counts, approved);
      let runId: string | undefined;
      try {
        const result = await runExample({
          ...exampleOptions(request),
          signal,
          authorization: gate,
          invocation: {
            requestCid,
            texts,
            seal: sealerFor(request, requestCid, {current: texts}),
            identify: read => contentCid(invocationOf(request, requestCid, read)),
          },
          continuation: {
            // Re-prove the fence before any provider I/O: a superseded
            // claimant stops here.
            beforeAcquisition() {
              fence.claim = journal.renewResume(fence.claim, leaseMs) as typeof fence.claim;
              earlierApprovalsCurrent();
              // The provider session is the protected send: enter the
              // admission (fence, approval validity, single start per claim
              // generation) immediately before it. A session an earlier
              // claim generation may have started refuses the fresh start
              // (`PriorAdmissionUnresolved`): a provider session has no
              // durable identity to reconcile, so no second one starts.
              // With every boundary now allowed there is no approval
              // admission, but the same ownership admission still applies.
              admission ??= admit({approvalClaims: false}).admission;
              admission!.enter();
            },
            // Preparation completed: the continuation creates its Run
            // directly in `running`, atomically with the intent completion.
            beforeRun() {
              const id = `run-${randomUUID()}`;
              journal.completeResume(fence.claim, {run: {runId: id,
                status: 'running'}});
              runId = id;
            },
          },
        });
        return await completed(result, runId!, counts,
          {prepare_attempt_id: prepareAttemptId});
      } catch (error) {
        if (runId !== undefined) {
          journal.finishRun(runId, {status: 'failed'});
          return plain({status: 'failed', run_id: runId, code: (error as ErrorFields).code,
            prepare_attempt_id: prepareAttemptId, counters: counts});
        }
        // An earlier claim generation entered its provider session and its
        // outcome is unknown: the intent is neither completed nor failed
        // here. It stays for reconciliation or that generation's completion.
        if ((error as ErrorFields | null | undefined)?.code === 'PriorAdmissionUnresolved') {
          return plain({status: 'reconciliation_required',
            prepare_attempt_id: prepareAttemptId, code: (error as ErrorFields).code,
            prior_generation: (error as ErrorFields).priorAdmission?.generation,
            counters: counts});
        }
        if ((error as ErrorFields | null | undefined)?.code === 'ResumeClaimStale' ||
            admissionRefusal === 'ResumeClaimStale') {
          return staleClaim('ResumeClaimStale');
        }
        if (error instanceof ExecutionAuthorizationError) {
          if (error.authorization?.action === 'waiting') {
            return refusal(error, counts);
          }
          return end('failed', {runtime_code: (error as ErrorFields).runtimeCode,
            boundary: (error.authorization as GateDecision | null | undefined)?.boundary,
            reason: error.authorization?.reason,
            ...(admissionRefusal === undefined ? {}
              : {code: admissionRefusal})});
        }
        try { return await end('failed', {code: (error as ErrorFields).code}); }
        catch { throw error; }
      }
    },

    // Explicit permitted retirement: expire overdue Checkpoints, then release
    // the holdings of every continuation with no remaining need. A failed
    // deletion stays owned and pending; calling this again retries it.
    async retire() {
      journal.expire();
      return plain(await evidence.settle());
    },

    // Closes the journal and releases the Store owner. Never deletes
    // evidence: waiting continuations keep theirs.
    close() {
      journal.close();
      return evidence.close();
    },
  });
}

function parseSigner(signer: SignerDocument | null | undefined) {
  if (signer === null || typeof signer !== 'object' ||
      !IDENTIFIER.test(signer.key_id ?? '') ||
      !IDENTIFIER.test(signer.reviewer_id ?? '') ||
      typeof signer.private_key_pem !== 'string') {
    fail('InvalidSigner');
  }
  return Object.freeze({keyId: signer.key_id, reviewerId: signer.reviewer_id,
    privateKey: createPrivateKey(signer.private_key_pem)});
}

export async function readSigner(path: string): Promise<unknown> {
  if (typeof path !== 'string' || path.length === 0) fail('SignerRequired');
  try { return JSON.parse(await readFile(resolve(path), 'utf8')); }
  catch (error) { fail('InvalidSigner', error); }
}

const signText = (text: string, key: ReturnType<typeof parseSigner>) =>
  sign(null, Buffer.from(text, 'utf8'), key.privateKey).toString('base64');

// One Resolution for one Checkpoint, signed per the pinned preimage rule:
// Ed25519 over the unsigned Resolution CID text. An approval carries its own
// run-scope approval evidence bound to this Checkpoint only.
function resolutionFor(view: CheckpointView, decision: ApprovalDecision, key: ReturnType<typeof parseSigner>, decidedAt: string) {
  let evidence;
  if (decision === 'approved') {
    const approval = {
      version: 'actql-run-scope-approval/0.1',
      prepared_invocation_cid: view.requiredArtifact.cid,
      review_projection_cid: view.reviewProjectionCid,
      claim: 'invocation_scope_approved',
      approver: key.reviewerId,
      approved_at: decidedAt,
      expires_at: view.expiresAt,
    } as {proof?: Signature; run_scope_approval_cid?: string} & Readonly<Record<string, unknown>>;
    approval.proof = {scheme: 'ed25519-v1', key_id: key.keyId,
      signature: signText(contentCid(approval), key)};
    approval.run_scope_approval_cid = contentCid(approval);
    evidence = {
      version: 'actql-checkpoint-approval-evidence/0.1',
      kind: view.kind,
      checkpoint_cid: view.checkpointCid,
      review_projection_cid: view.reviewProjectionCid,
      compatibility_approval: approval,
    };
  }
  const identity = view.prepareAttemptId !== null
    ? {prepare_attempt_id: view.prepareAttemptId}
    : {run_id: view.runId, run_definition_cid: view.runDefinitionCid};
  const body = {
    version: 'actql-checkpoint-resolution/0.1',
    resolution_id: `resolution-${view.checkpointId}-${decision}`,
    checkpoint_id: view.checkpointId,
    checkpoint_cid: view.checkpointCid,
    ...identity,
    decision,
    actor: key.reviewerId,
    decided_at: decidedAt,
    required_artifact_cid: view.requiredArtifact.cid,
    review_projection_cid: view.reviewProjectionCid,
    ...(evidence === undefined ? {} : {approval_evidence_cid: contentCid(evidence)}),
  } as {proof?: Signature; resolution_cid?: string} & Readonly<Record<string, unknown>>;
  body.proof = {scheme: 'ed25519-v1', key_id: key.keyId,
    signature: signText(contentCid(body), key)};
  body.resolution_cid = contentCid(body);
  return {
    resolutionWire: canonicalJson(body),
    approvalEvidenceWire: evidence === undefined ? '' : canonicalJson(evidence),
  };
}
