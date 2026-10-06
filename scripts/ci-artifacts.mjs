// Offline projections of explicitly selected retained evidence. Never runs an archive.
import {createHash} from 'node:crypto';
import {open} from 'node:fs/promises';
import {constants} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {openArtifactZip} from './ci-artifact-reader.mjs';
import {addTimingEvidence, formatTiming} from './ci-timing.mjs';
import {projectSessionCosts, bindSessionRunnerCosts} from './ci-session-costs.mjs';

const sha = value => createHash('sha256').update(value).digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const stable = value => Array.isArray(value) ? value.map(stable) : object(value) ?
  Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])])) : value;
const fingerprint = value => sha(JSON.stringify(stable(value)));
const pick = (value, keys) => Object.fromEntries(keys.map(key => [key, value?.[key] ?? null]));
const withoutOccurrence = value => { const {id, ...body} = value ?? {}; return body; };
const positive = value => Number.isSafeInteger(value) && value > 0;
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value);
const fullSha = value => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const sum = values => values.reduce((a, b) => a + b, 0);
const targets = ['js', 'wasm', 'native'];
const limits = [
  'Read-only artifact analysis; no execution, cleanup, retention change or merge-readiness conclusion.',
  'Phase values measure action calls, not compiler-only time, build counts, hashing or I/O. Missing splits remain unknown.',
  'Action-duration sums, enclosing capacity duration, job/step wall time and parallel runner totals are different boundaries; they are never added together.',
  'Pre-start delay is not proven queue time. Cache and runner details missing from selected evidence remain unknown.',
  'Failed/cancelled runs retain completed phase evidence but are never completed-green end-to-end samples.',
  'One sample is not a stable speedup estimate. Different source, runner/region, command, workload or campaign scope prevents a causal performance claim.',
  'Logical bytes and ZIP bytes are distinct. Identical-content bytes are deduplication potential, not recoverable disk space or deletion permission.',
  'All files remain protected: known references are re-audit evidence; unrecognized/unresolved references and unreferenced build outputs are unknown-protected.',
  'Session costs reconstruct certificate-bound observations, but offline selection metadata is not authenticated Actions provenance or reuse permission. Enclosing costs are not causal savings.',
];

export function artifactPath(value) {
  if (typeof value !== 'string') throw new Error('Invalid artifact reference');
  const path = value.startsWith('.artifacts/') ? value.slice(11) : value;
  if (!path || /[\\:\x00-\x1f\x7f]/u.test(path) || path.startsWith('/') || path.split('/').some(x => !x || x === '.' || x === '..')) {
    throw new Error('Unsafe artifact reference');
  }
  return path;
}
export function duration(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ?
    {milliseconds: value, reason: null} : {milliseconds: null, reason: value == null ? 'missing-duration' : 'invalid-duration'};
}
function provenance(value, repository) {
  if (!object(value) || value.repository !== repository || !positive(value.runId) || !positive(value.attempt) ||
      !fullSha(value.headSha) || !fullSha(value.executionSha) || !value.workflow || !value.event ||
      !value.status || !value.conclusion || !positive(value.artifact?.id) || !value.artifact.name ||
      !digest(value.artifact.sha256) || !positive(value.artifact.compressedBytes)) throw new Error('Incomplete artifact provenance');
  return structuredClone(value);
}

function observationMap(value) {
  return Object.fromEntries(Object.entries(value ?? {}).map(([target, observation]) => [target, withoutOccurrence(observation)]));
}
function workload(row) {
  return {...pick(row, ['name', 'site', 'anchor', 'original', 'minimal', 'history', 'localMinimal', 'finalCandidates', 'killed']),
    finalObservations: (row.finalObservations ?? []).map(withoutOccurrence),
    replay: observationMap(row.replay), healthy: observationMap(row.healthy)};
}
function phaseRow(campaign, row, phase, target, value, receipts, reason = null) {
  const measured = duration(value);
  return {campaign, mutation: row?.name ?? null, phase, target, ...measured,
    reason: reason ?? measured.reason, milliseconds: reason ? null : measured.milliseconds,
    boundary: 'reported action duration', receipts};
}
function phaseReceipts(executions, phase, target) {
  const suffix = phase === 'search' ? /-search-/u : phase === 'shrink' ? /-shrink-/u : /-(?:fixed|minimal|replay)-/u;
  return executions.filter(e => e.receipt?.target === target && (phase === 'healthy' || suffix.test(e.path ?? '')))
    .map(e => ({path: e.path, digest: e.digest}));
}
export function projectCampaign(report, kind, expectedInventory = {}) {
  const campaign = kind === 'capacity' ? 'capacity' : kind === 'fixed' ? 'fixed' : 'fresh';
  const rows = kind === 'capacity' ? report.mutations : report.results;
  if (!Array.isArray(rows)) throw new Error('Malformed retained campaign');
  const expected = expectedInventory[kind] ?? null;
  const names = rows.map(row => row.name).sort();
  const completeInventory = Array.isArray(expected) && fingerprint(names) === fingerprint([...expected].sort()) && new Set(names).size === names.length;
  const expectedTargets = expectedInventory.targets ?? targets;
  const phases = [], mutations = [], receipts = [];
  let targetComplete = true;
  for (const row of rows) {
    const capacityExecutions = (report.executions ?? []).filter(e => e.path?.includes(`-capacity-${row.name}-`));
    const mutated = row.executions ?? capacityExecutions.filter(e => !e.path.includes('-restored-'));
    const healthy = row.healthyExecutions ?? capacityExecutions.filter(e => e.path.includes('-restored-'));
    if (kind !== 'capacity') receipts.push(...mutated, ...healthy);
    const actualTargets = Object.keys(row.replay ?? {}).sort(), actualHealthy = Object.keys(row.healthy ?? {}).sort();
    const matched = fingerprint(actualTargets) === fingerprint([...expectedTargets].sort()) && fingerprint(actualHealthy) === fingerprint([...expectedTargets].sort());
    targetComplete &&= matched;
    const timing = row.timing ?? row.timings ?? {};
    if (kind !== 'fixed') for (const phase of ['search', 'shrink']) {
      const target = report.explorationTarget ?? (kind === 'capacity' ? 'js' : null);
      phases.push(phaseRow(campaign, row, phase, target, timing[`${phase}Ms`], phaseReceipts(mutated, phase, target), target ? null : 'unknown-exploration-target'));
    }
    for (const [phase, field, alternative] of [['mutated', 'mutatedReplayMs', 'replayMs'], ['healthy', 'restoredReplayMs', 'restoredMs']]) {
      for (const target of new Set([...expectedTargets, ...Object.keys(timing[field] ?? timing[alternative] ?? {})])) {
        phases.push(phaseRow(campaign, row, phase, target, (timing[field] ?? timing[alternative])?.[target],
          phaseReceipts(phase === 'healthy' ? healthy : mutated, phase, target),
          !expectedTargets.includes(target) || !(target in (phase === 'healthy' ? row.healthy ?? {} : row.replay ?? {})) ? 'target-mismatch' : null));
      }
    }
    mutations.push({name: row.name, site: row.site, anchor: row.anchor ?? null,
      originalDigest: row.originalDigest ?? null, mutatedDigest: row.mutatedDigest ?? null,
      targets: actualTargets, healthyTargets: actualHealthy, targetMatch: matched,
      workloadSha256: fingerprint(workload(row)), minimaSha256: fingerprint(row.minimal ?? null),
      shrinkHistorySha256: fingerprint(row.history ?? null), finalCandidateCount: row.finalCandidates?.length ?? null,
      attemptedCandidateCount: row.history ? sum(row.history.map(x => x.attempted ?? 0)) : null,
      oracleSha256: fingerprint({replay: observationMap(row.replay), healthy: observationMap(row.healthy), final: (row.finalObservations ?? []).map(withoutOccurrence)}),
      enclosingDuration: kind === 'capacity' ? duration(row.durationMs) : null});
  }
  if (kind === 'capacity') {
    receipts.push(...(report.executions ?? []));
    for (const target of expectedTargets) phases.push(phaseRow(campaign, null, 'normal', target, report.timings?.[target], (report.executions ?? []).filter(e => e.path?.endsWith(`-capacity-normal-${target}.json`)).map(e => pick(e, ['path', 'digest']))));
    for (const boundary of ['-1', '0', '1']) for (const target of expectedTargets) {
      phases.push(phaseRow(campaign, {name: `boundary:${boundary}`}, 'boundary', target, report.timings?.boundaries?.[boundary]?.[target], (report.executions ?? []).filter(e => e.path?.endsWith(`-capacity-boundary-${boundary}-${target}.json`)).map(e => pick(e, ['path', 'digest']))));
    }
  }
  const aggregate = new Map();
  for (const phase of phases) {
    const key = `${phase.phase}:${phase.target}`;
    if (!aggregate.has(key)) aggregate.set(key, {phase: phase.phase, target: phase.target, expectedCount: 0, measuredCount: 0, knownActionMilliseconds: 0});
    const group = aggregate.get(key); group.expectedCount++;
    if (phase.milliseconds !== null) { group.measuredCount++; group.knownActionMilliseconds = group.knownActionMilliseconds === null ? null : group.knownActionMilliseconds + phase.milliseconds;
      if (!Number.isFinite(group.knownActionMilliseconds)) group.knownActionMilliseconds = null; }
  }
  for (const group of aggregate.values()) group.actionMilliseconds = group.knownActionMilliseconds !== null && group.expectedCount === group.measuredCount && completeInventory && targetComplete ? group.knownActionMilliseconds : null;
  return {campaign, revision: report.revision, sourceDigest: report.source?.digest ?? null, toolchain: report.toolchain ?? null,
    seed: report.seed ?? null, explorationTarget: report.explorationTarget ?? (kind === 'capacity' ? 'js' : null), searchDomain: report.searchDomain ?? null,
    inventory: names, expectedInventory: expected, inventoryComplete: completeInventory, targetComplete,
    sourceWorkloadSha256: fingerprint(mutations.map(row => pick(row, ['name', 'originalDigest', 'mutatedDigest']))),
    workloadSha256: fingerprint({seed: report.seed ?? null, meaning: report.meaning ?? report.shrinkMeaning ?? null,
      searchDomain: report.searchDomain ?? null, corpus: kind === 'capacity' ? report.corpus : null,
      search: kind === 'capacity' ? report.search : null, mutations: mutations.map(row => row.workloadSha256)}),
    mutations, phases, aggregates: [...aggregate.values()], receipts};
}

async function resolveReceipts(campaigns, zip) {
  const seen = new Map(), references = [], commands = new Set(), errors = [];
  let occurrences = 0, duplicateOccurrences = 0, caseObservations = 0;
  for (const campaign of campaigns) {
    for (const execution of campaign.receipts) {
      occurrences++;
      let path;
      try { path = artifactPath(execution.path); } catch { errors.push({reason: 'unsafe-receipt-reference'}); continue; }
      if (!digest(execution.digest) || !object(execution.receipt) || sha(JSON.stringify(execution.receipt)) !== execution.digest) {
        errors.push({path, reason: 'receipt-digest-mismatch'}); continue;
      }
      const archivesDigest = fingerprint(execution.capacityArchives ?? null);
      const previous = seen.get(path);
      if (previous) {
        duplicateOccurrences++;
        if (previous.digest !== execution.digest || previous.archivesDigest !== archivesDigest) errors.push({path, reason: 'conflicting-duplicate-receipt'});
        continue;
      }
      seen.set(path, {digest: execution.digest, archivesDigest});
      let receipt;
      try { receipt = await zip.json(path); }
      catch { errors.push({path, reason: 'receipt-unavailable-or-invalid'}); continue; }
      if (!digest(execution.digest) || sha(JSON.stringify(receipt)) !== execution.digest ||
          (!object(execution.receipt) || sha(JSON.stringify(execution.receipt)) !== execution.digest)) { errors.push({path, reason: 'receipt-digest-mismatch'}); continue; }
      if (!targets.includes(receipt.target) || !Array.isArray(receipt.command) || !Array.isArray(receipt.cases)) {
        errors.push({path, reason: 'malformed-receipt'}); continue;
      }
      if (!receipt.cases.length) {
        errors.push({path, reason: 'empty-receipt-cases'}); continue;
      }
      const targetFlag = receipt.command.indexOf('--target');
      if (targetFlag >= 0 && receipt.command[targetFlag + 1] !== receipt.target) errors.push({path, reason: 'receipt-command-target-mismatch'});
      if (receipt.exit !== 0) errors.push({path, reason: 'nonzero-or-missing-receipt-exit'});
      caseObservations += receipt.cases.length;
      commands.add(JSON.stringify({target: receipt.target, command: receipt.command, compiler: receipt.compiler ?? null}));
      references.push({from: path, path, kind: 'receipt', digest: execution.digest, canonical: true});
      for (const [field, hashField] of [['sourcePath', 'sourceDigest'], ['fixturePath', 'fixtureDigest'], ['inputPath', 'inputDigest'], ['logPath', 'logDigest']]) {
        references.push({from: path, path: receipt[field], digest: receipt[hashField], kind: field, canonical: field === 'sourcePath'});
      }
      for (const [buildPath, hash] of Object.entries(receipt.artifacts ?? {})) {
        const retained = execution.capacityArchives?.[buildPath] ?? receipt.archives?.[buildPath];
        references.push({from: path, path: retained ?? null, originalPath: buildPath, digest: hash, kind: 'executable'});
      }
    }
    delete campaign.receipts;
  }
  return {uniqueReceipts: seen.size, verifiedReceiptIdentities: references.filter(r => r.kind === 'receipt').map(r => ({path: r.path, digest: r.digest})), occurrences, duplicateOccurrences, caseObservations,
    commands: [...commands].sort().map(JSON.parse), references, errors};
}

export async function inventoryStorage(zip, references = []) {
  const files = [], byPath = new Map(), byDigest = new Map(), duplicates = [], categories = {};
  for (const entry of zip.entries) {
    const sha256 = await zip.digest(entry.path);
    const file = {...entry, sha256, referencedBy: [], protection: 'unknown-protected',
      category: /(?:\/binaries\/|\.(?:exe|wasm|js|cjs|mjs)$)/u.test(entry.path) ? 'executable' :
        /\.log$/u.test(entry.path) ? 'log' : /\.json$/u.test(entry.path) ? 'other' : 'other'};
    files.push(file); byPath.set(file.path, file);
    if (!byDigest.has(sha256)) byDigest.set(sha256, []);
    byDigest.get(sha256).push(file);
  }
  const resolved = [], unresolved = [];
  for (const reference of references) {
    let path = null;
    try { if (reference.path !== null) path = artifactPath(reference.path); }
    catch { unresolved.push({...reference, reason: 'unsafe-reference'}); continue; }
    const selected = path ? [byPath.get(path)].filter(Boolean) : (byDigest.get(reference.digest) ?? []);
    if (!selected.length || !digest(reference.digest)) { unresolved.push({...reference, reason: 'missing-reference'}); continue; }
    let valid = true;
    for (const file of selected) {
      if (reference.canonical) {
        try {
          const data = await zip.json(file.path);
          valid &&= sha(JSON.stringify(reference.kind === 'sourcePath' ? data.sources : data)) === reference.digest;
        } catch { valid = false; }
      } else valid &&= file.sha256 === reference.digest;
    }
    if (!valid) { unresolved.push({...reference, reason: 'reference-digest-mismatch'}); continue; }
    for (const file of selected) {
      file.referencedBy.push(reference.from); file.protection = 'required-for-re-audit';
      if (reference.kind === 'receipt') file.category = 'receipt';
      if (reference.kind === 'executable') file.category = 'executable';
    }
    resolved.push({...reference, paths: selected.map(file => file.path), resolution: path ? 'exact-retained-path' : 'content-only-original-path-unretained'});
  }
  for (const file of files) {
    file.referencedBy = [...new Set(file.referencedBy)].sort();
    const category = categories[file.category] ??= {files: 0, logicalBytes: 0, zipMemberCompressedBytes: 0, referencedFiles: 0, referencedBytes: 0};
    category.files++; category.logicalBytes += file.bytes; category.zipMemberCompressedBytes += file.compressedBytes;
    if (file.referencedBy.length) { category.referencedFiles++; category.referencedBytes += file.bytes; }
  }
  for (const [sha256, members] of byDigest) if (members.length > 1) duplicates.push({sha256, logicalBytesEach: members[0].bytes,
    paths: members.map(file => file.path), identicalContentExtraLogicalBytes: members[0].bytes * (members.length - 1),
    protected: true, referenced: members.some(file => file.referencedBy.length > 0)});
  return {compressedArtifactBytes: zip.compressedBytes, logicalFileBytes: sum(files.map(file => file.bytes)),
    categories, files, references: {resolved, unresolved}, duplicateGroups: duplicates,
    identicalContentExtraLogicalBytes: sum(duplicates.map(group => group.identicalContentExtraLogicalBytes)),
    recoverableDiskBytes: null, deletionCandidates: [], regeneration: 'Not established by content duplication or a build-output path; unknown files stay protected.'};
}

export function compareArtifactSamples(samples) {
  const comparisons = [];
  for (let i = 0; i < samples.length; i++) for (let j = i + 1; j < samples.length; j++) {
    const left = samples[i], right = samples[j];
    for (const a of left.campaigns) {
      const b = right.campaigns.find(x => x.campaign === a.campaign);
      if (!b) { comparisons.push({left: left.id, right: right.id, campaign: a.campaign, comparable: false, differences: ['missing-campaign']}); continue; }
      const dimensions = sample => ({...pick(sample.provenance, ['repository', 'workflow', 'workflowPath', 'event', 'attempt', 'headSha', 'executionSha', 'status', 'conclusion', 'runner', 'cacheState']),
        commands: sample.receipts.commands});
      const leftDimensions = {...dimensions(left), toolchain: a.toolchain, inventory: a.inventory, workloadSha256: a.workloadSha256, sourceWorkloadSha256: a.sourceWorkloadSha256};
      const rightDimensions = {...dimensions(right), toolchain: b.toolchain, inventory: b.inventory, workloadSha256: b.workloadSha256, sourceWorkloadSha256: b.sourceWorkloadSha256};
      const differences = Object.keys(leftDimensions).filter(key => fingerprint(leftDimensions[key]) !== fingerprint(rightDimensions[key]));
      if (left.provenance.runId === right.provenance.runId && left.provenance.attempt === right.provenance.attempt) differences.push('same-execution-not-independent-samples');
      if (!a.inventoryComplete || !b.inventoryComplete) differences.push('incomplete-inventory');
      if (!a.targetComplete || !b.targetComplete) differences.push('target-mismatch');
      if (a.phases.some(x => x.milliseconds === null) || b.phases.some(x => x.milliseconds === null) || a.aggregates.some(x => x.actionMilliseconds === null) || b.aggregates.some(x => x.actionMilliseconds === null)) differences.push('incomplete-phase-timing');
      if (left.storage.references.unresolved.length || right.storage.references.unresolved.length) differences.push('unresolved-custody-references');
      if (!left.selectedEvidenceComplete || !right.selectedEvidenceComplete) differences.push('selected-evidence-incomplete');
      if (left.receipts.errors.length || right.receipts.errors.length) differences.push('receipt-integrity');
      if ([left, right].some(x => x.provenance.status !== 'completed' || x.provenance.conclusion !== 'success')) differences.push('not-two-green-samples');
      if ([left, right].some(x => x.provenance.cacheState == null || x.provenance.cacheState === 'unknown' || !x.provenance.runner?.region)) differences.push('unknown-runner-or-cache');
      comparisons.push({left: left.id, right: right.id, campaign: a.campaign, comparable: differences.length === 0,
        differences, sampleCounts: {left: 1, right: 1}, leftDimensions, rightDimensions,
        phaseChanges: a.aggregates.map(before => {
          const after = b.aggregates.find(x => x.phase === before.phase && x.target === before.target);
          return {phase: before.phase, target: before.target, leftActionMilliseconds: before.actionMilliseconds,
            rightActionMilliseconds: after?.actionMilliseconds ?? null,
            observedDeltaMilliseconds: before.actionMilliseconds !== null && after?.actionMilliseconds != null ? after.actionMilliseconds - before.actionMilliseconds : null};
        }), stableSpeedupEstimate: null, causalPerformanceClaim: false});
    }
  }
  return comparisons;
}

export async function analyzeArtifactSelection(selection, repository, open = openArtifactZip) {
  if (selection?.version !== 'actql-ci-artifact-selection/0.1' || !Array.isArray(selection.samples) || !selection.samples.length || selection.samples.length > 20) throw new Error('Invalid artifact selection');
  const report = {version: 'actql-ci-artifact-analysis/0.1', repository, complete: true, samples: [], comparisons: [], limits};
  const seen = new Set();
  for (const sample of selection.samples) {
    const source = provenance(sample.provenance, repository);
    if (!object(sample.reports) || !['fixed', 'fresh', 'capacity', 'session'].some(kind => typeof sample.reports[kind] === 'string')) throw new Error('No recognized retained report selected');
    const sessionSelected = Object.hasOwn(sample.reports, 'session');
    if (sessionSelected && (sample.reports.session !== 'checked.json' || Object.keys(sample.reports).length !== 1)) throw new Error('Session costs require their complete separate source archive');
    const id = `${source.runId}:${source.attempt}:${source.artifact.id}`;
    if (seen.has(id)) throw new Error('Duplicate artifact sample selection');
    seen.add(id);
    const zip = await open(sample.archive, {expectedSha256: source.artifact.sha256});
    try {
      if (zip.compressedBytes !== source.artifact.compressedBytes) throw new Error('Artifact compressed size mismatch');
      if (sessionSelected) {
        const sessionCosts = await projectSessionCosts(zip, source);
        report.samples.push({id, provenance: source, selectedReports: structuredClone(sample.reports),
          sampleCount: 1, campaigns: [], sessionCosts, selectedEvidenceComplete: false,
          status: source.status, conclusion: source.conclusion,
          reportedRunSuccessful: source.status === 'completed' && source.conclusion === 'success'});
        continue;
      }
      const campaigns = [];
      for (const kind of ['fixed', 'fresh', 'capacity']) {
        if (!sample.reports?.[kind]) continue;
        const path = artifactPath(sample.reports[kind]);
        const data = await zip.json(path);
        if (!object(data) || !digest(data.source?.digest) || (kind === 'capacity' ? data.version !== 'actql-relation-pipeline-structure/0.1' : data.version !== 'actql-relation-pipeline-mutations/0.1' || data.mode !== (kind === 'fixed' ? 'fixed' : 'explore'))) throw new Error('Invalid retained report schema or mode');
        if (data.revision !== source.executionSha) throw new Error('Artifact execution SHA mismatch');
        const projected = projectCampaign(data, kind, sample.expectedInventory);
        projected.path = path; projected.reportSha256 = await zip.digest(path);
        campaigns.push(projected);
      }
      const receipts = await resolveReceipts(campaigns, zip);
      const storage = await inventoryStorage(zip, receipts.references);
      delete receipts.references;
      const verified = new Map(receipts.verifiedReceiptIdentities.map(receipt => [receipt.path, receipt.digest]));
      for (const campaign of campaigns) for (const phase of campaign.phases) {
        const verifiedCount = phase.receipts.filter(receipt => {
          try { return verified.get(artifactPath(receipt.path)) === receipt.digest; } catch { return false; }
        }).length;
        phase.receiptCoverage = {verifiedCount, state: verifiedCount > 0 && verifiedCount === phase.receipts.length ? 'verified-retained-receipts' : 'unverified-or-unavailable'};
      }
      const selectedEvidenceComplete = !receipts.errors.length && !storage.references.unresolved.length && campaigns.every(c =>
        c.inventoryComplete && c.targetComplete && c.phases.every(p => p.milliseconds !== null && p.receiptCoverage.state === 'verified-retained-receipts') && c.aggregates.every(a => a.actionMilliseconds !== null));
      report.complete &&= selectedEvidenceComplete;
      report.samples.push({id, provenance: source, selectedReports: structuredClone(sample.reports),
        sampleCount: 1, campaigns, receipts, storage, status: source.status, conclusion: source.conclusion,
        reportedRunSuccessful: source.status === 'completed' && source.conclusion === 'success',
        selectedEvidenceComplete,
        unmeasured: {buildCount: null, compilerOnlyMilliseconds: null, hashingMilliseconds: null, ioMilliseconds: null, queueMilliseconds: null}});
    } finally { await zip.close(); }
  }
  report.comparisons = compareArtifactSamples(report.samples);
  if (selection.timingEvidence) {
    const timingEvidence = structuredClone(selection.timingEvidence);
    if (timingEvidence.repository !== repository) throw new Error('Timing repository mismatch');
    for (const sample of report.samples) {
      const attempts = (timingEvidence.runs ?? []).filter(run => run.id === sample.provenance.runId).flatMap(run => run.attempts ?? []).filter(attempt => attempt.number === sample.provenance.attempt);
      if (attempts.length !== 1 || ['headSha', 'workflow', 'event', 'status', 'conclusion'].some(key => attempts[0][key] !== sample.provenance[key])) throw new Error('Timing attempt identity mismatch');
    }
    addTimingEvidence(timingEvidence, report.samples.map(sample => `${sample.provenance.runId}:${sample.provenance.attempt}`));
    report.timing = timingEvidence.timing;
  }
  for (const sample of report.samples) if (sample.sessionCosts) {
    if (report.timing) bindSessionRunnerCosts(sample, report.timing);
    sample.selectedEvidenceComplete = sample.sessionCosts.runner.complete;
    report.complete &&= sample.selectedEvidenceComplete;
  }
  return report;
}
export async function collectArtifactEvidence(options) {
  const path = resolve(options.artifacts);
  const handle = await open(path, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0) | (constants.O_NONBLOCK ?? 0));
  let selection;
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > 4 * 1024 * 1024) throw new Error('Artifact selection is not a bounded regular file');
    const bytes = Buffer.alloc(stat.size + 1);
    let offset = 0;
    while (offset < bytes.length) {
      const {bytesRead} = await handle.read(bytes, offset, bytes.length - offset, offset);
      if (!bytesRead) break;
      offset += bytesRead;
    }
    const after = await handle.stat();
    if (offset !== stat.size || after.size !== stat.size || after.mtimeMs !== stat.mtimeMs || after.ctimeMs !== stat.ctimeMs) throw new Error('Artifact selection changed during read');
    selection = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes.subarray(0, offset)));
  } finally { await handle.close(); }
  for (const sample of selection.samples ?? []) sample.archive = resolve(dirname(path), sample.archive);
  return analyzeArtifactSelection(selection, options.repository);
}
export function formatArtifactEvidence(report) {
  const lines = [`Offline retained evidence: ${report.repository}`];
  for (const sample of report.samples) {
    if (sample.sessionCosts) {
      const {cost, runner} = sample.sessionCosts;
      lines.push(`\nSession sample ${sample.id}: ${sample.status}/${sample.conclusion}; n=${sample.sampleCount}`,
        `Provenance: ${JSON.stringify(sample.provenance)}`,
        `Bound producer owner: ${JSON.stringify(cost.producerOwner)}; partial phase sum ${cost.knownProducerMilliseconds} ms`,
        `Enclosing producer/check jobs: ${runner.selectedJobMilliseconds ?? 'unknown'} ms; whole attempt runner total ${runner.attemptRunnerMilliseconds ?? 'unknown'} ms; complete=${runner.complete}; ${runner.reason ?? 'observed'}`);
      for (const action of cost.actions) lines.push(`  ${action.actionId}: ${action.observation}; current ${action.currentMilliseconds ?? 'not executed'} ms; original ${action.originMilliseconds} ms at run ${action.originRunId} attempt ${action.originRunAttempt}`);
      lines.push('Net runner savings: unknown; nested phases and historical durations are not added to enclosing jobs.');
      continue;
    }
    lines.push(`\nSample ${sample.id}: ${sample.status}/${sample.conclusion}; n=${sample.sampleCount}`,
      `Provenance: ${JSON.stringify(sample.provenance)}`,
      `Receipts: ${sample.receipts.uniqueReceipts} unique; ${sample.receipts.duplicateOccurrences} repeated references; ${sample.receipts.caseObservations} case observations; errors ${JSON.stringify(sample.receipts.errors)}`);
    for (const campaign of sample.campaigns) {
      lines.push(`${campaign.campaign}: inventory ${campaign.inventory.length}, complete=${campaign.inventoryComplete}, targets complete=${campaign.targetComplete}; workload ${campaign.workloadSha256}`);
      for (const phase of campaign.aggregates) lines.push(`  ${phase.phase}/${phase.target}: action sum ${phase.actionMilliseconds ?? 'unknown'} ms; ${phase.measuredCount}/${phase.expectedCount} recorded durations; known partial sum ${phase.knownActionMilliseconds} ms`);
    }
    lines.push(`Storage: ZIP ${sample.storage.compressedArtifactBytes} bytes; logical ${sample.storage.logicalFileBytes} bytes; identical-content extra logical ${sample.storage.identicalContentExtraLogicalBytes} bytes; recoverable disk unknown`,
      `Categories: ${JSON.stringify(sample.storage.categories)}`,
      `Protected unresolved references: ${sample.storage.references.unresolved.length}; see JSON for exact custody paths and duplicate groups`);
  }
  for (const comparison of report.comparisons) lines.push(`Comparison ${comparison.left} -> ${comparison.right}/${comparison.campaign}: ${comparison.comparable ? 'matching observed dimensions' : 'non-comparable'}; ${comparison.differences.join(', ')}; n=1 per side; no stable/causal speedup estimate`);
  if (report.timing) lines.push(...formatTiming(report.timing));
  return [...lines, '', ...report.limits].join('\n').replace(/[\x00-\x08\x0b-\x1f\x7f-\x9f]/gu, '?');
}
