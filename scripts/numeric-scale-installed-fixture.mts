// Reuse the existing normal-tar consumer and its complete installed inventory.
// Only this authored actor is copied; product modules stay in the installation.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {constants} from 'node:fs';
import {copyFile, readFile, realpath} from 'node:fs/promises';
import {join, relative, isAbsolute} from 'node:path';
import {prepareHealthPackages} from './health-monitor-adapters.mjs';
import {checkoutState} from './packed-client-packages.mjs';

type ActorLocation = {repository: string; consumer: string};
type Launcher = {consumer: string; actor: string};
type ConsumerOptions = Pick<Parameters<typeof prepareHealthPackages>[0], 'repository' | 'command'> & {directory: string};

export async function stageNumericScaleActor({repository, consumer}: ActorLocation) {
  repository = await realpath(repository); consumer = await realpath(consumer);
  const suffix = relative(repository, consumer);
  assert(suffix === '..' || suffix.startsWith('../') || isAbsolute(suffix),
    'NumericConsumerMustBeOutsideSource');
  const source = join(repository, 'adapters/host-node/fixtures/numeric-scale-public-process.mjs');
  const actor = join(consumer, 'numeric-scale-public-process.mjs');
  // This actor has only built-in imports and the public installed @actql/node
  // entry. It has no relative Source dependency or import rewriting step.
  await copyFile(source, actor, constants.COPYFILE_EXCL);
  assert.deepEqual(await readFile(actor), await readFile(source));
  return actor;
}

export async function prepareNumericScaleConsumer({repository, directory, command}: ConsumerOptions) {
  const retained = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  assert(typeof retained === 'string' && retained.length > 0,
    'NumericScaleRequiresMatchingNormalClientPackages');
  const state = checkoutState(repository);
  assert(state.clean, 'NumericScaleRequiresCleanSource');
  const prepared = await prepareHealthPackages({repository, root: directory,
    source: {sha: state.revision, dirty: false}, retained, command});
  return {...prepared, actor: await stageNumericScaleActor({repository, consumer: prepared.consumer})};
}

export function runNumericScalePhase(prepared: Launcher, phase: string, directory: string,
  referencePath: string, count: number) {
  const env = {...process.env}; delete env.NODE_PATH; delete env.NODE_OPTIONS;
  const child = spawnSync(process.execPath, [prepared.actor, phase, directory, referencePath, String(count)],
    {cwd: prepared.consumer, env, encoding: 'utf8', timeout: 360000, maxBuffer: 8 * 1024 * 1024});
  assert.ifError(child.error);
  assert.equal(child.signal, null, child.stderr);
  assert.equal(child.status, 0, child.stderr);
  const lines = child.stdout.trim().split('\n');
  const report = JSON.parse(lines.at(-1)!) as {inputWireBytes?: number};
  const {inputWireBytes, ...completion} = report;
  assert.deepEqual(completion, {phase, rowsVerified: count, closeReturned: true, pid: child.pid});
  if (phase === 'produce-source') {
    assert(Number.isSafeInteger(inputWireBytes) && inputWireBytes! > 1048576);
    console.log(`Numeric JSON Source input: ${inputWireBytes} UTF8 bytes, ${count} rows`);
  } else assert.equal(inputWireBytes, undefined);
}
