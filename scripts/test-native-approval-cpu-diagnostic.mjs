// One existing installed workflow under an unprivileged, flat CPU sampler.
// Raw perf data and original receipt bodies never enter the upload report.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {basename, dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {parseArgs} from 'node:util';

// The caller has already verified every release member's bytes and hash.
// These labels classify observed member names, never physical custody or a path.
export function approvalPerfDsoMembers(manifest) {
  const packages = manifest.packages.filter(value => value.name === manifest.platforms['linux-x64-gnu'].package);
  assert.equal(packages.length, 1);
  const members = new Map();
  for (const [path, role] of [['bin/actql-native-client', 'native-client'],
    ['lib/libactql_crypto_component.so', 'crypto-component'],
    ['lib/libactql_sqlite_component.so', 'sqlite-component']]) {
    const files = packages[0].files.filter(value => value.path === path);
    assert.equal(files.length, 1, 'Required verified diagnostic DSO member missing');
    assert.match(files[0].sha256, /^[a-f0-9]{64}$/u);
    assert(Number.isSafeInteger(files[0].bytes) && files[0].bytes > 0);
    members.set(basename(path), Object.freeze({role, sha256: files[0].sha256}));
  }
  return members;
}

export function approvalPerfSamples(text, selected, observation = {}, dsoMembers = new Map()) {
  Object.assign(observation, {nonEmptyLines: 0, nonPidLines: 0,
    foreignPidLines: 0, selectedLines: 0, malformedSelectedLines: 0});
  assert(typeof text === 'string' && Buffer.byteLength(text) <= 8 * 1024 ** 2);
  assert(Array.isArray(selected) && selected.length === 2);
  const reports = new Map(selected.map(({template, pid}) => {
    assert(['deal-review-mock', 'churn-risk-mock'].includes(template));
    assert(Number.isSafeInteger(pid) && pid > 0);
    return [pid, {template, pid, samples: 0, unresolved: 0, symbols: new Map()}];
  }));
  assert.equal(reports.size, 2, 'Distinct actual approval processes required');
  assert.equal(new Set(selected.map(value => value.template)).size, 2);
  for (const line of text.split('\n')) {
    if (!line.trim() || line.startsWith('#')) continue;
    observation.nonEmptyLines++;
    const prefix = /^\s*(\d+)\s+/u.exec(line);
    if (prefix === null) {observation.nonPidLines++; continue;}
    const report = reports.get(Number(prefix[1]));
    if (report === undefined) {observation.foreignPidLines++; continue;}
    observation.selectedLines++;
    // perf 7 renders symbol/DSO only when IP is selected. Consume that hex
    // field without capturing, retaining or publishing its address value.
    const sample = /^\s*\d+\s+[0-9a-f]{1,16}\s+(.+?)\s+\(([^\r\n]*)\)\s*$/iu.exec(line);
    if (sample === null) {
      observation.malformedSelectedLines++;
      throw Object.assign(new Error('Invalid selected flat perf sample'), {
        code: 'NativeApprovalPerfSelectedLineInvalid', lineShape: {
          characters: line.length, whitespaceFields: Math.min(32, line.trim().split(/\s+/u).length),
          hasHexIpToken: /^\s*\d+\s+[0-9a-f]{1,16}\s+/iu.test(line),
          hasDsoEnvelope: /\([^\r\n]*\)\s*$/u.test(line),
        },
      });
    }
    report.samples++;
    const symbol = sample[1].replace(/\+0x[0-9a-f]+$/iu, '');
    if (symbol.length > 2048 || !/^[A-Za-z_.$][A-Za-z0-9_.$@:-]*$/u.test(symbol)) {
      report.unresolved++; continue;
    }
    const dso = sample[2].trim();
    const role = !dso || dso === '[unknown]' ? 'unknown'
      : dsoMembers.get(basename(dso))?.role ?? 'other';
    assert(['native-client', 'crypto-component', 'sqlite-component', 'other', 'unknown'].includes(role));
    const key = JSON.stringify([role, symbol]);
    const previous = report.symbols.get(key);
    report.symbols.set(key, {dsoRole: role, symbol, samples: (previous?.samples ?? 0) + 1});
    assert(report.symbols.size <= 16384, 'Unexpected diagnostic symbol volume');
  }
  return [...reports.values()].map(({symbols, ...report}) => ({...report,
    topSymbols: [...symbols.values()].sort((a, b) => b.samples - a.samples ||
      a.dsoRole.localeCompare(b.dsoRole) || a.symbol.localeCompare(b.symbol)).slice(0, 40),
    resolvedSymbols: new Set([...symbols.values()].map(value => value.symbol)).size,
    resolvedDsoSymbolGroups: symbols.size}));
}

// Both projections consume the SAME recorded data before its outer owner
// removes it. The fallback retains only PID/IP shape counts, never addresses,
// and cannot turn a primary attribution failure into a successful diagnostic.
export function decodeApprovalPerf(run, data, selected, dsoMembers, report) {
  let primaryFailure;
  try {
    const samples = run(['script', '-i', data, '-F', 'pid,ip,sym,dso']);
    report.decodeExitCode = samples.status; report.decodeErrorCode = samples.error?.code ?? null;
    assert(!samples.error && samples.status === 0, 'Flat sample decoding unavailable');
    if (/lost|throttl/iu.test(samples.stderr)) report.conditions.push('sample decoding reported loss or throttling');
    report.sampleParsing = {};
    report.approvals = approvalPerfSamples(samples.stdout, selected, report.sampleParsing, dsoMembers);
  } catch (error) {primaryFailure = error;}
  const fallback = report.fallback = {fields: ['pid', 'ip'], complete: false,
    approvals: selected.map(({template, pid}) => ({template, pid, samples: 0, malformed: 0}))};
  try {
    const samples = run(['script', '-i', data, '-F', 'pid,ip']);
    fallback.exitCode = samples.status; fallback.errorCode = samples.error?.code ?? null;
    assert(!samples.error && samples.status === 0, 'Fallback sample decoding unavailable');
    assert(Buffer.byteLength(samples.stdout) <= 8 * 1024 ** 2);
    for (const line of samples.stdout.split('\n')) {
      const prefix = /^\s*(\d+)\s+/u.exec(line);
      const original = prefix === null ? undefined : fallback.approvals.find(value => value.pid === Number(prefix[1]));
      if (original === undefined) continue;
      if (/^\s*\d+\s+[0-9a-f]{1,16}\s*$/iu.test(line)) original.samples++;
      else {
        original.malformed++;
        fallback.firstMalformedShape ??= {characters: line.length,
          whitespaceFields: Math.min(32, line.trim().split(/\s+/u).length)};
      }
    }
    fallback.complete = fallback.approvals.every(value => value.samples > 0 && value.malformed === 0);
    if (!fallback.complete) report.conditions.push('same-data fallback sample shape unavailable');
    if (!primaryFailure && fallback.complete && report.approvals.some(value =>
      value.samples !== fallback.approvals.find(other => other.pid === value.pid).samples)) {
      report.conditions.push('primary and fallback selected sample counts differ');
    }
  } catch (error) {
    fallback.failure = {name: error.name, code: error.code ?? null};
    report.conditions.push('same-data fallback decoding unavailable');
  }
  if (primaryFailure) throw primaryFailure;
  return report.approvals;
}

export function saveApprovalPerfReport(output, scratch, report) {
  // A failed report write retains the same private data for diagnosis.
  writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
  rmSync(scratch, {recursive: true});
}

export async function nativeApprovalCpuDiagnostic({root, normal, binding, perf, output}) {
  assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
  assert(process.getuid() !== 0, 'Profiler and consumer must retain the normal runner UID');
  root = realpathSync(root); normal = realpathSync(normal); perf = realpathSync(perf);
  output = resolve(output);
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  const load = name => import(pathToFileURL(join(root, 'scripts', name)).href);
  const {verifyNativeCliRelease} = await load('native-cli-release.mjs');
  const {checkoutState} = await load('packed-client-packages.mjs');
  const {approvalCallCounts} = await load('native-approval-performance.mjs');
  const manifest = await verifyNativeCliRelease(normal), source = checkoutState(root);
  const dsoMembers = approvalPerfDsoMembers(manifest);
  assert(source.clean && source.revision === manifest.sourceSha,
    'Unchanged installed fixture and artifact require the same original source');
  const original = JSON.parse(readFileSync(binding, 'utf8'));
  assert.equal(original.sourceSha, source.revision);
  assert.equal(hash(readFileSync(join(normal, 'release.json'))), original.manifestSha256);
  const scratch = mkdtempSync(join(dirname(output), 'cpu-samples-'));
  const report = {qualification: 'one instrumented installed workflow; not formal latency or thirty-sample acceptance',
    sourceSha: source.revision, diagnosticSha256: hash(readFileSync(fileURLToPath(import.meta.url))),
    perfSha256: hash(readFileSync(perf)),
    manifestSha256: original.manifestSha256, uid: process.getuid(), event: 'cpu-clock:u', frequency: 49,
    callGraph: false, sampleFields: ['pid', 'sym', 'dsoRole'],
    dsoRoleMembers: [...dsoMembers.values()], complete: false,
    consumerInvocations: 0, scratchPreservedForSymbols: true, approvals: [], conditions: []};
  const run = (args, options = {}) => spawnSync(perf, args, {cwd: root, encoding: 'utf8',
    maxBuffer: 8 * 1024 ** 2, ...options});
  let stage = 'profiler capability';
  try {
    const version = run(['version']);
    report.toolExitCode = version.status; report.toolErrorCode = version.error?.code ?? null;
    assert.equal(version.status, 0, 'Profiler unavailable');
    report.perfVersion = version.stdout.trim();
    const capability = run(['stat', '-e', 'cpu-clock:u', '--', '/usr/bin/true']);
    report.capabilityExitCode = capability.status;
    report.capabilitySignal = capability.signal; report.capabilityErrorCode = capability.error?.code ?? null;
    if (/permission|not permitted|access/iu.test(capability.stderr ?? ''))
      report.conditions.push('normal UID CPU sampler permission refused');
    if (/not supported|invalid event|unknown event/iu.test(capability.stderr ?? ''))
      report.conditions.push('software CPU event unavailable');
    assert.equal(capability.status, 0, 'Unprivileged software CPU sampling unavailable');
    stage = 'unchanged installed consumer';
    const data = join(scratch, 'perf.data'); report.consumerInvocations++;
    const collected = run(['record', '-e', 'cpu-clock:u', '-F', '49', '--no-buildid', '--no-buildid-cache',
      '-o', data, '--', process.execPath, join(root, 'scripts/test-native-cli-mock-install.mjs'), normal],
    // The original harness alone keeps the installed ELF for symbolization.
    // Its existing closed product environment does not forward this flag.
    {env: {...process.env, ACTQL_TEST_PRESERVE_SCRATCH: '1'}});
    report.consumerExitCode = collected.status; report.consumerSignal = collected.signal;
    report.collectionErrorCode = collected.error?.code ?? null;
    assert(!collected.error && collected.status === 0 && collected.signal === null,
      'Original installed workflow or profiler failed');
    if (/lost|throttl/iu.test(collected.stderr)) report.conditions.push('sample loss or throttling reported');
    stage = 'original approval receipt';
    const matches = [...collected.stdout.matchAll(/^Installed Native mock approval\/recovery passed: (.+)$/gmu)];
    assert.equal(matches.length, 1, 'One original workflow receipt required');
    const receiptPath = realpathSync(matches[0][1]); assert.equal(dirname(receiptPath), normal);
    const bytes = readFileSync(receiptPath), receipt = JSON.parse(bytes);
    assert.equal(receipt.cliSourceSha, source.revision); assert.equal(receipt.scenarios.length, 2);
    report.receiptSha256 = hash(bytes);
    const selected = receipt.scenarios.map(scenario => {
      const approvals = scenario.commands.filter(command => command.args.includes('approve'));
      assert.equal(approvals.length, 1, 'Only the original approval of each fixture is selected');
      return {template: scenario.template, pid: approvalCallCounts(approvals[0]).pid};
    });
    stage = 'flat sample attribution';
    report.selectedApprovals = selected;
    decodeApprovalPerf(run, data, selected, dsoMembers, report);
    assert(report.approvals.every(value => value.samples > 0), 'Actual approval CPU samples missing');
    if (report.approvals.some(value => value.resolvedSymbols === 0))
      report.conditions.push('approval function symbols unavailable');
    assert.deepEqual(checkoutState(root), source, 'Original fixture source changed');
    report.complete = report.conditions.length === 0;
  } catch (error) {
    report.failure = {stage, name: error.name, code: error.code ?? null};
    if (error.code === 'NativeApprovalPerfSelectedLineInvalid') {
      report.failure.reason = 'selected sample does not match fixed pid/hex-ip/symbol/dso fields';
      report.failure.lineShape = error.lineShape;
    }
  } finally {
    // This directory contains only profiler-derived data, never business state.
    saveApprovalPerfReport(output, scratch, report);
  }
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const {values} = parseArgs({options: Object.fromEntries(
    ['root', 'normal', 'binding', 'perf', 'output'].map(name => [name, {type: 'string'}]))});
  assert(Object.values(values).length === 5 && Object.values(values).every(value => value));
  const report = await nativeApprovalCpuDiagnostic(values);
  console.log(JSON.stringify({complete: report.complete, conditions: report.conditions,
    failure: report.failure ?? null}));
  process.exitCode = report.complete ? 0 : 1;
}
