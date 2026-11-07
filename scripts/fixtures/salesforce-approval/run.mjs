// Copy this fixture directory into an external ordinary package installation.
// The configuration file belongs to the fresh consumer, never to the package.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {createPrivateKey, sign} from 'node:crypto';
import {connect} from '@actql/node';
import {runSalesforceApprovalPhase} from './workflow.mjs';

const [phase, configurationPath, receiptPrefix] = process.argv.slice(2);
assert.ok(['capture', 'approve', 'recover'].includes(phase));
assert.ok(configurationPath && receiptPrefix);
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
const programs = {update: await readFile(new URL('update.aql', import.meta.url), 'utf8'),
  read: await readFile(new URL('read.aql', import.meta.url), 'utf8')};
// Approval is a separate explicit command. A configured operator uses the
// existing signed resolution API; mock uses the existing default Local signer.
const approve = configuration.signer === undefined ?
  (client, captured) => client.approve(captured.checkpointId) : async (client, captured) => {
    const {keyId, reviewerId, privateKeyPath} = configuration.signer;
    const key = createPrivateKey(await readFile(privateKeyPath, 'utf8'));
    return client.resolveCheckpoints([{checkpoint: captured.summary, decision: 'approved'}],
      {signer: {keyId, reviewerId, authorityScopeCid: captured.ref.authorityScopeCid,
        sign: bytes => sign(null, bytes, key)}});
  };
const client = await connect(configuration.connect);
await runSalesforceApprovalPhase({phase, client, programs, selection: configuration.selection,
  approve,
  load: async name => JSON.parse(await readFile(receiptPrefix + '.' + name + '.json', 'utf8')),
  save: (name, value) => writeFile(receiptPrefix + '.' + name + '.json',
    JSON.stringify(value) + '\n', {encoding: 'utf8', mode: 0o600, flag: 'wx'}),
});
console.log(JSON.stringify({phase, status: 'passed', publicClientClose: 'returned'}));
