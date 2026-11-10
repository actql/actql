// Reuse the existing normal-tar consumer and its complete installed inventory.
// Only this authored actor is copied; product modules stay in the installation.
import assert from 'node:assert/strict';
import {constants} from 'node:fs';
import {copyFile, readFile, realpath} from 'node:fs/promises';
import {join, relative, isAbsolute} from 'node:path';
import {prepareHealthPackages} from './health-monitor-adapters.mjs';
import {checkoutState} from './packed-client-packages.mjs';

export async function stageNumericScaleActor({repository, consumer}) {
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

export async function prepareNumericScaleConsumer({repository, directory, command}) {
  const retained = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  assert(typeof retained === 'string' && retained.length > 0,
    'NumericScaleRequiresMatchingNormalClientPackages');
  const state = checkoutState(repository);
  assert(state.clean, 'NumericScaleRequiresCleanSource');
  const prepared = await prepareHealthPackages({repository, root: directory,
    source: {sha: state.revision, dirty: false}, retained, command});
  return {...prepared, actor: await stageNumericScaleActor({repository, consumer: prepared.consumer})};
}
