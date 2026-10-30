// Cold metadata verification must not load installed SDK/runtime dependencies.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {writeInertPythonReleaseCohort} from './fixtures/release-python-wheels.mjs';

test('cold Python cohort verifier keeps complete wheel checks without SDK or site packages', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-cold-release-verifier-')), directory = join(root, 'cohort');
  t.after(() => rm(root, {recursive: true}));
  const python = execFileSync('python3', ['-E', '-S', '-c', 'import sys;print(sys.executable)'], {encoding: 'utf8'}).trim();
  await writeInertPythonReleaseCohort(directory, python);
  const args = ['-E', '-S', 'scripts/python_release_cohort.py', '--verify-directory', directory,
    '--source', 'a'.repeat(40), '--version', '0.0.7rc1'];
  const verified = JSON.parse(execFileSync(python, args, {encoding: 'utf8', stdio: 'pipe'}));
  assert.deepEqual(verified.cohort.wheels.map(item => item.distribution), ['actql-sdk', 'actql-local-runtime', 'actql']);
  assert.match(verified.qualification, /not component execution, install, Linux or public acceptance/u);
  const wheel = join(directory, 'wheels', verified.cohort.wheels[0].file), original = await readFile(wheel);
  await writeFile(wheel, Buffer.concat([original, Buffer.from('changed')]));
  assert.throws(() => execFileSync(python, args, {encoding: 'utf8', stdio: 'pipe'}),
    failure => failure.status !== 0 && failure.stderr.includes('Python release wheel bytes changed'));
});
