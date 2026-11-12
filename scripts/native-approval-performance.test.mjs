import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {approvalCallCounts, assertApprovalCallCounts, assessNativeApproval, approvalResources, approvalPhases} from './native-approval-performance.mjs';

const sourceSha = 'a'.repeat(40), fixtureSha256 = 'b'.repeat(64), runnerSha256 = 'c'.repeat(64);
const series = () => ({mode: 'final', sourceSha, fixtureSha256, runnerSha256,
  samples: Array.from({length: 30}, (_, iteration) => ({iteration, sourceSha, fixtureSha256,
    runnerSha256, wallNs: 4000000000, cpuUserUs: 1000, cpuSystemUs: 1000, cpuScope: 'synthetic OS sample', peakRssBytes: 4096, rssScope: 'synthetic OS sample', completed: true, verified: true}))});

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
