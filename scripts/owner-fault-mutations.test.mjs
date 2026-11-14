import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

const sourceRoot = new URL('../adapters/host-common/', import.meta.url);
const mutations = [
  {
    name: 'a thrown physical commit cannot become a known unsent failure',
    module: 'sqlite-transaction.mjs',
    test: 'sqlite-transaction.test.mjs',
    selected: '^lost physical COMMIT reply retains Unknown',
    before: "phase === 'commit' || state.active !== false ?",
    after: "state.active !== false ?",
    diagnostic: /OriginalJournalCommitOutcomeUnknown/u,
  },
  {
    name: 'an observation wrapper cannot replace the original operation failure with success',
    module: 'observation.mjs',
    test: 'observation.test.mjs',
    dependencies: ['ledger-contract.generated.mjs'],
    selected: '^queue overflow and delivery failure cannot replace an operation result',
    before: '        throw cause;',
    after: '        return undefined;',
    diagnostic: /Missing expected rejection/u,
  },
];
for (const mutation of mutations) {
  test(mutation.name, t => {
    const scratch = mkdtempSync(join(tmpdir(), 'actql-if-owner-mutation-'));
    try {
      const source = readFileSync(new URL(mutation.module, sourceRoot), 'utf8');
      assert.equal(source.split(mutation.before).length, 2, 'Select the exact existing Owner fence');
      writeFileSync(join(scratch, mutation.module), source.replace(mutation.before, mutation.after));
      writeFileSync(join(scratch, mutation.test), readFileSync(new URL(mutation.test, sourceRoot)));
      for (const name of mutation.dependencies ?? []) {
        writeFileSync(join(scratch, name), readFileSync(new URL(name, sourceRoot)));
      }
      const env = {...process.env}; delete env.NODE_TEST_CONTEXT;
      const child = spawnSync(process.execPath, ['--test',
        `--test-name-pattern=${mutation.selected}`, mutation.test],
      {cwd: scratch, env, encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024});
      assert.equal(child.error, undefined);
      assert.equal(child.signal, null);
      assert.equal(child.status, 1, child.stdout + child.stderr);
      const output = child.stdout + child.stderr;
      assert.match(output, mutation.diagnostic);
      assert.match(output, /# fail 1/u);
      assert.doesNotMatch(output, /ERR_MODULE_NOT_FOUND|SyntaxError|test timed out/u);
      t.diagnostic(output);
    } finally { rmSync(scratch, {recursive: true, force: true}); }
  });
}
