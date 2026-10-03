// Explicit, optional real-history rehearsal. Ordinary CI uses small Git fixtures.
import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, writeFileSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

export function rehearsalInputs(args) {
  const usage = 'Usage: --source <commit SHA> --validator <commit SHA> --supplement <JSON file>';
  assert.equal(args.length, 6, usage);
  const options = new Map();
  for (let i = 0; i < args.length; i += 2) {
    assert(['--source', '--validator', '--supplement'].includes(args[i]) && !options.has(args[i]), usage);
    options.set(args[i], args[i + 1]);
  }
  assert(/^[0-9a-f]{40}$/.test(options.get('--source')) && /^[0-9a-f]{40}$/.test(options.get('--validator')), usage);
  assert(typeof options.get('--supplement') === 'string' && options.get('--supplement').length, usage);
  return {source: options.get('--source'), validator: options.get('--validator'), supplementFile: options.get('--supplement')};
}

export function rehearse(root, {source, validator, supplementFile}) {
  const raw = readFileSync(resolve(root, supplementFile));
  const supplement = JSON.parse(raw);
  assert(raw.equals(Buffer.from(`${JSON.stringify(supplement, null, 2)}\n`)), 'Noncanonical supplement input');
  assert(/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(supplement.id)
    && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(supplement.target?.id), 'Invalid supplement identity');
  const env = {...Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_'))), GIT_NO_REPLACE_OBJECTS: '1'};
  const git = (cwd, ...args) => {
    const result = spawnSync('git', ['--no-replace-objects', '-c', 'user.name=Foundation Replay',
      '-c', 'user.email=foundation@example.invalid', '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false', ...args],
    {cwd, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  for (const sha of [source, validator]) git(root, 'cat-file', '-e', `${sha}^{commit}`);
  const temporary = join(mkdtempSync(join(tmpdir(), 'actql-foundation-rehearsal-')), 'history');
  git(root, 'worktree', 'add', '--detach', temporary, source);
  try {
    const directory = 'proofs/relation-pipeline/foundation-declarations';
    const originalPath = `${directory}/${supplement.target.id}.json`;
    const original = readFileSync(join(temporary, originalPath));
    const digest = createHash('sha256').update(original).digest('hex');
    assert.equal(digest, supplement.target.digest, 'Original digest differs from explicit input');
    const introductions = git(temporary, 'log', '--full-history', '--diff-filter=A', '--format=%H', '--', originalPath);
    const validate = () => spawnSync(process.execPath, ['proofs/relation-pipeline/history.mjs', '--write'],
      {cwd: temporary, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
    const before = validate();
    if (before.status !== 0) assert.match(before.stderr, /Incomplete or ambiguous foundation resolution inputs/);
    git(temporary, 'merge', '--no-ff', '--no-edit', validator);
    const supplementPath = `${directory}-supplements/${supplement.id}.json`;
    if (existsSync(join(temporary, supplementPath))) {
      assert.deepEqual(readFileSync(join(temporary, supplementPath)), raw, 'Existing supplement must remain unchanged');
    } else {
      mkdirSync(join(temporary, `${directory}-supplements`), {recursive: true});
      writeFileSync(join(temporary, supplementPath), raw);
      git(temporary, 'add', supplementPath);
      git(temporary, 'commit', '-m', 'fix(proofs): append explicit late dependency receipt');
    }
    const after = validate();
    assert.equal(after.status, 0, after.stderr);
    assert.deepEqual(readFileSync(join(temporary, originalPath)), original);
    assert.equal(git(temporary, 'log', '--full-history', '--diff-filter=A', '--format=%H', '--', originalPath), introductions);
    const manifest = JSON.parse(readFileSync(join(temporary, '.artifacts/relation-pipeline/current-foundation.json')));
    const matched = manifest.supplements?.find(value => value.id === supplement.id);
    assert(matched, 'Explicit supplement missing from validated report');
    assert.deepEqual(matched.target, supplement.target);
    return {sourceRevision: source, validatorRevision: validator, supplementedHistory: git(temporary, 'rev-parse', 'HEAD'),
      originalDigest: digest, originalIntroductions: introductions.split('\n'),
      before: before.status === 0 ? 'success' : 'Incomplete or ambiguous foundation resolution inputs', after: 'success'};
  } finally {
    git(root, 'worktree', 'remove', '--force', temporary);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(rehearse(process.cwd(), rehearsalInputs(process.argv.slice(2)))));
}
