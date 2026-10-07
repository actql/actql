// Ordinary public Clients against an installed Host in a fresh process.
import {appendFile, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
const options = JSON.parse(await new Promise(resolve => {
  let input = ''; process.stdin.setEncoding('utf8');
  process.stdin.on('data', chunk => {input += chunk;});
  process.stdin.on('end', () => resolve(input));
}));
const {root, runtime, entrance, phase, program} = options;
const {connect} = await import(runtime.client);
const {getSubmissionInput} = await import(runtime.sdk);
const {openInstalledRemoteHttpHost} = await import(runtime.httpHost);
const keys = JSON.parse(await readFile(join(root, 'keys.json'), 'utf8'));
const principalId = userInfo().username;
let computes = 0, client, host, server, report;
const progress = boundary => appendFile(join(root, `${phase}.progress.jsonl`),
  JSON.stringify({boundary, at: new Date().toISOString(), computes}) + '\n');
const authorization = {
  accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
    account_id: 'submission-custody', entries: [{entry_id: 'acceptance', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId, publicKey: keys.publicKey}],
  reviewReaders: [principalId], hostKey: {keyId: 'host', privateKey: keys.privateKey},
  observe(name) {if (name === 'computed') computes++;},
};
try {
  await progress('opening_host');
  const installation = {directory: join(root, 'host'), authorization};
  if (entrance === 'local') client = await connect({mode: 'local', owner: 'local', durability: 'durable', installation});
  else {
    const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(root, name))));
    setDefaultCACertificates([...getCACertificates('default'), cert.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation, authenticate: () => principalId});
    server = createServer({key, cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', token: 'fixture-owner', durability: 'durable',
      endpoint: `https://127.0.0.1:${server.address().port}/`});
  }
  await progress('connected');
  const originalPath = join(root, 'original-submission-input.json');
  const original = phase === 'initial'
    ? {submissionRef: client.newSubmission({nonce: 'original-submission'}),
      kind: 'program', input: program, parameters: null}
    : JSON.parse(await readFile(originalPath, 'utf8'));
  if (phase === 'initial') await writeFile(originalPath, JSON.stringify(original));
  await progress('original_input_retained');
  try {
    const run = await client.start(original.input, {submissionRef: original.submissionRef,
      parameters: original.parameters});
    await progress('run_admitted');
    const state = await run.wait({signal: AbortSignal.timeout(15000)});
    await progress('terminal_observed');
    report = {outcome: 'accepted', ref: run.ref, submissionRef: original.submissionRef,
      state, rows: await run.result('answer').all()};
    await progress('rows_delivered');
  } catch (error) {
    report = {outcome: 'unknown', code: error.code,
      requestId: getSubmissionInput(error)?.requestId,
      submissionRef: getSubmissionInput(error)?.submissionRef, message: error.message};
  }
  report.lookup = await client.lookupSubmission(original.submissionRef);
  await progress('original_submission_looked_up');
  report.computes = computes;
} catch (error) {
  const causes = [];
  for (let cause = error.cause; cause && causes.length < 8; cause = cause.cause) {
    causes.push({name: cause.name, code: cause.code});
  }
  report = {error: error.code ?? error.message, stack: error.stack, causes};
}
finally {
  await client?.close();
  await progress('client_closed');
  if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
  await host?.close();
}
await writeFile(join(root, `${phase}.json`), JSON.stringify(report));
process.exit(report.error === undefined ? 0 : 1);
