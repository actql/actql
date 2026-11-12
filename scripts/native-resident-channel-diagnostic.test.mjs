import assert from 'node:assert/strict';
import {spawnSync, execFileSync} from 'node:child_process';
import {chmod, mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {parse} from 'yaml';
import {channelDiagnosticSummary, publishChannelDiagnostic, rewriteChannelControlSpawn,
  runChannelDiagnosticCase} from './diagnose-native-resident-channel.mjs';

test('channel diagnostic changes only the exact original control spawn', async () => {
  const source = await readFile(new URL('./test-native-resident-site.mjs', import.meta.url), 'utf8');
  const changed = rewriteChannelControlSpawn(source, {python: '/original/python', wrapper: '/observer', report: '/closed/report'});
  const anchor = "const child = spawn(executable, ['run', ...configured,";
  const [before, after] = source.split(anchor);
  assert.equal(changed, before + 'const child = spawn("/original/python", ["/observer", "/closed/report", executable, \'run\', ...configured,' + after);
  assert(changed.includes("const siteProcessEnvironment = Object.freeze({PATH: '/usr/bin:/bin', LANG: 'C'});"));
  assert(changed.includes('milliseconds = 60_000'));
  assert.throws(() => rewriteChannelControlSpawn(source + '\n', {}), /Source differs/u);
});

test('channel publication retains bounded closed observations and the original failure', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-channel-summary-'));
  const observation = {selectedKind: 'consumer', requestedKind: 'unobserved', frameBytes: 8192, offset: 4096,
    childWait: 'running', ioctl: 'not-entered', unreadBytes: null, write: 'nonprogress', writeBytes: 0,
    channelReturn: 'busy', returnedBytes: null, consumerExecutorEntered: true, request: 'private-body'};
  const report = {channelCalls: 3, droppedGroups: 0, observations: [{observation, count: 3}], last: observation,
    consumerExecutorEntered: true, waitCounts: {running: 3, 'private-identity': 1},
    sendReturns: {'consumer/false': 3, 'private-id/false': 1},
    conditions: ['requested-kind-unavailable', 'private-error'], body: 'private-body'};
  const selected = channelDiagnosticSummary({status: 17, stderr: 'private-exception'}, report);
  assert.equal(selected.caseExit, 17);
  assert.equal(selected.last.offset, 4096);
  assert.deepEqual(selected.waitCounts, {running: 3});
  assert.deepEqual(selected.sendReturns, {'consumer/false': 3});
  assert(!JSON.stringify(selected).includes('private'));
  assert.equal(channelDiagnosticSummary({status: 0}, {...report,
    observations: Array(100).fill({observation, count: 1})}).observations.length, 64);
  assert.equal(channelDiagnosticSummary({}, {...report, last: {...observation, offset: 8192}}).last, null);
  const path = join(directory, 'closed');
  await writeFile(path, JSON.stringify(report));
  await writeFile(path + '.case', JSON.stringify({status: 17}));
  const output = join(directory, 'published.json');
  assert.equal(publishChannelDiagnostic(output, path, 1).caseExit, 17);
  assert.throws(() => publishChannelDiagnostic(output, path, 1), {code: 'EEXIST'});
});

test('channel case requires same-job preparation and preserves the original fixture and bound', () => {
  let invocation;
  const result = runChannelDiagnosticCase('/closed/report', {
    env: {ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION: '/same/preparation',
      ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT: '/same/http'},
    execute: (command, args, options) => {invocation = {command, args, options};return {status: 19};}});
  assert.equal(result.status, 19);
  assert.equal(invocation.args.at(-1), '--effect-computation-only');
  assert.equal(invocation.options.timeout, 285000);
  assert.equal(invocation.options.stdio, 'ignore');
  assert.throws(() => runChannelDiagnosticCase('/closed/report', {env: {},
    execute: () => assert.fail('No missing-preparation producer fallback')}), /Same-job Native preparation/u);
});

test('channel wrapper preserves the original three streams argv environment and nonzero return', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-channel-wrapper-'));
  const bin = join(directory, 'bin'); await mkdir(bin);
  const python = execFileSync('python3', ['-c', 'import sys;print(sys.executable)'], {encoding: 'utf8'}).trim();
  const spy = join(directory, 'spy.json'), fake = join(bin, 'gdb');
  await writeFile(fake, `#!${python}\nimport os,sys,json\nfrom pathlib import Path\n` +
    `a=sys.argv; i=a.index('--args'); f=[int(x) for x in a[i+3:]]\n` +
    `value=json.loads(os.pread(f[-1],1048576,0))\n` +
    `Path(${JSON.stringify(spy)}).write_text(json.dumps({'value':value,'parent':'set follow-fork-mode parent' in a,'detach':'set detach-on-fork on' in a,'noASLRChange':'set disable-randomization off' in a}))\n` +
    `assert os.read(f[0],100)==b'original request'\nos.write(f[1],b'original response')\nos.write(f[2],b'original stderr')\n` +
    `print('private debugger text')\nsys.exit(7)\n`);
  await chmod(fake, 0o700);
  const target = ['/original/native', 'run', '--executor-entry-log', join(directory, 'entry'), '--private-value', 'original'];
  const result = spawnSync(python, [fileURLToPath(new URL('./fixtures/native-resident-channel-debugger.py', import.meta.url)),
    join(directory, 'report'), ...target], {env: {PATH: bin, LANG: 'C', OMIT_THIS: 'private'},
    input: 'original request', encoding: 'utf8', timeout: 5000});
  assert.equal(result.status, 7); assert.equal(result.stdout, 'original response'); assert.equal(result.stderr, 'original stderr');
  const value = JSON.parse(await readFile(spy, 'utf8'));
  assert.deepEqual(value.value, {argv: target, environment: {PATH: bin, LANG: 'C'}});
  assert(value.parent && value.detach && value.noASLRChange);
});

test('explicit channel-only mode runs one hosted job and guards all normal jobs', async () => {
  const text = await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const workflow = parse(text), input = workflow.on.workflow_dispatch.inputs.native_effect_channel_diagnostic;
  assert.deepEqual({type: input.type, default: input.default}, {type: 'boolean', default: false});
  const selected = workflow.jobs['native-effect-channel'];
  assert(selected.if.includes("github.event_name == 'workflow_dispatch' && inputs.native_effect_channel_diagnostic"));
  assert.equal(selected['runs-on'], 'ubuntu-24.04');
  assert.deepEqual(selected.permissions, {contents: 'read'});
  assert.equal(selected.needs, undefined);
  assert.equal(selected.steps.filter(step => step.run?.includes('diagnose-native-resident-channel.mjs')).length, 1);
  assert(selected.steps.find(step => step.id === 'native-preparation').run.includes('--entries all --seconds 900 --http-jobs 2'));
  const upload = selected.steps.filter(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(upload.length, 1); assert(upload[0].with.path.endsWith('/sanitized.json'));
  for (const [name, job] of Object.entries(workflow.jobs)) {
    if (name !== 'native-effect-channel') {
      assert(job.if.includes('!inputs.native_effect_channel_diagnostic'), name);
      assert.equal((job.if.match(/\$\{\{/gu) ?? []).length, 1, name);
      assert.equal((job.if.match(/\}\}/gu) ?? []).length, 1, name);
    }
  }
  assert(workflow.concurrency.group.includes("inputs.native_effect_channel_diagnostic && 'effect-channel'"));
  assert(workflow.concurrency['cancel-in-progress'].includes('!inputs.native_effect_channel_diagnostic'));
});
