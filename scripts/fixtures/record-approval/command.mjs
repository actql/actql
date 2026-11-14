// Shared public consumer entry; the existing workflow owns every connected
// Client, original Run, approval and cleanup. No provider credentials are read.
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createPrivateKey, sign} from 'node:crypto';

const text = value => typeof value === 'string' && value.trim().length > 0;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

export async function runRecordApprovalCommand({argv, programDirectory, connect,
  runPhase, createDefinition, retainProgramInputs = false, log = value => console.log(JSON.stringify(value))}) {
  if (typeof retainProgramInputs !== 'boolean') throw new TypeError('InvalidRecordApprovalFixtureMode');
  const [phase, configurationPath, receiptPrefix] = argv;
  if (argv.length !== 3 || !['check', 'capture', 'approve', 'recover'].includes(phase) ||
      !text(configurationPath) || !text(receiptPrefix)) {
    throw new TypeError('Expected check|capture|approve|recover CONFIGURATION RECEIPT_PREFIX');
  }
  const path = resolve(configurationPath);
  let configuration;
  const wire = await readFile(path, 'utf8');
  try {configuration = JSON.parse(wire);}
  catch {throw new TypeError('InvalidRecordApprovalConfiguration');}
  if (!object(configuration) || !object(configuration.connect)) {
    throw new TypeError('InvalidRecordApprovalConfiguration');
  }
  if (configuration.operatorModulePath !== undefined && !text(configuration.operatorModulePath)) {
    throw new TypeError('InvalidRecordApprovalOperatorModule');
  }
  const signer = configuration.signer;
  if (signer !== undefined && (!object(signer) ||
      !['keyId', 'reviewerId', 'privateKeyPath'].every(name => text(signer[name])))) {
    throw new TypeError('InvalidRecordApprovalSigner');
  }
  let programs;
  if (retainProgramInputs && ['approve', 'recover'].includes(phase)) {
    try {programs = JSON.parse(await readFile(receiptPrefix + '.programs.json', 'utf8'));}
    catch (cause) {
      if (cause?.code === 'ENOENT') throw cause;
      throw new TypeError('InvalidRecordApprovalRetainedPrograms');
    }
    if (!object(programs) || Object.keys(programs).sort().join(',') !== 'read,update' ||
        !text(programs.update) || !text(programs.read)) {
      throw new TypeError('InvalidRecordApprovalRetainedPrograms');
    }
  } else programs = {update: await readFile(new URL('update.aql', programDirectory), 'utf8'),
    read: await readFile(new URL('read.aql', programDirectory), 'utf8')};
  // Use the connector's existing independent case contract before connecting.
  // This is configuration readiness, not Program/Host/provider admission.
  createDefinition(programs, configuration.selection);
  if (phase === 'check') {
    log({phase, status: 'ready', connected: false});
    return;
  }
  if (retainProgramInputs && phase === 'capture') {
    // Only authored fixture input. The existing workflow still compares its
    // complete Program hashes/parameters/oracles to the captured binding on
    // reopen; this receipt grants no Host, current or approval authority.
    await writeFile(receiptPrefix + '.programs.json', JSON.stringify(programs) + '\n',
      {encoding: 'utf8', mode: 0o600, flag: 'wx'});
  }
  // Capture/recovery never open the operator key. Approval loads it only after
  // the existing workflow has re-read the SAME original sealed Review.
  const approve = signer === undefined ?
    (client, captured) => client.approve(captured.checkpointId) : async (client, captured) => {
      const key = createPrivateKey(await readFile(resolve(dirname(path), signer.privateKeyPath), 'utf8'));
      return client.resolveCheckpoints([{checkpoint: captured.summary, decision: 'approved'}],
        {signer: {keyId: signer.keyId, reviewerId: signer.reviewerId,
          authorityScopeCid: captured.ref.authorityScopeCid,
          sign: bytes => sign(null, bytes, key)}});
    };
  // A real installation's authorization/secret callbacks cannot be JSON.
  // Load only the explicitly named trusted operator module, after check exits.
  // Its existing Host callbacks remain responsible for all access decisions.
  let connection = configuration.connect;
  if (configuration.operatorModulePath !== undefined) {
    const operator = await import(pathToFileURL(resolve(dirname(path), configuration.operatorModulePath)).href);
    if (typeof operator.configureConnection !== 'function') {
      throw new TypeError('InvalidRecordApprovalOperatorModule');
    }
    connection = await operator.configureConnection(connection);
    if (!object(connection)) throw new TypeError('InvalidRecordApprovalConnection');
  }
  const client = await connect(connection);
  await runPhase({phase, client, programs, selection: configuration.selection, approve,
    load: async name => JSON.parse(await readFile(receiptPrefix + '.' + name + '.json', 'utf8')),
    save: (name, value) => writeFile(receiptPrefix + '.' + name + '.json',
      JSON.stringify(value) + '\n', {encoding: 'utf8', mode: 0o600, flag: 'wx'}),
  });
  log({phase, status: 'passed', publicClientClose: 'returned'});
}
