import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createOwnedScratch} from './owned-scratch.mjs';

const scratchRoot = process.env.ACTQL_TEST_SCRATCH_ROOT ?? tmpdir();
const scratch = await createOwnedScratch({parent: scratchRoot,
  prefix: 'actql-retained-task-', label: 'Native retained task file'});
const root = scratch.path;
const moon = process.env.MOON_HOME
  ? join(process.env.MOON_HOME, 'bin', 'moon')
  : 'moon';

{
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
        ACTQL_TEST_NATIVE_RETAINED_TASK_FILE_ROOT: root,
        ACTQL_REQUIRE_NATIVE_RETAINED_TEST: '1',
      },
      stdio: 'inherit',
    },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`native retained task test failed: ${result.signal ?? result.status}`);
  }
  scratch.passed();
}
