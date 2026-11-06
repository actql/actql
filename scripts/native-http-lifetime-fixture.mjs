// Existing test-only libcurl ABI fixture; it performs no transport.
import {execFileSync} from 'node:child_process';
import {mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

export function nativeHttpLifetimeFixture(namespace) {
  const root=fileURLToPath(new URL('../',import.meta.url));
  const directory=join(namespace,'http-lifetime');
  mkdirSync(directory,{mode:0o700});
  const module=join(directory,process.platform==='darwin'?'transport.dylib':'transport.so');
  execFileSync('cc',['-std=c11','-O0','-Wall','-Wextra','-Werror',
    ...(process.platform==='darwin'?['-dynamiclib']:['-shared','-fPIC']),
    join(root,'scripts/fixtures/native-http-lifetime-library.c'),'-o',module],
  {cwd:root,stdio:'pipe',timeout:30000});
  return {ACTQL_TEST_NATIVE_HTTP_LIFETIME_LIBRARY:module};
}
