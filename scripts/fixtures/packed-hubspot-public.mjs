// Same original public Program, values and assertion oracle, over normal installed packages.
import assert from 'node:assert/strict';
import test from 'node:test';
import {inspect, promisify} from 'node:util';
import {execFile} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fixture, expected} from './packed-hubspot-public.fixture.mjs';
const executeFile = promisify(execFile);
const source = 'SELECT id, amount, tags FROM hubspot.companies |> RESULT records';
const columns = [
  {name: 'id', contract: {type: 'string', nullable: false}},
  {name: 'amount', contract: {type: 'decimal', nullable: true, precision: 38, scale: 10}},
  {name: 'tags', contract: {type: 'array', nullable: true, items: {type: 'string', nullable: false}}},
];

for (const entrance of ['Local', 'HTTPS']) test(
  `public ${entrance} HubSpot preserves full values through Named Result and original Run lookup`, async t => {
    const f = await fixture(t, entrance);
    const report = await f.client.check(source, {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.equal(report.report?.verdict, 'verified', inspect(report, {depth: 8}));
    assert.deepEqual(report.report.runnable, {verdict: 'yes', reasons: []});
    assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
    const submissionRef = f.client.newSubmission({nonce: `hubspot-public-${entrance.toLowerCase()}`});
    const execution = await f.client.startSource(source, {format: 'sql', submissionRef});
    const state = await execution.wait({signal: AbortSignal.timeout(20000)});
    if (state.status !== 'succeeded') t.diagnostic(inspect({state, observations: f.observations},
      {depth: 8, maxStringLength: 3000}));
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 8}));
    const result = execution.result('records');
    assert.deepEqual((await result.describe()).columns, columns);
    assert.deepEqual(await result.all(), [expected]);
    assert.deepEqual(await result.all(), [expected]);
    const attached = await f.client.attach(execution.ref);
    assert.deepEqual(await attached.result('records').all(), [expected]);
    const original = await f.client.startSource(source, {format: 'sql', submissionRef});
    assert.deepEqual(original.ref, execution.ref);
    assert.deepEqual(await original.result('records').all(), [expected]);
    assert.deepEqual(f.state.requests.map(value => value.path.split('?')[0]), [
      '/account-info/v3/details', '/crm/v3/properties/companies',
      '/crm/v3/objects/companies', '/crm/v3/properties/companies']);
    assert.equal(f.state.resolutions, 4, 'result and original Run lookup cannot replay provider acquisition');
    await f.client.close();
    const cleanup = f.observations.filter(([name]) => name === 'dispatch_cleanup_completed');
    assert.equal(cleanup.length, 1);
    const usage = cleanup[0][1].resourceUsage;
    assert.equal(usage.holdings, '2');
    for (const field of ['heldBytes', 'reservedTransferBytes', 'reservedRetentionBytes',
      'reservedExecutionBytes', 'uncertainTransferBytes']) assert.equal(usage[field], '0', field);
    assert(BigInt(usage.transferredBytes) > 0n);
    if (entrance === 'Local') {
      await f.closeHost();
      const restartPath = join(f.root, 'original-host-restart.json');
      await writeFile(restartPath, JSON.stringify({installation: f.installation,
        ref: execution.ref}), {flag: 'wx', mode: 0o600});
      const launched = executeFile(process.execPath,
        ['scripts/fixtures/packed-hubspot-restart.mjs', restartPath],
        {cwd: new URL('../../', import.meta.url), timeout: 10000,
          killSignal: 'SIGTERM', maxBuffer: 1024 * 1024});
      let child;
      try {child = await launched;}
      catch (error) {
        await Promise.all(['stdout', 'stderr'].map(stream => writeFile(
          join(f.root, `restart-child.${stream}.log`), error[stream] ?? '',
          {flag: 'wx', mode: 0o600})));
        throw error;
      }
      await Promise.all(['stdout', 'stderr'].map(stream => writeFile(
        join(f.root, `restart-child.${stream}.log`), child[stream],
        {flag: 'wx', mode: 0o600})));
      await writeFile(join(f.root, 'restart-child-result.json'), JSON.stringify({
        pid: launched.child.pid, exitCode: 0, secretResolutions: 0,
        source: 'hubspot-client-restart.fixture.mjs'}), {flag: 'wx', mode: 0o600});
      const restored = JSON.parse(child.stdout);
      assert.deepEqual(restored, {sameRun: true, secretResolutions: 0,
        columns, rows: [expected]});
      assert.equal(f.state.requests.length, 4, 'a fresh process restores the original capture without Provider replay');
    }
    t.diagnostic(JSON.stringify({entrance, providerRequests: f.state.requests.length,
      sameRunLookup: true, repeatedRead: true, usage}));
  });
