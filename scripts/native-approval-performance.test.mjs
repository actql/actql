import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {approvalCallCounts, assertApprovalCallCounts, assessNativeApproval, approvalResources, approvalPhases} from './native-approval-performance.mjs';

const sourceSha = 'a'.repeat(40), fixtureSha256 = 'b'.repeat(64), runnerSha256 = 'c'.repeat(64);
const series = () => ({mode: 'final', sourceSha, fixtureSha256, runnerSha256,
  samples: Array.from({length: 30}, (_, iteration) => ({iteration, sourceSha, fixtureSha256,
    runnerSha256, wallNs: 4000000000, cpuUserUs: 1000, cpuSystemUs: 1000, cpuScope: 'synthetic OS sample', peakRssBytes: 4096, rssScope: 'synthetic OS sample', completed: true, verified: true}))});

test('authenticated Host subject consumes its original control header without parsing it again', () => {
  const controlSource = readFileSync(new URL('../src/platform_native/client_host/local_initial_signing_original.mbt', import.meta.url), 'utf8');
  const subjectSource = readFileSync(new URL('../src/platform_native/client_host/local_initial_host_signing_subject.mbt', import.meta.url), 'utf8');
  const body = (source, name) => {
    const start = source.indexOf('fn ' + name + '(');
    assert(start >= 0, 'Missing actual control reader: ' + name);
    const end = source.indexOf('\n///|', start);
    return source.slice(start, end < 0 ? undefined : end);
  };
  const control = body(controlSource, 'read_local_initial_signing_control_with_host_key');
  const independent = body(subjectSource, 'read_initial_host_signing_subject');
  const selected = control.includes('read_initial_host_signing_subject_after_header(')
    ? body(subjectSource, 'read_initial_host_signing_subject_after_header') : independent;
  const parses = value => [...value.matchAll(/local_initial_signing_control_header\(/gu)].length;
  assert.equal(parses(control) + parses(selected), 1,
    'The same authenticated control must not run the canonical header codec twice');
  assert.match(control, /read_initial_host_signing_subject_after_header\(\n\s+host,\n\s+header,\n\s+host_key,/u);
  assert.equal(parses(independent), 1, 'Independent callers retain complete closed-header admission');
  assert.match(independent, /read_initial_host_signing_subject_after_header\(\s*host,\s*header,\s*fields,\s*signing_original~,?\s*\)/u);
  assert.doesNotMatch(selected, /\.transaction\(|\.check_binding\(|\.authorize\(|\.now\(|mut /u);
  assert.match(selected, /read_local_installation_authenticated_payload\(/u);
  assert.match(selected, /local_adoption_fields\(payload,/u);
  for (const original of ['fields.public_key.cid()', 'host.session.intent_cid', 'fields.issuer', 'fields.policy.cid()']) {
    assert(selected.includes(original), 'Missing original subject correspondence: ' + original);
  }
});

test('Native approval target requires thirty verified samples on the same source fixture and runner', () => {
  assert.equal(assessNativeApproval(series()).status, 'passed');
  const short = series(); short.samples.pop();
  const result = assessNativeApproval(short);
  assert.equal(result.status, 'incomplete'); assert.equal(result.summary.p95Ms, null);
  for (const field of ['sourceSha', 'fixtureSha256', 'runnerSha256']) {
    const mixed = series(); mixed.samples[0][field] = 'd'.repeat(field === 'sourceSha' ? 40 : 64);
    assert.throws(() => assessNativeApproval(mixed), /Mixed Native approval/u);
  }
});

test('Native approval enforces both p95 and maximum without dropping slow failures', () => {
  const slow = series(); slow.samples[0].wallNs = 11000000000;
  slow.samples[0].verified = false;
  const result = assessNativeApproval(slow);
  assert.equal(result.status, 'failed'); assert.equal(result.summary.maxMs, 11000);
  assert(result.failures.some(value => value.includes('oracle failed')));
  assert(result.failures.some(value => value.includes('maximum')));
  const p95 = series(); p95.samples[0].wallNs = p95.samples[1].wallNs = 6000000000;
  assert(assessNativeApproval(p95).failures.some(value => value.includes('p95')));
});

test('Native approval diagnostic samples do not supply a final acceptance p95', () => {
  const selected = series(); selected.mode = 'diagnostic'; selected.samples.length = 3;
  const result = assessNativeApproval(selected);
  assert.equal(result.status, 'incomplete'); assert.equal(result.summary.p95Ms, null);
  assert(result.missing.includes('diagnostic only'));
  selected.samples.push({...selected.samples[0]});
  assert.throws(() => assessNativeApproval(selected));
});

test('Native approval call bounds retain mutable SQL while refusing helper amplification', () => {
  const counts = {pid: 1, sqlPrepares: 300, currentCalls: 50, externalBoundaries: 4, unexpectedHelperRevalidations: 0,
    hostAuthorizations: 1, adoptionDigests: 10, materialAdmissions: 1, sourceValidations: 8, memberHashes: 11};
  assertApprovalCallCounts(counts, 2);
  assert.throws(() => assertApprovalCallCounts({...counts, unexpectedHelperRevalidations: 1}, 2), /repeated immutable/u);
  for (const field of ['sqlPrepares', 'currentCalls', 'sourceValidations', 'adoptionDigests']) {
    assert.throws(() => assertApprovalCallCounts({...counts, [field]: 100000}, 2), /amplified/u);
  }
  for (const field of ['sqlPrepares', 'currentCalls', 'sourceValidations', 'externalBoundaries', 'materialAdmissions']) {
    assert.throws(() => assertApprovalCallCounts({...counts, [field]: 0}, 2), /missing/u);
  }
  assert.throws(() => assertApprovalCallCounts(counts, 0));
});

test('Native approval counters refuse incomplete overflowed duplicated or signalled observations', () => {
  const counters = Array.from({length: 70}, (_, tag) => ({tag, name: 'fixture', count: tag + 1}));
  const metadata = {pid: 123, overflow: false, initializing_drops: 0, invalid_tags: 0, invalid_amounts: 0};
  const record = () => ({code: 0, signal: null, stderr: 'ACTQL_NATIVE_TIMINGS ' + JSON.stringify(metadata) + '\n' +
    counters.map(value => 'ACTQL_NATIVE_COUNTER ' + JSON.stringify(value) + '\n').join('')});
  assert.equal(approvalCallCounts(record()).sqlPrepares, 2);
  const missing = record(); missing.stderr = missing.stderr.split('\n').slice(0, -2).join('\n');
  assert.throws(() => approvalCallCounts(missing), /Incomplete/u);
  const duplicate = record(); duplicate.stderr += 'ACTQL_NATIVE_COUNTER ' + JSON.stringify(counters[0]) + '\n';
  assert.throws(() => approvalCallCounts(duplicate), /duplicate/u);
  assert.throws(() => approvalCallCounts({...record(), signal: 'SIGKILL'}), /signal/u);
  metadata.overflow = true;
  assert.throws(() => approvalCallCounts(record()), /overflow/u);
});


test('OS approval resources retain actual command scope and reject unavailable measurements', () => {
  const mac = approvalResources('real 1.20\nuser 0.30\nsys 0.10\n 4096 maximum resident set size\n', 'darwin');
  assert.equal(mac.cpuUserUs, 300000); assert.equal(mac.cpuSystemUs, 100000); assert.equal(mac.peakRssBytes, 4096);
  const linux = approvalResources(' User time (seconds): 0.30\n System time (seconds): 0.10\n Maximum resident set size (kbytes): 4096\n', 'linux');
  assert.equal(linux.peakRssBytes, 4194304);
  assert.throws(() => approvalResources('', 'darwin'));
  assert.throws(() => approvalResources('user 0.3\nsys 0.1\n', 'linux'));
});


test('approval work allowance rejects one extra digest or helper independently of observations', () => {
  const boundaries = 3;
  const fixedAndBoundaryWork = 32 + 2 * boundaries;
  const counts = {pid: 1, sqlPrepares: 300, currentCalls: 50, externalBoundaries: boundaries,
    unexpectedHelperRevalidations: 0, hostAuthorizations: 0, adoptionDigests: fixedAndBoundaryWork,
    materialAdmissions: 1, sourceValidations: fixedAndBoundaryWork, memberHashes: 11};
  assertApprovalCallCounts(counts, 1);
  assert.throws(() => assertApprovalCallCounts({...counts, adoptionDigests: fixedAndBoundaryWork + 1}, 1),
    /adoption validation amplified/u);
  assert.throws(() => assertApprovalCallCounts({...counts, sourceValidations: fixedAndBoundaryWork + 1}, 1),
    /Source validation amplified/u);
  assert.throws(() => assertApprovalCallCounts({...counts, unexpectedHelperRevalidations: 1}, 1),
    /repeated immutable/u);
});

test('approval phases require complete actual boundaries and retain inclusive durations separately', () => {
  const rows = [5, 7, 32, 33, 34, 35, 36, 37, 38].map(tag => ({tag, name: 'synthetic policy fixture',
    begins: 1, ends: 1, active: 0, overlap: 0, unmatched_end: 0, inclusive_ns: 10, exclusive_ns: 2, sql_prepares: 3, current_calls: 2}));
  const record = () => ({stderr: rows.map(row => 'ACTQL_NATIVE_PHASE ' + JSON.stringify(row)).join('\n')});
  assert.equal(approvalPhases(record()).length, 9);
  rows[0].active = 1;
  assert.equal(approvalPhases(record(), {requireCompleted: false}).length, 9, 'Optional timing precision is not functional acceptance');
  assert.throws(() => approvalPhases(record()), /unfinished/u);
  rows.shift();
  assert.throws(() => approvalPhases(record()), /incomplete/u);
});

function signingMethod(source, owner, name) {
  const signature = new RegExp('(?:pub )?fn ' + owner + '::' + name + '\\(');
  const start = source.search(signature);
  assert(start >= 0, `Missing actual ${owner}::${name}`);
  const end = source.indexOf('\n///|', start);
  return source.slice(start, end < 0 ? source.length : end);
}

// Count the actual successful Source call path, not runtime Journal work or
// an authority fixture. Every independent entry keeps its own full traversal.
function verifiedWireTraversals(caller, signing) {
  const walk = body => [...body.matchAll(/\b(?:self|signing)\.(sign_once|sign_and_admit_original_resolution|admit_original_resolution|admit_verified_resolution_in_same_call|original_verified_resolution)\(/gu)]
    .reduce((count, [, name]) => count + (name === 'original_verified_resolution' ? 1
      : walk(signingMethod(signing, 'NativeLocalInitialHostAttestationSigning', name))), 0);
  return walk(signingMethod(caller, 'NativeLocalSavedEffectReview', 'resolve_initial_original'));
}

test('same original-read signing handoff traverses verified wire once while independent admission stays full', () => {
  const caller = readFileSync(new URL('../src/platform_native/client_host/local_saved_effect_resolution.mbt', import.meta.url), 'utf8');
  const signing = readFileSync(new URL('../src/platform_native/client_host/local_initial_host_attestation_signing.mbt', import.meta.url), 'utf8');
  assert.equal(verifiedWireTraversals(caller, signing), 1,
    'The successful actual caller must not discard and reread the same verified wire');
  const repeated = caller.replace('signing.sign_and_admit_original_resolution()',
    'signing.sign_once(); signing.admit_original_resolution()');
  assert.notEqual(repeated, caller);
  assert.equal(verifiedWireTraversals(repeated, signing), 2,
    'Restoring the former actual call chain must expose both full traversals');
  const independent = signingMethod(signing, 'NativeLocalInitialHostAttestationSigning', 'admit_original_resolution');
  assert.equal([...independent.matchAll(/self\.original_verified_resolution\(/gu)].length, 1);
});

test('same-read wire handoff preserves full signer history current verifier and Resolution CAS bodies', () => {
  const source = readFileSync(new URL('../src/platform_native/client_host/local_initial_host_attestation_signing.mbt', import.meta.url), 'utf8');
  const method = name => signingMethod(source, 'NativeLocalInitialHostAttestationSigning', name);
  const digest = value => createHash('sha256').update(value).digest('hex');
  assert.equal(digest(method('sign_once')), '2186fa4cf279c1846342345a6e067d1a261ec2c9f2f628dff1ebb81e28c5e664',
    'Claim, physical signer, signature store and before/after current gates remain exact');
  assert.equal(digest(method('original_verified_resolution')), 'a7e55b62ba61ef4bb1a29691ef37d404850697f982cbdf5cfaba89a5378ce062',
    'Independent history reads retain both current observations and complete wire equality');
  const admission = method('admit_verified_resolution_in_same_call');
  assert.equal(digest(admission.slice(admission.indexOf('  let preparation = self.preparation'))),
    'ce1853531cd3dc9e878ea99e54a2bf13ad3e18b3f74a34a3cb5f2f35e1b322a2',
    'Full mutable/current callbacks, real signature verifier and original Resolution CAS remain exact');
  const closed = method('sign_and_admit_original_resolution');
  assert.match(closed, /original_read is Some\(_\)/u);
  assert.match(closed, /approval_scope is SavedApproval\(_\)/u);
  assert.match(closed, /let wire = match self\.sign_once\(\)/u);
  assert.match(closed, /Err\(issue\) => return Err\(issue\)/u);
  assert.match(closed, /self\.admit_verified_resolution_in_same_call\(wire\)/u);
  assert.doesNotMatch(closed, /pub fn|@env\.now|journal\.transaction|self\.signature\s*=|self\.admitted_record\s*=/u);
});

function initialPhysicalCurrentTraversals(caller, signing, keys) {
  const independent = signing.slice(signing.indexOf('fn prepare_local_initial_resolution_physical('),
    signing.indexOf('\n///|', signing.indexOf('fn prepare_local_initial_resolution_physical(')));
  const initialBranch = signingMethod(keys, 'NativeLocalReviewerProofKey', 'require_signing_key_scope');
  const full = [...independent.matchAll(/\.require_signing_key_scope\(/gu)].length *
    [...initialBranch.matchAll(/key\.require_current\(/gu)].length;
  const entry = signingMethod(caller, 'NativeLocalReviewerProofMaterials', 'prepare_initial_original_signing');
  if (entry.includes('prepare_local_initial_resolution_physical(current.key, scope)')) return full;
  assert.match(entry, /current\.prepare_original_physical\(\)/u);
  const closed = signingMethod(signing, 'NativeLocalInitialSigningCurrent', 'prepare_original_physical');
  assert.match(closed, /self\.key\.require_signing_scope_after_current\(self\.scope\)/u);
  const fields = signingMethod(keys, 'NativeLocalInitialReviewerSigningKey', 'require_signing_scope_after_current');
  return [...(closed + fields).matchAll(/\.require_current\(/gu)].length;
}

test('initial physical constructor does not repeat the immediately completed key current traversal', () => {
  const signing = readFileSync(new URL('../src/platform_native/client_host/local_initial_resolution_signing.mbt', import.meta.url), 'utf8');
  const keys = readFileSync(new URL('../src/platform_native/client_host/local_initial_reviewer_proof_key.mbt', import.meta.url), 'utf8');
  assert.equal(initialPhysicalCurrentTraversals(signing, signing, keys), 0,
    'The closed constructor must use the same just-current key and original scope');
  const repeated = signing.replace('current.prepare_original_physical()',
    'prepare_local_initial_resolution_physical(current.key, scope)');
  assert.notEqual(repeated, signing);
  assert.equal(initialPhysicalCurrentTraversals(repeated, signing, keys), 1,
    'Restoring the old actual constructor call must expose the redundant full traversal');
});

test('initial physical constructor retains independent admission fields physical child and post-callback fences', () => {
  const signing = readFileSync(new URL('../src/platform_native/client_host/local_initial_resolution_signing.mbt', import.meta.url), 'utf8');
  const keys = readFileSync(new URL('../src/platform_native/client_host/local_initial_reviewer_proof_key.mbt', import.meta.url), 'utf8');
  const current = readFileSync(new URL('../src/platform_native/client_host/local_initial_resolution_signing_current.mbt', import.meta.url), 'utf8');
  const digest = value => createHash('sha256').update(value).digest('hex');
  const independent = signingMethod(keys, 'NativeLocalReviewerProofKey', 'require_signing_key_scope');
  const fields = signingMethod(keys, 'NativeLocalInitialReviewerSigningKey', 'require_signing_scope_after_current');
  const originalFields = fields.slice(fields.indexOf('  let facts = self.fields'))
    .replace(/\n\}\n?$/u, '')
    .replaceAll('self.finish_original_projection()', 'key.finish_original_projection()')
    .replaceAll('self.fields', 'key.fields')
    .split('\n').map(line => '    ' + line).join('\n');
  const restored = independent.replace('      key.require_signing_scope_after_current(scope)\n    }\n  }\n}',
    originalFields + '\n    }\n  }\n}');
  assert.equal(digest(restored), 'f7a94c817d726b960b77053b0f52d08d8a786d4dcb18a84d8adfdeeab5864542',
    'The independent full admission reconstructs its original current, every field and physical projection check');
  const physicalStart = signing.indexOf('fn prepare_local_initial_resolution_library(');
  const physicalEnd = signing.indexOf('\n///|', physicalStart);
  assert.equal(digest(signing.slice(physicalStart, physicalEnd).split('  let public_key')[1]),
    'fe21f9a20735b19f6d7498a4af496a2a695716f1f5759bc83f649f7e919c8634');
  const constructor = signingMethod(signing, 'NativeLocalReviewerProofMaterials', 'prepare_initial_original_signing');
  assert.equal(digest(constructor.slice(0, constructor.indexOf('  let physical'))),
    '84967ca08196923839634430f42b12e9276cba5fb490ac369584c185b3404e1c',
    'Only original field reads and the previous child lifetime check separate the current constructor and handoff');
  assert.equal([...signing.matchAll(/\.prepare_original_physical\(/gu)].length, 1,
    'The handoff is used only by this closed constructor, never a later retained-current view');
  assert.equal(digest(constructor.split('  let original :')[1]),
    '2dee0a5ca99fcb91ced443bbb595e9da3bef4c229668f53a624726c3a3ed3fbd',
    'The same Library child is retained before the unchanged post-constructor current callback');
  assert.equal(digest(signingMethod(current, 'NativeLocalReviewerProofMaterials', 'initial_signing_current_after_original_scope')),
    '5781d5881a46f0613c29e550f1a67d43b396e451638883e26e0ed1940f59519a',
    'Fresh role authority, full material current and original subject terminal checks stay exact');
  const closed = signingMethod(signing, 'NativeLocalInitialSigningCurrent', 'prepare_original_physical');
  assert.match(closed, /approval_scope is SavedApproval\(saved\)/u);
  assert.match(closed, /original_read is Some\(\(capture, _\)\)/u);
  assert.match(closed, /physical_equal\(saved\.capture, capture\) else \{\n    return prepare_local_initial_resolution_physical\(self\.key, self\.scope\)/u,
    'Unscoped, Resident and missing/foreign original Reads keep their full independent entry');
  assert.match(closed, /prepare_local_initial_resolution_library\(self\.key, self\.scope\)/u);
  assert.doesNotMatch(closed, /pub fn|\.now|\.current\(|journal\.|\.require_current\(|\.scope\s*=|\.key\s*=/u);
});

test('initial host restoration consumes the same admitted subject while preserving full post-IO current', () => {
  const source = readFileSync(new URL('../src/platform_native/client_host/local_initial_host_signing_original.mbt', import.meta.url), 'utf8');
  const constructor = signingMethod(source, 'NativeLocalHostConnection', 'restore_initial_host_signing_original');
  // Both field readers use the same complete with-subject decoder. Count the
  // selected scoped expression, rather than treating its legacy fallback as
  // another read on that path. These are Source calls, not runtime SQL counts.
  const assignment = constructor.slice(constructor.indexOf('    signing_subject:'));
  const scopedReads = assignment.startsWith('    signing_subject: if signing_original is Some(_) {\n      subject\n    } else {')
    ? 0 : [...assignment.matchAll(/read_initial_host_signing_subject\(/gu)].length;
  assert.equal(1 + scopedReads, 1, 'The admitted scoped subject must not be discarded and authenticated again');
  assert.match(constructor, /let \(fields, subject\) = match\n    read_local_initial_host_signing_control_with_subject\(/u);
  assert.match(constructor, /let signing_original = if reviewer\.original_read is Some\(_\)/u);
  assert.equal([...assignment.matchAll(/read_initial_host_signing_subject\(/gu)].length, 1,
    'The independent legacy/unscoped branch keeps its complete subject read');
  assert.match(constructor, /root\.restore_private_file_projection\(fields\.exported\)/u);
  assert.match(constructor, /original\.require_current\(\)\.map\(_ => original\)/u,
    'Physical projection construction is followed by the complete fresh current read');
  const controlStart = source.indexOf('fn read_local_initial_host_signing_control_with_subject(');
  const digest = value => createHash('sha256').update(value).digest('hex');
  assert.equal(digest(source.slice(controlStart, source.indexOf('\n///|', controlStart))),
    'bc26137008e37267832cda58e328a789acbd94456f641216c816b9da6c6159d8',
    'The full authenticated original control/issuer/policy admission remains exact');
  const current = signingMethod(source, 'NativeLocalInitialHostSigningOriginal', 'require_current');
  assert.equal(digest(current.slice(current.indexOf('  if fields.exported'))),
    'd85bcc3daebd7a9865a4744e0fee8f6b34c72322632263b64298f35cfa05ce5b',
    'All Host identity, subject, physical generation and final current fences remain exact');
});

test('Host key current consumes the original control fields without admitting both role packets again', () => {
  const reviewer = readFileSync(new URL('../src/platform_native/client_host/local_initial_signing_original.mbt', import.meta.url), 'utf8');
  const host = readFileSync(new URL('../src/platform_native/client_host/local_initial_host_signing_original.mbt', import.meta.url), 'utf8');
  const current = signingMethod(host, 'NativeLocalInitialHostSigningOriginal', 'require_current');
  const retainedEntry = signingMethod(reviewer, 'NativeLocalInitialSigningOriginal', 'require_current_after_host_binding');
  const control = retainedEntry.includes('self.read_current_control_after_host_binding()')
    ? signingMethod(reviewer, 'NativeLocalInitialSigningOriginal', 'read_current_control_after_host_binding')
    : retainedEntry;
  const admissions = [...control.matchAll(/read_local_initial_signing_control(?:_with_host_key)?\(/gu)].length;
  assert.equal(admissions, 1, 'Original current still authenticates the complete control exactly once');
  const scopedStart = current.indexOf('  let (fields, subject) = if self.reviewer.original_read is Some(_) {');
  const scopedEnd = current.indexOf('\n  } else {', scopedStart);
  const scoped = scopedStart < 0 ? current : current.slice(scopedStart, scopedEnd);
  const reviewerReads = [...scoped.matchAll(/self\.reviewer\.(?:require_current|read_current_control)\(/gu)].length * admissions;
  const repeatedReads = [...scoped.matchAll(/read_local_initial_host_signing_control_with_subject\(/gu)].length;
  assert.equal(reviewerReads + repeatedReads, 1,
    'The immediately admitted Host fields and subject must survive the Reviewer current handoff');
  assert(scopedStart >= 0 && scopedEnd > scopedStart);
  const legacy = current.slice(scopedEnd, current.indexOf('  if fields.exported'));
  assert.match(legacy, /self\.reviewer\.require_current\(\)/u);
  assert.match(legacy, /read_local_initial_host_signing_control_with_subject\(/u,
    'Missing original Read retains the independent complete entry');
  assert.doesNotMatch(scoped, /read_local_initial_host_signing_control|\.now\(|authorize\(|\.transaction\(/u);
  assert.match(scoped, /fields\.policy\.cid\(\) == reviewer_fields\.policy\.cid\(\)/u);
  assert.match(scoped, /fields\.issuer == reviewer_fields\.issuer/u);
  const restored = control
    .replace(/fn NativeLocalInitialSigningOriginal::read_current_control_after_host_binding\([\s\S]*?\n  guard self\.host/u,
      'fn NativeLocalInitialSigningOriginal::require_current_after_host_binding(\n  self : NativeLocalInitialSigningOriginal,\n) -> Result[Unit, NativeLocalAdoptionIssue] {\n  guard self.host')
    .replace('read_local_initial_signing_control_with_host_key(', 'read_local_initial_signing_control(')
    .replace('is Ok(Some((fields, host_fields)))', 'is Ok(Some(fields))')
    .replace('self.check_host_current().map(_ => (fields, host_fields))', 'self.check_host_current()');
  assert.equal(createHash('sha256').update(restored).digest('hex'),
    '198284f47ac20e744033e508f4b231084eae327f7c2c4e34836861d63e974e68',
    'Control admission and every original Reviewer custody/separation/projection/current check stay exact');
});

test('finite read statement keeps exact row admission and private selected ABI bindings', () => {
  const source = readFileSync(new URL('../src/platform_native/sqlite/sqlite_stub.c', import.meta.url), 'utf8');
  const start = source.indexOf('static int32_t actql_database_read(');
  const row = source.indexOf('  int32_t result = actql_bind_key(', start);
  const end = source.indexOf('  int finalize_code', row);
  assert.equal(createHash('sha256').update(source.slice(row, end)).digest('hex'),
    '68d5f9ee07f0d524a8cd4a17eedbb7561bee5df9be85d40aa449f3e365de0cb1',
    'Both original bindings, step, extent/revision/type and all row/body limits stay exact');
  assert.match(source, /bool reusable = !exact_extent && database->library->reset != NULL &&\n    database->library->clear_bindings != NULL/u);
  assert.equal([...source.matchAll(/sqlite3_stmt \*record_read_statement;/gu)].length, 1);
  const api = readFileSync(new URL('../packages/python-local-runtime/native/sqlite-component/api.h', import.meta.url), 'utf8');
  const selected = readFileSync(new URL('../src/platform_native/sqlite/sqlite_selected_component.inc', import.meta.url), 'utf8');
  assert.match(api, /#define ACTQL_SQLITE_COMPONENT_ABI 3/u);
  assert.match(selected, /api->abi != ACTQL_SQLITE_COMPONENT_ABI/u);
  assert.match(selected, /api->bytes != sizeof\(\*api\)/u);
  for (const port of ['reset', 'clear_bindings']) {
    assert(selected.includes(`api->${port} == NULL`));
    assert(selected.includes(`(void *)api->${port}`), 'Every added port retains actual module-origin validation');
    assert(selected.includes(`library->${port} = api->${port};`));
    assert(source.includes(`!ACTQL_LOAD(library, ${port}, "sqlite3_${port}")`));
  }
});

test('closed Reviewer snapshot reuses only its admitted original record without another read-only transaction', () => {
  const source = readFileSync(new URL('../src/platform_native/client_host/local_reviewer_proof_materials.mbt', import.meta.url), 'utf8');
  const start = source.indexOf('fn local_reviewer_proof_snapshot(');
  const entry = source.slice(start, source.indexOf('\n///|', start));
  const transactions = (active, admitted, same) => active && admitted && same &&
    entry.includes('return local_reviewer_proof_snapshot_from_admitted_record(') ? 0
      : [...entry.matchAll(/journal\.transaction\(/gu)].length;
  assert.equal(transactions(true, true, true), 0,
    'The existing closed operation must not begin and commit another transaction just to project its admitted record');
  for (const facts of [[false, true, true], [true, false, true], [true, true, false]])
    assert.equal(transactions(...facts), 1, 'Cold, invalidated and foreign paths retain their complete owned transaction');
  assert.match(entry, /journal\.check_transaction_context\(\)/u);
  const after = entry.slice(entry.indexOf('journal.check_transaction_context()'));
  for (const condition of ['journal.operation_active', '!journal.fenced', '!journal.transaction_active',
    '!journal.publication_read_locked', 'journal.operation_record is Some(record)']) assert(after.includes(condition));
  assert.match(after, /@host\.client_request_identity_relation\(record\.request, request\) ==\n      @host\.SameRequest/u);
  const project = source.indexOf('fn local_reviewer_proof_snapshot_from_admitted_record(');
  const body = source.indexOf('  if @host.client_request_identity_relation', project);
  assert.equal(createHash('sha256').update(source.slice(body, source.indexOf('\n///|', body))).digest('hex'),
    '9336a0966131f03eb5edf76e766cc825c8e735408983ed055395a79c6aed3f13',
    'All original Request/definition/checkpoint/kind/Run/status/cancellation/Unknown facts remain exact');
});

test('same original Checkpoint metadata projects its live record without an extra transaction', () => {
  const source = readFileSync(new URL('../src/platform_native/client_host/local_checkpoint_lookup.mbt', import.meta.url), 'utf8');
  const entry = signingMethod(source, 'NativeLocalHostConnection', 'lookup_submitted_checkpoint_metadata_with_operations');
  const fast = entry.indexOf('  // Same admitted record after current');
  assert(fast >= 0, 'The same-record metadata path must avoid the original unconditional read transaction');
  const prefix = entry.slice(0, entry.indexOf('  let project ='));
  assert.equal(createHash('sha256').update(prefix).digest('hex'),
    '39f323df5f2729c32dc8fdaebca423d29ec388c172fb164e55876c6deacbb96d',
    'Original role selection, monotonic epoch/CAS and Submission/Run identity admission stay exact');
  const fallback = entry.indexOf('  self.journal\n  .transaction_with_reads(', fast);
  assert(fallback > fast);
  const closed = entry.slice(fast, fallback);
  assert.doesNotMatch(closed, /\.transaction(?:_with_reads)?\(/u);
  assert.equal([...closed.matchAll(/authority\.current_for\(journal, request\)/gu)].length, 1,
    'Pure projection has no later callback requiring another Account/current traversal');
  assert.equal([...closed.matchAll(/journal\.check_transaction_context\(reads~\)/gu)].length, 1);
  const current = closed.indexOf('authority.current_for(journal, request)');
  const select = closed.indexOf('journal.operation_record is Some(record)');
  const project = closed.indexOf('return project(record)');
  assert(closed.indexOf('journal.check_transaction_context(reads~)') < current && current < select && select < project,
    'Actual physical Read exchange and current precede same-record selection and pure projection');
  assert.doesNotMatch(closed.slice(project), /current_for|check_transaction_context|\.retained\(/u);
  const projection = entry.slice(entry.indexOf('    let run_definition_cid ='),
    entry.indexOf('\n  }\n  // Same admitted record after current'));
  assert.equal(createHash('sha256').update(projection.split('\n').map(line => line ? '    ' + line : '').join('\n')).digest('hex'),
    'b05f1f59e7f6278dd75fb518c8018a02311e013b88099947506c0d7f941e6ff7',
    'The exact original immutable five-field projection introduces no callback or I/O');
  const contracts = readFileSync(new URL('../src/run_publication/contracts.mbt', import.meta.url), 'utf8');
  assert.match(contracts, /pub fn publication_contract_identity\(contract : PublicationContract\) -> String \{\n  contract\.identity\n\}/u);
  for (const guard of ['journal.operation_active', '!journal.fenced', '!journal.transaction_active',
    '!journal.publication_read_locked', 'journal.operation_record is Some(record)', '@host.SameRequest'])
    assert(closed.includes(guard));
  const cold = entry.slice(fallback);
  assert.equal([...cold.matchAll(/authority\.current_for\(self\.journal, request\)/gu)].length, 2);
  assert.match(cold, /self\.journal\.retained\(request, reads~\)/u);
  assert.match(cold, /reads~,\n  \)/u);
  for (const [path, expected] of [
    ['local_reviewer_binding.mbt', '709c3b409ce032cf441867898a3d3bac8ab0e2167ec5d9c4256ef2b18fdb07c5'],
    ['local_reviewer_proof_materials.mbt', 'af4737cae23d7e7d320bd96c2d4be5609e43b2236b4fb72440359df833c04508'],
  ]) assert.equal(createHash('sha256').update(readFileSync(new URL('../src/platform_native/client_host/' + path, import.meta.url))).digest('hex'), expected,
    'Existing clock, key generation, OriginalRead, role and revision/cancellation fences stay exact');
});


test('Host grant history authenticates the same control role packets once in its original transaction', () => {
  const host = readFileSync(new URL('../src/platform_native/client_host/local_initial_host_attestation_original.mbt', import.meta.url), 'utf8');
  const entry = signingMethod(host, 'NativeLocalHostConnection', 'check_initial_host_attestation_grant_original_locked');
  const current = entry.includes('self.check_initial_host_attestation_grant_after_submission_locked(')
    ? signingMethod(host, 'NativeLocalHostConnection', 'check_initial_host_attestation_grant_after_submission_locked') : entry;
  const admissions = [...current.matchAll(/read_local_initial_(?:host_)?signing_control(?:_with_host_key)?\(/gu)].length;
  assert.equal(admissions, 1,
    'The Host control reader already authenticates the same Reviewer packet and Host subject');
  assert.match(current, /is Ok\(Some\(\(reviewer, Some\(\(fields, _\)\)\)\)\)/u);
  assert.match(current, /fields\.policy\.cid\(\) == reviewer\.policy\.cid\(\)/u);
  assert.match(current, /fields\.issuer == reviewer\.issuer/u);
  const unchangedTail = current.slice(current.indexOf('  let metadata =')).replace('    file.content_cid == metadata.host_configuration_cid else {\n    return Err(CustodyLost)\n  }\n  // The scope check above already joined this SAME Host/Library/Read. Select\n  // its admitted bytes without another full Source/package walk; the final\n  // physical/current fence after key-generation checks remains below.\n  let body = match capture {\n    Some(owner) => owner.selected_configuration_in_original_read(file.name)\n    None => self.selected_configuration(file.name)\n  }\n  guard body is Ok(body) &&', '    file.content_cid == metadata.host_configuration_cid &&\n    self.selected_configuration(file.name) is Ok(body) &&');
  assert.equal(createHash('sha256').update(unchangedTail).digest('hex'),
    '095c61f6f0edc180e278abcd679320ef2e172917f798702bbbdbf42daf888ddd',
    'All original issue/policy/Account/configuration/key separation/generation and final Host checks stay exact');
});

test('Host grant dispatch forwards its original checked Submission without another epoch traversal', () => {
  const issue = readFileSync(new URL('../src/platform_native/client_host/local_initial_signing_issue_record.mbt', import.meta.url), 'utf8');
  const host = readFileSync(new URL('../src/platform_native/client_host/local_initial_host_attestation_original.mbt', import.meta.url), 'utf8');
  const dispatch = signingMethod(issue, 'NativeLocalHostConnection', 'check_initial_signing_grant_original_locked');
  const independent = signingMethod(host, 'NativeLocalHostConnection', 'check_initial_host_attestation_grant_original_locked');
  const handedOff = dispatch.includes('self.check_initial_host_attestation_grant_after_submission_locked(');
  const continuation = handedOff
    ? signingMethod(host, 'NativeLocalHostConnection', 'check_initial_host_attestation_grant_after_submission_locked') : independent;
  const submissions = body => [...body.matchAll(/self\.check_signing_grant_submission_locked\(/gu)].length;
  assert.equal(submissions(dispatch) + submissions(continuation), 1,
    'One unchanged Submission/epoch admission is sufficient before the pure purpose dispatch');
  assert.equal(submissions(independent), 1, 'The separate Host entry retains its own actual Submission/epoch admission');
  assert.match(independent, /original\.grant is SigningGrant\(grant\) &&\n    original\.initial_issue is Some\(_\)/u);
  assert.match(continuation, /original\.grant is SigningGrant\(grant\) &&\n    original\.initial_issue is Some\(_\)/u);
  assert.doesNotMatch(continuation, /check_signing_grant_submission_locked|\.transaction\(|@env\.now|\.authorize\(/u);
  // Reverse only the already-approved configuration projection before the original whole-body pin.
  const originalConfigurationDispatch = dispatch.replace('    file.content_cid == metadata.host_configuration_cid else {\n    return Err(CustodyLost)\n  }\n  // The scope check above already joined this SAME Host/Library/Read. Select\n  // its admitted bytes without another full Source/package walk; the final\n  // physical/current fence after key-generation checks remains below.\n  let body = match capture {\n    Some(owner) => owner.selected_configuration_in_original_read(file.name)\n    None => self.selected_configuration(file.name)\n  }\n  guard body is Ok(body) &&', '    file.content_cid == metadata.host_configuration_cid &&\n    self.selected_configuration(file.name) is Ok(body) &&');
  assert.equal(createHash('sha256').update(originalConfigurationDispatch.replace('check_initial_host_attestation_grant_after_submission_locked(\n      original,',
    'check_initial_host_attestation_grant_original_locked(\n      original,\n      expected_run,')).digest('hex'),
    'f0dcdc74d816b3cb47f6e2dbfccc060bf93305712b0caf06f58c88bfbd5332fb', 'The dispatcher keeps every original check and every independent Reviewer obligation');
});


test('same original-read grant history selects its admitted configuration without another full binding walk', () => {
  for (const [path, name] of [
    ['local_initial_host_attestation_original.mbt', 'check_initial_host_attestation_grant_after_submission_locked'],
    ['local_initial_signing_issue_record.mbt', 'check_initial_signing_grant_original_locked'],
  ]) {
    const source = readFileSync(new URL('../src/platform_native/client_host/' + path, import.meta.url), 'utf8');
    const method = signingMethod(source, 'NativeLocalHostConnection', name);
    const start = method.indexOf('  let body = match capture {');
    const end = method.indexOf('  guard body is Ok(body)', start);
    const branch = start < 0 ? method : method.slice(start, end);
    const scoped = start < 0 ? branch : branch.slice(0, branch.indexOf('    None =>'));
    const directWalks = [...scoped.matchAll(/self\.(?:selected_configuration|check_binding)\(/gu)].length;
    const terminalWalks = start < 0 ? 0 : [...method.slice(end).matchAll(/self\.check_binding\(/gu)].length;
    assert.equal(directWalks + terminalWalks, 1,
      path + ': scoped configuration is DATA; the original final physical/current fence remains required');
    assert(start >= 0 && end > start);
    assert.match(scoped, /Some\(owner\) => owner\.selected_configuration_in_original_read\(file\.name\)/u);
    assert.match(branch, /None => self\.selected_configuration\(file\.name\)/u,
      'Legacy independent entry retains its complete binding check');
    assert.doesNotMatch(scoped, /Err\(|unwrap_or|pub fn|\.read_callback_active|\.read_facts_valid|\.authorize\(/u);
    assert(method.indexOf('    self.authority_scope_cid(') < start,
      'The existing same Host/Library/Read scope check must precede the projection');
    assert.match(method.slice(end), /body == file\.body &&\n    initial_reviewer_host_configuration\(body\)/u);
    assert.match(method.slice(end), /self\.session\.root\.restore_private_file_projection\(fields\.exported\)/u);
    assert.match(method.slice(end), /self\.check_binding\(\)\.map_err\(_ => CustodyLost\)/u);
  }
  const settings = readFileSync(new URL('../src/platform_native/client_host/local_settings.mbt', import.meta.url), 'utf8');
  const scope = signingMethod(settings, 'NativeLocalHostConnection', 'authority_scope_cid');
  assert.match(scope, /owner\.opening is JournalAcquired\(host\) &&\n      physical_equal\(host, self\) &&\n      physical_equal\(owner\.crypto, crypto\)/u);
  const read = readFileSync(new URL('../src/platform_native/client_host/local_journal_preparation_read.mbt', import.meta.url), 'utf8');
  const projection = signingMethod(read, 'NativeLocalJournalCapture', 'selected_configuration_in_original_read');
  assert.match(projection, /self\.check_current_in_original_read\(\)/u);
  assert.match(projection, /if self\.read_callback_active && self\.read_facts_valid/u);
  assert.match(projection, /Some\(file\) => Ok\(file\.body\)/u);
});
