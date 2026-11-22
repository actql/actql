// Shared public consumer entry; the existing workflow owns every connected
// Client, original Run, approval and cleanup. No provider credentials are read.
import {open, readFile, writeFile} from 'node:fs/promises';
import {constants} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createPrivateKey, sign} from 'node:crypto';
import {admitAuthoredRecordApprovalCase} from './workflow.mjs';

const text = value => typeof value === 'string' && value.trim().length > 0;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const maxAuthoredCaseBytes = 1024 * 1024;

async function readAuthoredCase(path) {
  const file = await open(path, constants.O_RDONLY | constants.O_NONBLOCK);
  try {
    const info = await file.stat();
    if (!info.isFile() || info.size > maxAuthoredCaseBytes) throw new TypeError('InvalidRecordApprovalCaseFile');
    const chunks = [];
    let size = 0;
    for await (const bytes of file.createReadStream({start: 0, end: maxAuthoredCaseBytes, autoClose: false})) {
      size += bytes.length;
      if (size > maxAuthoredCaseBytes) throw new TypeError('InvalidRecordApprovalCaseFile');
      chunks.push(bytes);
    }
    try {
      const wire = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(Buffer.concat(chunks, size));
      return admitAuthoredRecordApprovalCase(JSON.parse(wire));
    } catch {
      throw new TypeError('InvalidRecordApprovalAuthoredCase');
    }
  } finally {await file.close();}
}

export async function runRecordApprovalCommand({argv, programDirectory, connect,
  runPhase, createDefinition, retainProgramInputs = false, log = value => console.log(JSON.stringify(value))}) {
  if (typeof retainProgramInputs !== 'boolean') throw new TypeError('InvalidRecordApprovalFixtureMode');
  const [phase, configurationPath, receiptPrefix] = argv;
  if (argv.length !== 3 || !['check', 'capture', 'approve', 'reject', 'recover'].includes(phase) ||
      !text(configurationPath) || !text(receiptPrefix)) {
    throw new TypeError('Expected check|capture|approve|reject|recover CONFIGURATION RECEIPT_PREFIX');
  }
  const path = resolve(configurationPath);
  let configuration;
  const wire = await readFile(path, 'utf8');
  try {configuration = JSON.parse(wire);}
  catch {throw new TypeError('InvalidRecordApprovalConfiguration');}
  if (!object(configuration) || !object(configuration.connect)) {
    throw new TypeError('InvalidRecordApprovalConfiguration');
  }
  const {decision = 'approved'} = configuration;
  if (!['approved', 'rejected'].includes(decision) ||
      (phase === 'approve' && decision !== 'approved') || (phase === 'reject' && decision !== 'rejected')) {
    throw new TypeError('InvalidRecordApprovalDecision');
  }
  if (configuration.operatorModulePath !== undefined && !text(configuration.operatorModulePath)) {
    throw new TypeError('InvalidRecordApprovalOperatorModule');
  }
  const signer = configuration.signer;
  if (signer !== undefined && (!object(signer) ||
      !['keyId', 'reviewerId', 'privateKeyPath'].every(name => text(signer[name])))) {
    throw new TypeError('InvalidRecordApprovalSigner');
  }
  let definition, programs;
  if (Object.hasOwn(configuration, 'casePath')) {
    if (!text(configuration.casePath) || Object.hasOwn(configuration, 'selection') || retainProgramInputs) {
      throw new TypeError('InvalidRecordApprovalCaseSelection');
    }
    definition = await readAuthoredCase(resolve(dirname(path), configuration.casePath));
  } else if (retainProgramInputs && ['approve', 'reject', 'recover'].includes(phase)) {
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
  if (definition === undefined) createDefinition(programs, configuration.selection);
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
  // Capture and recovery leave the operator key closed. A resolution loads it after
  // the existing workflow has re-read the SAME original sealed Review.
  const resolveDecision = signer === undefined ?
    (client, captured) => client[decision === 'approved' ? 'approve' : 'reject'](captured.checkpointId) : async (client, captured) => {
      const key = createPrivateKey(await readFile(resolve(dirname(path), signer.privateKeyPath), 'utf8'));
      return client.resolveCheckpoints([{checkpoint: captured.summary, decision}],
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
  await runPhase({phase, client,
    ...(definition === undefined ? {programs, selection: configuration.selection} : {definition}),
    ...(decision === 'approved' ? {approve: resolveDecision} : {decision, reject: resolveDecision}),
    load: async name => JSON.parse(await readFile(receiptPrefix + '.' + name + '.json', 'utf8')),
    save: (name, value) => writeFile(receiptPrefix + '.' + name + '.json',
      JSON.stringify(value) + '\n', {encoding: 'utf8', mode: 0o600, flag: 'wx'}),
  });
  log({phase, status: 'passed', publicClientClose: 'returned',
    ...(decision === 'rejected' ? {decision} : {})});
}
