// Emitted and copied into the installed RC consumer. Product imports resolve
// through the ordinary packages installed in that consumer.
import {connect} from '@actql/node';
import {getCheckInput} from '@actql/sdk';
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {runReleaseProjectNodeAction} from '../release-project-node-action.mjs';
import {workflowWorkObservation} from '../../adapters/host-node/fixtures/work-observation.fixture.mjs';

type SequenceRequest = Parameters<typeof runReleaseProjectNodeAction>[0]['request'] & {beforeBytes?: string};

const [requestPath, responsePath] = process.argv.slice(2);
const request = JSON.parse(await readFile(requestPath, 'utf8')) as SequenceRequest;
const work = workflowWorkObservation({trackOriginal: true});
const response: Awaited<ReturnType<typeof runReleaseProjectNodeAction>> & {
  workObservation?: ReturnType<typeof work.snapshot> | ReturnType<typeof work.forOriginal>;
} = await runReleaseProjectNodeAction({request,
  getCheckInput,
  connect: options => connect({...options, installation: {...options.installation, observation: work.connection}}),
  readProgram: () => readFile(request.program!, 'utf8'),
  retainAccepted: value => writeFile(responsePath + '.accepted', JSON.stringify(value) + '\n', {flag: 'wx', mode: 0o600}),
  assertPendingTarget: () => assert.equal(readFileSync('mock/data.json', 'utf8'), request.beforeBytes,
    'Pending Run must not write the target'),
  retainClose: value => writeFile(responsePath + '.close', JSON.stringify(value) + '\n', {mode: 0o600}),
});
response.workObservation = response.original ? work.forOriginal(response.original.ref) : work.snapshot();
await writeFile(responsePath, JSON.stringify(response) + '\n', {flag: 'wx', mode: 0o600});
