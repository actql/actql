import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {normalNpmPackJsonArgs, parseNpmPackJson} from './packed-client-packages.mjs';
import {packDistributionPackages} from './measure-distribution-artifacts.mjs';

test('normal pack JSON arguments preserve caller flags and one lifecycle stdout policy', () => {
  for (const input of [
    ['pack', '--json', '--pack-destination', '/owned/output'],
    ['pack', '--offline', '--json', '--cache', '/owned/cache', '--pack-destination', '/owned/output'],
    ['pack', '--pack-destination', '/owned/output', '--json', '--future-npm-option'],
  ]) {
    const original = [...input], result = normalNpmPackJsonArgs(input);
    assert.deepEqual(input, original);
    assert.deepEqual(result, [...original, '--foreground-scripts=false']);
    assert.notEqual(result, input);
  }
});

test('normal pack JSON policy refuses disabled hooks duplicate JSON and competing foreground flags', () => {
  for (const args of [null, [], ['install', '--json'], ['pack'], ['pack', '--json', '--json'],
    ['pack', '--json', 1], ['pack', '--json', '--ignore-scripts'],
    ['pack', '--json', '--ignore-scripts=true'], ['pack', '--json', '--ignore-scripts=false'],
    ['pack', '--json', '--foreground-scripts'], ['pack', '--json', '--foreground-scripts=true'],
    ['pack', '--json', '--foreground-scripts=false']]) {
    assert.throws(() => normalNpmPackJsonArgs(args), TypeError);
  }
});

test('pack JSON parses only the complete value without recovering diagnostic suffixes', () => {
  for (const value of [[{name: '@fixture/original'}], {'@fixture/original': {files: []}}]) {
    const json = JSON.stringify(value);
    assert.deepEqual(parseNpmPackJson(' \n' + json + '\n'), value);
    for (const output of ['lifecycle diagnostic\n' + json, '[diagnostic]\n' + json,
      json + '\ntrailing diagnostic', json + json]) {
      assert.throws(() => parseNpmPackJson(output), SyntaxError);
    }
  }
});

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'normal-pack-json-adapter-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const names = ['client-wire', 'sdk', 'node', 'run-host-core', 'local-node'];
  const calls = [], authored = names.map(name => {
    const filename = `${name}-1.2.3.tgz`, bytes = Buffer.from(`authored archive DATA: ${name}\n`);
    writeFileSync(join(root, filename), bytes);
    return {name: `@actql/${name}`, version: '1.2.3', filename, size: bytes.length,
      expectedSha256: createHash('sha256').update(bytes).digest('hex')};
  });
  const run = async (command, args, cwd) => {
    const index = calls.length, name = names[index];
    assert.equal(command, 'npm');
    assert.deepEqual(args, ['pack', '--pack-destination', root, '--json', '--foreground-scripts=false']);
    assert.equal(cwd, join(root, 'packages', name));
    calls.push({command, args, cwd});
    const {expectedSha256, ...metadata} = authored[index];
    return {stdout: JSON.stringify([metadata])};
  };
  return {root, calls, authored, run};
}

test('distribution pack adapter keeps the exact metadata identity size and archive digest checks', async t => {
  const f = fixture(t);
  const packages = await packDistributionPackages({repository: f.root, destination: f.root, run: f.run});
  assert.equal(f.calls.length, 5);
  assert.deepEqual(packages.map(value => value.sha256), f.authored.map(value => value.expectedSha256));
  assert.deepEqual(packages.map(value => value.name), f.authored.map(value => value.name));
});

test('distribution pack adapter refuses lifecycle prefixes instead of scanning for a JSON suffix', async t => {
  const f = fixture(t);
  await assert.rejects(packDistributionPackages({repository: f.root, destination: f.root,
    run: async (...args) => ({stdout: 'lifecycle [diagnostic]\n' + (await f.run(...args)).stdout})}), SyntaxError);
  assert.equal(f.calls.length, 1);
});

test('distribution pack adapter still refuses a wrong package name filename or size', async t => {
  for (const change of [{name: '@fixture/foreign'}, {filename: '../foreign.tgz'}, {size: 0}]) {
    const f = fixture(t);
    await assert.rejects(packDistributionPackages({repository: f.root, destination: f.root,
      run: async (...args) => {
        const report = parseNpmPackJson((await f.run(...args)).stdout);
        return {stdout: JSON.stringify([{...report[0], ...change}])};
      }}), {code: 'ERR_ASSERTION'});
    assert.equal(f.calls.length, 1);
  }
});
