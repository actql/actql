import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { hash } from './inventory.mjs';
export function classify(paths, failure = null) {
  if (failure) return { required: true, reason: `Cannot establish diff: ${failure}`, paths: [] };
  if (!paths.length) return { required: true, reason: 'Empty diff cannot establish unchanged assumptions', paths };
  // Only these reviewed presentation-only files can skip fresh exploration.
  // Unknown paths, specifications, dependencies, CI and every runtime/proof
  // assumption fail open to exploration, including files not in the pilot.
  const harmless = /^(README\.md|LICENSE|CONTRIBUTING\.md)$/;
  const relevant = paths.filter(path => !harmless.test(path));
  return { required: relevant.length > 0, reason: relevant.length
    ? 'Runtime, proof, build, CI, specification or unclassified change' : 'Only reviewed presentation-only files changed', paths };
}
export function decision(root, env = process.env) {
  const git = args => spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  const head = git(['rev-parse', 'HEAD']);
  let base = env.ACTQL_PIPELINE_BASE;
  if (!base && env.GITHUB_EVENT_PATH) {
    try {
      const event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH));
      base = event.pull_request?.base?.sha ?? event.before;
    } catch { /* Missing/invalid event is handled by the fail-open rule. */ }
  }
  const diff = base && /^[0-9a-f]{40}$/.test(base) ? git(['diff', '--name-only', base, 'HEAD']) : null;
  const result = classify(diff?.status === 0 ? diff.stdout.trim().split('\n').filter(Boolean) : [],
    diff?.status === 0 ? null : 'missing base, invalid base or git diff failed');
  return { ...result, revision: head.status === 0 ? head.stdout.trim() : null, base: base ?? null,
    classifierDigest: hash(readFileSync(new URL('./exploration-impact.mjs', import.meta.url))) };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const result = decision(root);
  mkdirSync(`${root}/.artifacts/relation-pipeline`, { recursive: true });
  writeFileSync(`${root}/.artifacts/relation-pipeline/exploration-decision.json`, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result));
}
