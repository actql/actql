import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {join} from 'node:path';
import {userInfo} from 'node:os';

// Used unchanged by source and real packed consumers. No provider is selected.
export async function runInstalledConnectorTableAcceptance({connect,
  createInstalledConnectorTable, openInstalledRemoteHttpHost, directory, program}) {
  let loaderCalls = 0;
  const entry = {name: 'fixture', source: {
    profileVersion: 'actql-installed-fixture-source/0.1',
    load() {loaderCalls++; throw new Error('UnselectedConnectorLoaded');},
  }};
  const firstTable = createInstalledConnectorTable([entry]);
  const otherTable = createInstalledConnectorTable([entry]);
  const emptyTable = createInstalledConnectorTable([]);
  const keys = generateKeyPairSync('ed25519');
  const authorization = {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'table-fixture', entries: [{entry_id: 'host-read', outcome: 'allow',
        principal: {any_of: [userInfo().username]},
        connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/answer', 'run']},
        operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'values', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  };
  const configuration = {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(directory, 'first'), authorization,
      connectorTable: firstTable}};
  const clients = [];
  try {
    const first = await connect(configuration); clients.push(first);
    const sibling = await connect(configuration); clients.push(sibling);
    await assert.rejects(connect({...configuration, installation: {
      ...configuration.installation, connectorTable: otherTable}}),
    {message: 'InstalledHostConfigurationMismatch'});
    await assert.rejects(connect({...configuration, installation: {
      ...configuration.installation, connectorTable: {...firstTable}}}),
    {code: 'InvalidInstalledConnectorTable'});
    const other = await connect({...configuration, installation: {
      ...configuration.installation, directory: join(directory, 'other'),
      connectorTable: otherTable}}); clients.push(other);
    const empty = await connect({...configuration, installation: {
      ...configuration.installation, directory: join(directory, 'empty'),
      connectorTable: emptyTable}}); clients.push(empty);
    const submissionRef = first.newSubmission({nonce: 'table-original'});
    const original = await first.startSource(program, {format: 'json', submissionRef});
    assert.equal((await original.wait()).status, 'succeeded');
    await first.close();
    assert.deepEqual(await (await sibling.attach(original.ref)).result('answer').all(),
      [{id: 1}, {id: 2}]);
    for (const client of [other, empty]) {
      const execution = await client.startSource(program, {format: 'json'});
      assert.equal((await execution.wait()).status, 'succeeded');
      assert.deepEqual(await execution.result('answer').all(), [{id: 1}, {id: 2}]);
    }
    assert.equal(loaderCalls, 0);
    await assert.rejects(openInstalledRemoteHttpHost({
      directory: join(directory, 'http-forged'), authenticate: () => userInfo().username,
      connectorTable: {...emptyTable}}), {code: 'InvalidInstalledConnectorTable'});
    const http = await openInstalledRemoteHttpHost({directory: join(directory, 'http'),
      authenticate: () => userInfo().username, connectorTable: emptyTable});
    await http.close();
    return {sameHandleShared: true, otherHandleRefused: true,
      separateRoots: true, emptyTableValues: true, explicitHttpStartup: true, loaderCalls};
  } finally {
    for (const client of clients.reverse()) await client.close();
  }
}
