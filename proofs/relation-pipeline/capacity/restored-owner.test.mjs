import test from 'node:test';
import { minimalRepository, runDriver, successful } from '../fixtures/execution-driver.mjs';

// Real executor, source inventory, physical fixture, artifact and receipt code;
// only the compiler process is synthetic. This is lifecycle, not semantic proof.
test('restored same-root owner closes the old fixture, recompiles restored bytes and preserves both receipts', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const pristine = snapshot(root);
writeFileSync(join(root, sourcePath), '// instrumented mutation\n');
execute([makeCase()], registry, 'js', false, 'capacity-mutated-minimal');
const prior = executions.at(-1), archivedPrior = readFileSync(join(root, prior.path));
writeFileSync(join(root, sourcePath), original);
assert.deepEqual(snapshot(root), pristine);
const premature = createExecutor(workspaceIdentity(root, 'normal', pristine));
assert.throws(() => premature.execute([makeCase()], registry, 'js'), /Another pipeline batch owns/);
premature.close();
assert(existsSync(join(root, fixture)), 'Non-owner close removed predecessor fixture');
closeExecutor();
assert(!existsSync(join(root, fixture)));
assert.throws(() => execute([makeCase()], registry, 'js'), /workspace is closed/);
const restored = createExecutor(workspaceIdentity(root, 'normal', pristine));
for (const target of ['js', 'wasm', 'native']) {
  restored.execute([makeCase()], registry, target, true, 'capacity-minimum-post-restore');
  const current = executions.at(-1);
  assert.notEqual(current.receipt.boundary.workspace, prior.receipt.boundary.workspace);
  assert.equal(current.receipt.boundary.root, prior.receipt.boundary.root);
  assert.equal(current.receipt.sourceDigest, pristine.digest);
  assert.equal(current.receipt.cases[0].observation.compiledSource, original);
  assert.equal(current.receipt.cases[0].observation.observedCorrespondence, true);
  assert.notEqual(current.receipt.buildIdentity, prior.receipt.buildIdentity);
  assert.deepEqual(JSON.parse(readFileSync(join(root, current.path))), current.receipt);
  for (const [path, hash] of Object.entries(current.receipt.artifacts)) assert.equal(digest(readFileSync(join(root, path))), hash);
}
restored.close();
assert(!existsSync(join(root, fixture)));
assert.throws(() => restored.execute([makeCase()], registry, 'js'), /workspace is closed/);
assert.deepEqual(readFileSync(join(root, prior.path)), archivedPrior);
assert.deepEqual(snapshot(root), pristine);
assert.equal(executions.length, 4);
`));
});
test('fresh restored owner rejects leftover instrumentation before observation', t => {
  successful(runDriver(minimalRepository(t), String.raw`
const pristine = snapshot(root);
execute([makeCase()], registry, 'js'); closeExecutor();
writeFileSync(join(root, sourcePath), '// leftover instrumentation\n');
const restored = createExecutor(workspaceIdentity(root, 'normal', pristine));
assert.throws(() => restored.execute([makeCase()], registry, 'js'), /Pristine execution source changed/);
restored.close();
assert.equal(executions.length, 1); assert(!existsSync(join(root, fixture)));
writeFileSync(join(root, sourcePath), original);
`));
});
