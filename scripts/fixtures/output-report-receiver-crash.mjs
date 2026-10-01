// Acceptance fixture: crash the real durable receiver after its commit and
// before any ACK reaches the Site. Do not close/checkpoint the SQLite owner.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {runtimeCore} from '../../adapters/host-common/runtime-core.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  '../../adapters/host-node/sqlite-coordinator-journal.mjs';
import {createRemoteSiteCoordinator} from
  '../../adapters/host-node/remote-site-coordinator.mjs';

const [modulePath, directory, inputPath] = process.argv.slice(2);
const core = runtimeCore(await import(pathToFileURL(modulePath).href));
const control = core.remoteSiteControl;
const store = openSqliteCoordinatorDispatchJournal(directory,
  {coordinatorAuthority: 'cloud-coordinator', maxDeliveryBytes: 1_048_576});
const receiver = createRemoteSiteCoordinator({control,
  journal: control.createCoordinatorJournal('cloud-coordinator'), store,
  output: () => { throw new Error('ReceiverMustNotRepeatTransfer'); },
  transferControl: core.remoteTransferControl});
const input = JSON.parse(await readFile(inputPath, 'utf8'));
const receipt = receiver.receiveObservation(input);
assert.equal(typeof receipt.outputAckWire, 'string');
assert.equal(store.inspectOutput(receiver.recoveredOutputs[0].record, control).progress, 2);
process.kill(process.pid, 'SIGKILL');
