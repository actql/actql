import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

// Execute the actual discriminant projection with synthetic PRIVATE strings in
// every payload slot. This is a privacy/presentation probe, not a Host issuance
// or Native lifecycle test; actual imported enum compatibility is compiler-checked
// by the canonical Native package gate.
test('cleanup category never serializes payloads and keeps public error code', {timeout: 90_000}, t => {
  const source = readFileSync(new URL('../src/cmd/native_client/local_command_cleanup_cause.mbt', import.meta.url), 'utf8');
  const functionSource = source.slice(source.indexOf('fn command_preparation_cleanup_cause('));
  const outer = [], declarations = [], assertions = [];
  const nested = [...functionSource.matchAll(/    (Command\w+)\(cause\) =>\s+match cause \{([\s\S]*?)\n      \}/g)];
  assert.ok(nested.length >= 20);
  let covered = functionSource;
  for (const [block, variant, body] of nested) {
    const type = `Probe${variant}`;
    const cases = [...body.matchAll(/([A-Z]\w*)(\((?:_|,|\s)*\))?\s*=>\s*"([A-Za-z0-9]+)"/g)];
    assert.ok(cases.length > 0);
    const residual = cases.reduce((value, [row]) => value.replace(row, ''), body);
    assert.equal(residual.trim(), '', 'Only closed enum patterns and literal tags are permitted');
    declarations.push(`pub(all) enum ${type} {\n` + cases.map(([, name, fields]) =>
      '  ' + name + (fields ? '(' + Array((fields.match(/_/g) ?? []).length).fill('String').join(', ') + ')' : '')).join('\n') + '\n}');
    outer.push(`  ${variant}(${type})`);
    for (const [, name, fields, tag] of cases) {
      const payload = fields ? '(' + Array((fields.match(/_/g) ?? []).length).fill('"PRIVATE-PAYLOAD-NOT-A-CAPABILITY"').join(', ') + ')' : '';
      assertions.push(`  assert_eq(command_preparation_cleanup_cause(${variant}(${name}${payload})), "${tag}")`);
    }
    covered = covered.replace(block, '');
  }
  const direct = [...covered.matchAll(/    (Command\w+)(\(_\))? => "([A-Za-z0-9]+)"/g)];
  for (const [block, variant, payload, tag] of direct) {
    outer.push('  ' + variant + (payload ? '(String)' : ''));
    assertions.push(`  assert_eq(command_preparation_cleanup_cause(${variant}${payload ? '("PRIVATE-APPLICATION-MESSAGE")' : ''}), "${tag}")`);
    covered = covered.replace(block, '');
  }
  assert.match(covered, /^fn command_preparation_cleanup_cause\(\s*issue : LocalCommandPreparationIssue,?\s*\) -> String \{\s*match issue \{\s*\}\s*\}\s*$/);
  const main = readFileSync(new URL('../src/cmd/native_client/main.mbt', import.meta.url), 'utf8');
  assert.match(main, /fn fail_cleanup_command\(message : String\)[\s\S]*?"ACTQL_E_CLEANUP_PENDING",\s*message,/);
  assert.match(main, /command_preparation_cleanup_kind\(issue\) \+\s*observed \+\s*" cause=" \+\s*command_preparation_cleanup_cause\(issue\)/);
  const crypto = readFileSync(new URL('../src/cmd/native_client/local_initial_crypto_domain.mbt', import.meta.url), 'utf8');
  assert.match(crypto, /Filesystem\(issue\) =>\s*"Filesystem\(" \+\s*command_preparation_cleanup_cause\(CommandFilesystemCleanup\(issue\)\) \+\s*"\)"/);
  const presentation = readFileSync(new URL('../src/cmd/native_client/local_command_diagnostic.mbt', import.meta.url), 'utf8');
  assert.match(presentation, /\("code", Json::string\(code\)\), \("message", Json::string\(text\)\)/);
  const root = mkdtempSync(join(tmpdir(), 'actql-cleanup-cause-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  mkdirSync(join(root, 'src'));
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/cleanup-cause-probe"\nsource = "src"\n');
  writeFileSync(join(root, 'src/moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/probe.mbt'), declarations.join('\n') + '\npub(all) enum LocalCommandPreparationIssue {\n' + outer.join('\n') + '\n}\n');
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), functionSource + '\n' + 'test "all closed causes exclude private payloads" {\n' + assertions.join('\n') + '\n}\n');
  const actual = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024});
  assert.equal(actual.error, undefined, actual.error?.message);
  assert.equal(actual.status, 0, actual.stdout + actual.stderr);
  assert.match(actual.stdout + actual.stderr, /Total tests: 1, passed: 1, failed: 0/);
});
