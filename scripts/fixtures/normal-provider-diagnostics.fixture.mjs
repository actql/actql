// Bounded caller-owned diagnostics only. No Host/Core handle, reader, grant,
// retry or failure classification is issued by this fixture helper.
import {types as nodeTypes} from 'node:util';
import {createDecipheriv, createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {open} from 'node:fs/promises';
import {join} from 'node:path';

const cid = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const canonicalFields = fields => JSON.stringify(Object.fromEntries(Object.entries(fields).sort(
  ([left], [right]) => left < right ? -1 : left > right ? 1 : 0)));

async function readClosedFixtureFile(path, maximum) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const original = await file.stat();
    if (!original.isFile() || original.size < 1 || original.size > maximum) throw Error('OriginalRawFixtureExtent');
    const buffer = Buffer.alloc(original.size + 1);
    const {bytesRead} = await file.read(buffer, 0, buffer.length, 0);
    const current = await file.stat();
    if (bytesRead !== original.size || current.size !== original.size || current.mtimeMs !== original.mtimeMs ||
        current.ctimeMs !== original.ctimeMs) throw Error('OriginalRawFixtureChanged');
    return buffer.subarray(0, bytesRead);
  } finally {await file.close();}
}

// Read-only proof for this controlled fixture's closed Store. The fixture key
// authenticates existing ciphertext; neither decrypted body is reported.
export async function closedModelRawEvidence({publication, keyPath, storeAuthorityCid, definitionCid,
  attemptCid, scopeCid, slotCid, expectMissing = false}) {
  const binding = {attempt: 1, attempt_cid: attemptCid, phase: 'entered',
    run_definition_cid: definitionCid, scope_cid: scopeCid, slot_cid: slotCid, store_authority_cid: storeAuthorityCid};
  const holdingCid = cid(canonicalFields({...binding, role: 'model_raw_response',
    version: 'actql-model-scoped-private-holding/0.1'}));
  const recordPath = join(publication, 'physical-holdings', holdingCid.slice(7) + '.json');
  const wire = await readClosedFixtureFile(recordPath, 8192).catch(error => {
    if (expectMissing && error.code === 'ENOENT') return undefined;
    throw error;
  });
  if (wire === undefined) return undefined;
  if (expectMissing) throw Error('UnexpectedOriginalRawFixtureHolding');
  const holding = JSON.parse(wire);
  const descriptorCid = holding.manifest_cid;
  if (holding.holding_cid !== holdingCid || holding.namespace !== 'publication-private' ||
      !Array.isArray(holding.objects) || holding.objects.length !== 2 ||
      !/^sha256:[a-f0-9]{64}$/u.test(descriptorCid)) throw Error('OriginalRawFixtureHolding');
  const key = await readClosedFixtureFile(keyPath, 32);
  const version = 'actql-private-publication-evidence/0.1';
  const decode = async (object, role, maximum) => {
    if (!/^sha256:[a-f0-9]{64}$/u.test(object.cid)) throw Error('OriginalRawFixtureObject');
    const sealed = await readClosedFixtureFile(join(publication, 'objects', object.cid.slice(7)), maximum);
    if (sealed.length !== object.byte_count || cid(sealed) !== object.cid) throw Error('OriginalRawFixtureObject');
    const envelope = JSON.parse(sealed);
    if (envelope.version !== version) throw Error('OriginalRawFixtureEnvelope');
    const decrypt = createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.nonce, 'base64'));
    decrypt.setAAD(Buffer.from(version + '\0' + role + '\0' + descriptorCid));
    decrypt.setAuthTag(Buffer.from(envelope.tag, 'base64'));
    const body = decrypt.update(Buffer.from(envelope.ciphertext, 'base64'));
    try {
      if (decrypt.final().length !== 0) throw Error('OriginalRawFixtureEnvelope');
      return body;
    } catch (error) {
      body.fill(0);
      throw error;
    }
  };
  let descriptor, content;
  try {
    descriptor = await decode(holding.objects[0], 'model_raw_descriptor', 12288);
    const {self_cid: selfCid, ...facts} = JSON.parse(descriptor);
    if (selfCid !== descriptorCid || cid(canonicalFields(facts)) !== descriptorCid ||
        facts.version !== 'actql-model-raw-response/0.1' ||
        !Object.entries(binding).every(([name, value]) => facts[name] === value)) throw Error('OriginalRawFixtureBinding');
    content = await decode(holding.objects[1], 'model_raw_content', 65536);
    if (facts.byte_count !== content.length || facts.content_cid !== cid(content)) throw Error('OriginalRawFixtureContent');
    return {holdingCid, descriptorCid, contentCid: facts.content_cid, byteCount: facts.byte_count,
      httpStatus: facts.http_status, transportEof: facts.transport_eof,
      objectCids: holding.objects.map(object => object.cid)};
  } finally {
    content?.fill(0);
    descriptor?.fill(0);
    key.fill(0);
  }
}

import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';

const requestJournal = '.state/requests/client-requests.sqlite3';

function fixtureAdmissionStatement(database, reference) {
  const where = ' WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?';
  const key = [reference.namespaceId, reference.authorityScopeCid, reference.runDefinitionCid];
  const read = () => database.prepare('SELECT run_admission_evidence_json FROM client_requests' + where)
    .get(...key).run_admission_evidence_json;
  return {where, key, read};
}

export function modelPlanFixtureDigest(value) {
  return 'sha256:' + createHash('sha256').update(value).digest('hex');
}

export function omitFixtureModelPlanBinding(reference, taskCid) {
  // Change exactly one optional association in the closed fixture's genuine
  // Run. Every other admission field and the parked or settled rows stay put.
  const database = new DatabaseSync(requestJournal);
  try {
    const {where, key, read} = fixtureAdmissionStatement(database, reference);
    const original = read();
    const {modelPlanBindings, ...remaining} = JSON.parse(original);
    assert.equal(modelPlanBindings.runDefinitionCid, reference.runDefinitionCid);
    assert.equal(modelPlanBindings.bindings.length, 1);
    const [member] = modelPlanBindings.bindings;
    if (taskCid !== undefined) assert.equal(member.taskCid, taskCid);
    assert.equal(typeof remaining.modelOriginalRunWire, 'string');
    const wire = JSON.stringify(remaining);
    const updated = database.prepare('UPDATE client_requests SET run_admission_evidence_json = ?' + where +
      ' AND run_admission_evidence_json = ?').run(wire, ...key, original);
    assert.equal(updated.changes, 1);
    assert.equal(read(), wire);
    const evidence = {originalSha256: modelPlanFixtureDigest(original), admittedSha256: modelPlanFixtureDigest(wire)};
    return {member, evidence};
  } finally { database.close(); }
}

export function verifyFixtureModelPlanBindingStillAbsent(reference, evidence) {
  const database = new DatabaseSync(requestJournal, {readOnly: true});
  try {
    assert.equal(modelPlanFixtureDigest(fixtureAdmissionStatement(database, reference).read()), evidence.admittedSha256);
  } finally { database.close(); }
}

function ownData(value, key) {
  if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) return undefined;
  const field = Object.getOwnPropertyDescriptor(value, key);
  return field !== undefined && Object.hasOwn(field, 'value') ? field.value : undefined;
}

// Copy only existing inert diagnostic scalars. In particular, a code-site
// message, exception, cause object or arbitrary diagnostic member is not read.
function diagnosticScalars(value, cleanup = false) {
  const data = {};
  const accept = (key, valid) => {
    const selected = ownData(value, key);
    if (valid(selected)) data[key] = selected;
  };
  if (cleanup) {
    accept('owner', v => ['local_managed', 'managed_operations'].includes(v));
    accept('phase', v => ['close_additional', 'close_operations', 'await_stop', 'settle_operations', 'refresh_cleanup'].includes(v));
    accept('continuation', v => ['runnable', 'blocked', 'unavailable'].includes(v));
  } else {
    accept('code', v => typeof v === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,95}$/u.test(v));
    for (const key of ['phase', 'kind', 'cause']) {
      accept(key, v => typeof v === 'string' && v.length <= 96 && /^[a-z_]+(?:\.[a-z_]+)*$/u.test(v));
    }
    for (const key of ['task', 'unit', 'step', 'controlWorkLimit']) {
      accept(key, v => Number.isSafeInteger(v) && v >= 0 && v <= 2147483647);
    }
    accept('workLimit', v => Number.isSafeInteger(v) && v >= 0 && v <= 2147483647 ||
      typeof v === 'string' && /^(?:0|[1-9][0-9]{0,18})$/u.test(v) && BigInt(v) <= 9223372036854775807n);
    accept('dimension', v => ['retained_bytes', 'execution_bytes'].includes(v));
    accept('setting', v => ['installation.sourceFreeMaxWork', 'unavailable'].includes(v));
  }
  return Object.keys(data).length === 0 ? undefined : data;
}

// Start the observation budget at the physical peer entry. The same wait
// remains concurrent with cancellation and has a rejection handler from issue.
export async function observeEnteredCancellation({awaitEntry, wait, cancel, record}) {
  record('entry_pending');
  try { await awaitEntry(); }
  catch (failure) {
    record('entry_failed');
    throw failure;
  }
  record('entered');
  let waitFailure;
  const waiting = wait().then(value => {
    record('wait_returned');
    return value;
  }, failure => {
    waitFailure = {cause: failure};
    record('wait_failed');
  });
  record('wait_started');
  try { await cancel(); }
  catch (failure) {
    record('cancel_path_failed');
    throw waitFailure === undefined ? failure : waitFailure.cause;
  }
  const result = await waiting;
  if (waitFailure !== undefined) throw waitFailure.cause;
  return result;
}

export function normalProviderDiagnostics({phase, work, write}) {
  const terminals = [], requests = [], failures = [], dispatchFailures = [];
  let calls = 0;
  const problem = cause => ({name: typeof cause?.name === 'string' ? cause.name : null,
    code: typeof cause?.code === 'string' ? cause.code : null});
  const note = cause => {if (failures.length < 8) failures.push(problem(cause));};
  const put = async (path, value, exclusive) => {
    try {
      const wire = JSON.stringify(value) + '\n';
      if (Buffer.byteLength(wire) > 1048576) throw Error('NormalDiagnosticByteLimit');
      await write(path, wire, {mode: 0o600, ...(exclusive ? {flag: 'wx'} : {})});
    } catch (cause) {note(cause);}
  };
  const snapshot = () => {
    try {return work.snapshot();}
    catch (cause) {note(cause);return {complete: false, unavailable: true};}
  };
  return {
    dispatchFailure(event, detail) {
      if (event !== 'dispatch_failed') return;
      if (dispatchFailures.length === 2) {note(Error('NormalDiagnosticDispatchLimit'));return;}
      try {
        const record = {};
        const code = ownData(detail, 'primaryCode');
        if (code === 'ModelProjectCredentialUnavailable') {
          record.credentialRefusal = code;
        }
        if (code === 'InstalledModelStructuredModelUnsupported' ||
            code === 'InstalledModelStructuredAdapterUnsupported') record.capabilityRefusal = code;
        const primary = diagnosticScalars(ownData(detail, 'primaryDiagnostic'));
        const cleanup = diagnosticScalars(ownData(detail, 'cleanupDiagnostic'), true);
        if (primary !== undefined) record.primary = primary;
        if (cleanup !== undefined) record.cleanup = cleanup;
        for (const key of ['issueTag', 'nestedIssueTag', 'leafIssueTag']) {
          const value = ownData(detail, key);
          if (Number.isSafeInteger(value) && value >= 0 && value <= 65535) record[key] = value;
        }
        dispatchFailures.push(record);
      } catch {note(Error('NormalDiagnosticDispatchProjectionFailed'));}
    },
    request(request) {
      calls++;
      if (requests.length === 2) {note(Error('NormalDiagnosticRequestLimit'));return;}
      const method = typeof request.method === 'string' && /^[A-Z]{1,16}$/u.test(request.method) ? request.method : '<unexpected>';
      // Allow only known fixture endpoints. Never copy headers/body/query or
      // disclose an arbitrary unexpected URL supplied by a different caller.
      const path = request.url?.split('?')[0];
      requests.push({method, path: path === '/v1/chat/completions' || path === '/v1/responses' ? path : '<unexpected>'});
    },
    async terminal(index, value) {
      if (![0, 1].includes(index) || terminals.some(entry => entry.index === index)) {
        note(Error('NormalDiagnosticTerminalConflict'));return;
      }
      const path = `terminal-${index}.json`;
      terminals.push({index, path});
      // Preserve the FULL original public reply before its existing assertion.
      // It is not another status call or a recovered/reconstructed terminal.
      await put(path, value, true);
      await put('normal-diagnostic-before-assert.json', {phase, terminals, dispatchFailures, http: {calls, requests}, work: snapshot()}, false);
    },
    async finish(firstClose, fd, cleanup) {
      const value = {phase, qualification: 'Instrumented caller diagnostics, not pristine timing or an internal physical ACK',
        terminals, dispatchFailures, http: {calls, requests}, work: snapshot(), firstClose, fd, cleanup, diagnosticFailures: failures};
      await put('normal-diagnostic.json', value, false);
      return {value, complete: failures.length === 0 && value.work.complete === true};
    },
  };
}
