import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {classifyCommand} from './local-checks-hook.mjs';
import {codexHookResponse} from './codex-local-checks-hook.mjs';
import {claudeHookResponse} from './claude-local-checks-hook.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const event = command => ({hook_event_name: 'PreToolUse', tool_name: 'Bash',
  cwd: root, tool_input: {command}});
// Run every shared input case against both explicitly named protocol adapters.
const hookResponse = payload => {
  const codex = codexHookResponse(payload);
  assert.deepEqual(claudeHookResponse(payload), codex);
  return codex;
};

test('PreToolUse blocks simple full Moon commands with supported deny JSON only', () => {
  for (const command of ['moon test', 'moon test --target js --deny-warn',
    'moon test --filter selected', 'moon build --target native --release']) {
    const response = hookResponse(event(command));
    assert.deepEqual(Object.keys(response), ['hookSpecificOutput']);
    assert.deepEqual(Object.keys(response.hookSpecificOutput),
      ['hookEventName', 'permissionDecision', 'permissionDecisionReason']);
    assert.equal(response.hookSpecificOutput.hookEventName, 'PreToolUse');
    assert.equal(response.hookSpecificOutput.permissionDecision, 'deny');
    const reason = response.hookSpecificOutput.permissionDecisionReason;
    assert.match(reason, /local-checks\.mjs (test|build) moon --allow-heavy --timeout-seconds <seconds> --/u);
    assert.match(reason, /not user approval/u);
  }
});

test('focused checks, reporting and unrelated commands make no hook decision', () => {
  for (const command of ['moon test --target js -p execution_relation',
    'moon test src/execution_relation/cases_test.mbt',
    'moon build --target js src/bridge', 'moon check --target js',
    'node --test scripts/local-checks-policy.test.mjs',
    'node scripts/local-checks.mjs test node -- scripts/example.test.mjs',
    'node scripts/local-checks.mjs test moon -- -p execution_relation',
    'node scripts/local-checks.mjs build moon -- src/bridge',
    'node scripts/local-checks.mjs list', 'node scripts/local-checks.mjs changed',
    'node scripts/local-checks.mjs run lint',
    'node scripts/local-checks.mjs run core --dry-run',
    'moon test --help', 'moon build --dry-run']) {
    assert.equal(hookResponse(event(command)), null, command);
  }
});

test('known-heavy job denies while preserving the selected target in guidance', () => {
  const result = hookResponse(event('node scripts/local-checks.mjs run core --target wasm'));
  assert.match(result.hookSpecificOutput.permissionDecisionReason,
    /run core --allow-heavy --target wasm/u);
  assert.equal(classifyCommand('node scripts/local-checks.mjs run new-job').recognized, false);
});

test('CI-only pipeline job hooks deny execution with no heavy override route but permit reporting', () => {
  for (const name of ['pipeline-mutations', 'pipeline-capacity', 'pipeline-mutations-rest', 'pipeline-capacity-mutants', 'pipeline-validation', 'pipeline-evidence']) {
    for (const options of ['', ' --allow-heavy', ' --allow-heavy --timeout-seconds 30']) {
      const command = `node scripts/local-checks.mjs run ${name}${options}`;
      assert.equal(classifyCommand(command).classification, 'ci-only');
      const result = hookResponse(event(command)).hookSpecificOutput;
      assert.equal(result.permissionDecision, 'deny');
      assert.match(result.permissionDecisionReason, /CI only/u);
      assert.match(result.permissionDecisionReason, /--allow-heavy cannot enable this job locally/u);
      assert.doesNotMatch(result.permissionDecisionReason, /run [a-z-]+ --allow-heavy/u);
    }
    for (const options of ['--dry-run', '--allow-heavy --dry-run']) {
      const command = `node scripts/local-checks.mjs run ${name} ${options}`;
      assert.equal(classifyCommand(command).classification, 'reporting');
      assert.equal(hookResponse(event(command)), null);
    }
  }
});

test('unknown Moon options direct users to supported policy rather than a rejected override', () => {
  const reason = hookResponse(event('moon test --future-option path')).
    hookSpecificOutput.permissionDecisionReason;
  assert.match(reason, /unclassified arguments/u);
  assert.match(reason, /checkout root/u);
  assert.doesNotMatch(reason, /--allow-heavy --timeout-seconds/u);
});

test('an explicit override belongs only to recognized wrapper options before --', () => {
  for (const command of [
    'node scripts/local-checks.mjs run core --allow-heavy',
    'node ./scripts/local-checks.mjs run core --target js --allow-heavy --timeout-seconds 30',
    'node scripts/local-checks.mjs test moon --allow-heavy --timeout-seconds 30.5 --kill-grace-seconds 0.25 -- --target js',
    'node scripts/local-checks.mjs build moon --allow-heavy --timeout-seconds 30 -- --release',
  ]) {
    assert.equal(classifyCommand(command).explicitOverride, true, command);
    assert.equal(hookResponse(event(command)), null);
  }
  for (const command of ['moon test --allow-heavy',
    'node scripts/local-checks.mjs test moon -- --allow-heavy']) {
    assert.equal(hookResponse(event(command)).hookSpecificOutput.permissionDecision, 'deny');
  }
});

test('unsupported shell syntax is explicitly unclassified, never asserted safe', () => {
  for (const command of [
    'moon test && echo --allow-heavy',
    'node scripts/local-checks.mjs run core --allow-heavy; moon test',
    'moon test | cat', 'moon test >log', 'moon test\nmoon build',
    'cd repo && moon test', 'env CI=1 moon test', 'CI=1 moon test',
    'bash -c "moon test"', '/usr/bin/moon test', 'npm test',
    'node proofs/relation-pipeline/mutations.mjs verify',
    'node proofs/relation-pipeline/capacity/run.mjs all',
    'node proofs/relation-pipeline/run.mjs all',
    'node proofs/relation-pipeline/ci-artifacts.mjs begin mutations',
    'moon test --target "js"', "moon test --filter 'selected *'",
    'moon test $(echo src/a)', 'moon test src/*', 'moon test # comment',
    'moon test\\\n--target js',
  ]) {
    assert.deepEqual(classifyCommand(command), {recognized: false, classification: 'unknown'}, command);
    assert.equal(hookResponse(event(command)), null, 'No hook decision is not a safety verdict');
  }
});

test('malformed wrapper flags never become a matching explicit override', () => {
  for (const command of [
    'node scripts/local-checks.mjs run core --allow-heavy=1',
    'node scripts/local-checks.mjs run core --timeout-seconds --allow-heavy',
    'node scripts/local-checks.mjs test moon --allow-heavy',
    'node scripts/local-checks.mjs run core -- --allow-heavy',
  ]) assert.equal(classifyCommand(command).recognized, false, command);
});

test('personal hook is scoped to this checkout and only PreToolUse/Bash', () => {
  for (const payload of [null, {}, {...event('moon test'), tool_name: 'apply_patch'},
    {...event('moon test'), hook_event_name: 'PostToolUse'},
    {...event('moon test'), cwd: root.replace(/\/$/u, '') + '-other'},
    {...event('moon test'), cwd: '/'}, {...event('moon test'), cwd: 'relative'},
    {...event('moon test'), cwd: undefined}]) assert.equal(hookResponse(payload), null);
  assert.equal(hookResponse({...event('moon test'), cwd: root + 'src'}).
    hookSpecificOutput.permissionDecision, 'deny');
});

for (const client of ['codex', 'claude']) test(`${client} stdin adapter emits deny JSON or no decision without executing commands`, () => {
  const script = fileURLToPath(new URL(`./${client}-local-checks-hook.mjs`, import.meta.url));
  const run = input => spawnSync(process.execPath, [script],
    {input, encoding: 'utf8', timeout: 5000});
  const blocked = run(JSON.stringify(event('moon test')));
  assert.equal(blocked.status, 0);
  assert.equal(JSON.parse(blocked.stdout).hookSpecificOutput.permissionDecision, 'deny');
  const pass = run(JSON.stringify(event('node --test example.test.mjs')));
  assert.equal(pass.status, 0);
  assert.equal(pass.stdout, '');
  const malformed = run('{');
  assert.equal(malformed.status, 0);
  assert.equal(malformed.stdout, '');
  assert.match(malformed.stderr, /no decision was made/u);
  for (const payload of [null, [], {}, {tool_input: 'moon test'},
    {...event('moon test'), tool_input: {command: ['moon', 'test']}},
    {...event('moon test'), hook_event_name: 'Unknown'}]) {
    const unknown = run(JSON.stringify(payload));
    assert.equal(unknown.status, 0);
    assert.equal(unknown.stdout, '');
  }
});

test('inactive client examples name the corresponding adapter with a bounded hook timeout', () => {
  for (const [client, file] of [['codex', 'codex-local-checks-hooks.json'],
    ['claude', 'claude-local-checks-settings.json']]) {
    const example = JSON.parse(readFileSync(new URL(`../docs/examples/${file}`, import.meta.url), 'utf8'));
    const [entry] = example.hooks.PreToolUse;
    assert.equal(entry.matcher, '^Bash$');
    assert.equal(entry.hooks[0].type, 'command');
    assert.equal(entry.hooks[0].timeout, 5);
    assert.equal(entry.hooks[0].command,
      `node "/absolute/path/to/actql/scripts/${client}-local-checks-hook.mjs"`);
  }
});
