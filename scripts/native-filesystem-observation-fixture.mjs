import {chmodSync, mkdirSync, symlinkSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';

// Fixed independent fixtures for the filesystem package's Native tests. Each
// invocation owns a new namespace; no caller path is adopted or rewritten.
export function nativeFilesystemObservationFixtures(parent) {
  const root = join(parent, 'filesystem-observations');
  mkdirSync(root, {mode: 0o700});
  const directory = relative => {
    const path = join(root, relative);
    mkdirSync(path, {recursive: true, mode: 0o700});
    return path;
  };
  const file = (relative, content = 'abc') => {
    const path = join(root, relative);
    writeFileSync(path, content, {flag: 'wx', mode: 0o644});
    chmodSync(path, 0o644);
    return path;
  };
  const ordinary = directory('ordinary');
  const sentinel = file('sentinel', 'unchanged');
  symlinkSync(sentinel, join(ordinary, 'foreign link.json'));

  const observations = directory('files');
  for (const name of ['exact', 'mode', 'overwrite', 'missing', 'symlink', 'directory']) {
    directory(`files/${name}`);
    if (['exact', 'mode', 'overwrite'].includes(name)) file(`files/${name}/file`);
  }
  symlinkSync(sentinel, join(observations, 'symlink/file'));
  directory('files/directory/file');

  const namespaces = directory('directories');
  for (const name of ['exact', 'replacement', 'mode', 'cleanup']) directory(`directories/${name}`);
  symlinkSync(join(namespaces, 'exact'), join(namespaces, 'alias'), 'dir');
  file('directories/cleanup/file');
  for (const name of ['scope-exact', 'scope-replacement']) {
    directory(`directories/${name}/node_modules/@actql`);
  }
  directory('directories/scope-alias/node_modules');
  symlinkSync(join(namespaces, 'scope-exact/node_modules/@actql'),
    join(namespaces, 'scope-alias/node_modules/@actql'), 'dir');

  const census = directory('census');
  for (const name of ['exact', 'cleanup', 'missing', 'extra', 'extra-empty', 'symlink', 'wrong-kind']) {
    directory(`census/${name}`);
    if (name !== 'missing') file(`census/${name}/LICENSE`);
    if (name === 'wrong-kind') file(`census/${name}/bin`);
    else if (name === 'symlink') symlinkSync(join(namespaces, 'exact'), join(census, name, 'bin'), 'dir');
    else directory(`census/${name}/bin`);
  }
  file('census/extra/extra');
  directory('census/extra-empty/extra');
  directory('census/empty');
  directory('census/scoped-exact/@actql');
  directory('census/scoped-file');
  file('census/scoped-file/@actql');
  directory('census/scoped-other/@other');
  directory('census/scoped-extra/@actql');
  directory('census/scoped-extra/extra');
  directory('census/scoped-symlink');
  symlinkSync(join(census, 'scoped-exact/@actql'), join(census, 'scoped-symlink/@actql'), 'dir');
  return {
    ACTQL_TEST_NATIVE_ORDINARY_FILE_ROOT: ordinary,
    ACTQL_TEST_NATIVE_FILE_OBSERVATION_ROOT: observations,
    ACTQL_TEST_NATIVE_DIRECTORY_OBSERVATION_ROOT: namespaces,
    ACTQL_TEST_NATIVE_CENSUS_ROOT: census,
  };
}
