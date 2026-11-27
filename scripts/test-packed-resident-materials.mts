// The installed public issuer is the one used by the real native Site fixture.
// Reuse its existing admission/executor/transfer/physical release assertions;
// do not introduce a second protocol issuer or Site admission implementation.
import {spawnSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const revision = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: repository,
  encoding: 'utf8'});
if (revision.status !== 0) throw new Error('PackedMaterialsRevisionUnavailable');
const directory = await withPackedQueryEvidence({
  scratch: process.env.ACTQL_TEST_SCRATCH_ROOT ?? join(repository, '..', '.codex-scratch'),
  revision: revision.stdout.trim(), githubOutput: process.env.GITHUB_OUTPUT,
  keepArtifacts: process.argv.includes('--keep-artifacts'),
}, async ({root, run, recordTarball}) => {
  const env = {...process.env, npm_config_cache: join(root, 'npm-cache')};
  const redelivery = process.argv.includes('--redelivery-only');
  const outputReport = process.argv.includes('--output-report-only');
  const packages = ['run-host-core', 'client-wire', ...((redelivery || outputReport) ? ['coordinator-core'] : [])];
  for (const name of packages) {
    run('npm', ['pack', '--pack-destination', root, '--json'],
      {cwd: join(repository, 'packages', name), env});
    recordTarball(join(root, `actql-${name}-0.0.0-development.tgz`));
  }
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--offline', '--ignore-scripts', '--no-save',
    ...packages.map(name => join(root, `actql-${name}-0.0.0-development.tgz`))], {cwd: root, env});
  const output = run(process.execPath,
    [join(repository, 'scripts/test-native-resident-site.mjs'),
      outputReport ? '--output-report-only' : redelivery ? '--redelivery-only' : '--materials-only'],
    {cwd: root, env: {...env, ACTQL_TEST_SCRATCH_ROOT: root,
      ACTQL_TEST_RUN_HOST_CORE_MODULE: join(root,
        'node_modules/@actql/run-host-core/index.mjs'),
      ...((redelivery || outputReport) ? {ACTQL_TEST_COORDINATOR_CORE_MODULE: join(root,
        'node_modules/@actql/coordinator-core/index.mjs')} : {})}, timeout: 900_000});
  console.log(output.trimEnd());
});
console.log(`Packed resident materials evidence: ${directory}`);
