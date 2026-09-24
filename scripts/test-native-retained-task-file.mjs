import {spawnSync} from 'node:child_process';
import {mkdtemp, mkdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const scratchRoot = process.env.ACTQL_TEST_SCRATCH_ROOT ?? tmpdir();
await mkdir(scratchRoot, {recursive: true});
const root = await mkdtemp(join(scratchRoot, 'actql-retained-task-'));
const moon = process.env.MOON_HOME
  ? join(process.env.MOON_HOME, 'bin', 'moon')
  : 'moon';

try {
  const result = spawnSync(
    moon,
    [
      'test',
      '--target',
      'native',
      'src/platform_native/retained_task_file',
      '--deny-warn',
    ],
    {
      cwd: new URL('../', import.meta.url),
      env: {
        ...process.env,
        ACTQL_TEST_NATIVE_STORE_ROOT: root,
        ACTQL_REQUIRE_NATIVE_RETAINED_TEST: '1',
      },
      stdio: 'inherit',
    },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`native retained task test failed: ${result.signal ?? result.status}`);
  }
} finally {
  await rm(root, {recursive: true, force: true});
}
