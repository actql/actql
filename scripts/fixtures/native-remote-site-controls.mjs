// The full HTTP runner and focused diagnostic execute the same original
// Native Site CLI controls against their own current HTTPS peer and journal.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {once} from 'node:events';
import {join} from 'node:path';

export async function testNativeRemoteSiteControls({
  moon, nativeBuildRoot, repository, root, sqliteLibrary, library, nativeHttpOrigin,
  remoteRequestCid, stalePollObserved, releaseStalePoll,
}) {
  execFileSync(moon, [
    'build', '--target', 'native', 'src/cmd/native_remote_site',
  ], {cwd: repository, stdio: 'inherit'});
  const executable = join(
    nativeBuildRoot,
    'native/debug/build/cmd/native_remote_site/' +
      'native_remote_site.exe',
  );
  const journalPath = join(root, 'native-site-agent.sqlite3');
  const revisionA = `sha256:${'a'.repeat(64)}`;
  const revisionB = `sha256:${'b'.repeat(64)}`;
  const common = [
    '--sqlite-library', sqliteLibrary,
    '--journal-path', journalPath,
    '--site-key', 'native-site',
    '--site-generation', '1',
    '--runtime-revision', revisionA,
  ];
  const startAgent = arguments_ => {
    const child = spawn(executable, [...common, ...arguments_], {
      cwd: repository,
      env: {PATH: '/usr/bin:/bin', LANG: 'C'},
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on('data', chunk => stdout.push(chunk));
    child.stderr.on('data', chunk => stderr.push(chunk));
    return (async () => {
      const [code, signal] = await once(child, 'exit');
      return Object.freeze({
        code,
        signal,
        stdout: Buffer.concat(stdout).toString('utf8'),
        stderr: Buffer.concat(stderr).toString('utf8'),
      });
    })();
  };
  const runAgent = arguments_ => startAgent(arguments_);
  const rejectedDispatch = await runAgent([
    '--http-library', library,
    '--ca', join(root, 'ca.crt'),
    '--cert', join(root, 'client.crt'),
    '--key', join(root, 'client.key'),
    '--poll-url', `${nativeHttpOrigin}/outbound/poll`,
    '--observation-url',
    `${nativeHttpOrigin}/outbound/observation`,
    'poll-once',
  ]);
  assert.notEqual(rejectedDispatch.code, 0);
  assert.equal(
    rejectedDispatch.stdout,
    'actql-native-remote-site: dispatch requires a runtime-linked ' +
      'Site component\n',
  );
  const queried = await runAgent([
    '--http-library', library,
    '--ca', join(root, 'ca.crt'),
    '--cert', join(root, 'client.crt'),
    '--key', join(root, 'client.key'),
    '--poll-url', `${nativeHttpOrigin}/outbound/query`,
    '--observation-url',
    `${nativeHttpOrigin}/outbound/status-observation`,
    'poll-once',
  ]);
  assert.equal(queried.code, 0, queried.stderr);
  assert.deepEqual(JSON.parse(queried.stdout), {
    kind: 'not-seen',
    request_cid: remoteRequestCid,
    revision: 0,
  });
  const staleProcess = startAgent([
    '--http-library', library,
    '--ca', join(root, 'ca.crt'),
    '--cert', join(root, 'client.crt'),
    '--key', join(root, 'client.key'),
    '--poll-url', `${nativeHttpOrigin}/outbound/stale-poll`,
    '--observation-url',
    `${nativeHttpOrigin}/outbound/stale-observation`,
    'poll-once',
  ]);
  await stalePollObserved;
  const restarted = await runAgent([
    'restart',
    '--next-generation', '2',
    '--next-runtime-revision', revisionB,
  ]);
  assert.equal(restarted.code, 0, restarted.stderr);
  assert.deepEqual(JSON.parse(restarted.stdout), {reconciled_records: 0});
  releaseStalePoll();
  const fenced = await staleProcess;
  assert.notEqual(fenced.code, 0);
  const stale = await runAgent(['restart',
    '--next-generation', '2',
    '--next-runtime-revision', revisionB,
  ]);
  assert.notEqual(stale.code, 0);
}
