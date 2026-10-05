// Generate Salesforce record-update Host state at four phases with the
// checkout's own product code, through the public Client and real Host
// processes only. Usage:
//   node adapters/connectors/salesforce/test/cross-version/generate-update-state.mjs <output>
// A Host's authority scope and Store authority are derived from its absolute
// root and principal, so saved state resumes only at its original root, by
// the same user, on the same machine. Each phase runs in
// `<output>/work/<phase>` (its root) and, once its Host has stopped, is
// archived unchanged (with its Store's hard links) as
// `<output>/saved/<phase>/state.tar`, beside `manifest.json`: the
// generating checkout, the runtime it ran, the org's origin, the root, the
// independent expectations and the digest of every saved file. No journal
// or Store is edited.
import {execFileSync} from 'node:child_process';
import {mkdir, rm, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {STATE_VERSION, approve, digests, install, kindProgram, kindWrites,
  newKeys, openHost, openOrg, runtimeBundleCid, startHostProcess,
  waitFor} from './update-state.mjs';

const repository = fileURLToPath(new URL('../../../../../', import.meta.url));
const output = resolve(process.argv[2] ?? '');
if (!process.argv[2]) throw new Error('Usage: generate-update-state.mjs <output>');

// The org's stored records; the phases update Name to the record's Id.
const records = [1, 2, 3].map(index => ({Id: `a0000000000000${index}`,
  Name: `record-${index}`, External_Key__c: `key-${index}`}));

function issueOrgCertificates(directory) {
  const openssl = (...args) => execFileSync('openssl', args,
    {cwd: directory, stdio: 'ignore'});
  openssl('genrsa', '-out', 'ca.key', '2048');
  openssl('req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
    '-subj', '/CN=ActQL Cross-Version Test CA', '-days', '3650');
  openssl('genrsa', '-out', 'resource.key', '2048');
  openssl('req', '-new', '-key', 'resource.key', '-out', 'resource.csr',
    '-subj', '/CN=localhost');
  execFileSync('sh', ['-c',
    'printf "subjectAltName=DNS:localhost,IP:127.0.0.1\\n" > resource.ext'],
  {cwd: directory});
  openssl('x509', '-req', '-in', 'resource.csr', '-CA', 'ca.crt', '-CAkey',
    'ca.key', '-CAcreateserial', '-out', 'resource.crt', '-days', '3650',
    '-extfile', 'resource.ext');
}

const git = (...args) => execFileSync('git', args, {cwd: repository,
  encoding: 'utf8'}).trim();

// The write kind of a phase: `create-…` and `upsert-…` phases write that
// kind; every other phase updates.
const kindOf = name => name.startsWith('create-') ? 'create'
  : name.startsWith('upsert-') ? 'upsert' : 'update';

async function phase(name, ids, drive) {
  const root = join(output, 'work', name);
  const pristine = join(output, 'saved', name);
  await rm(root, {recursive: true, force: true});
  await rm(pristine, {recursive: true, force: true});
  const tls = join(root, 'org-tls');
  await mkdir(tls, {recursive: true});
  issueOrgCertificates(tls);
  const keys = newKeys();
  const afters = [];
  const t = {after: fn => afters.push(fn)};
  let held;
  const heldWrite = new Promise(resolveHeld => { held = resolveHeld; });
  const holdWrites = name.endsWith('unknown-after-send') ? [1]
    : name === 'response-saved' ? [2] : [];
  const org = await openOrg(t, {port: 0, certificateDirectory: tls, records,
    holdWrites, onHeldWrite: held});
  try {
    const installation = await install({root, org, keys,
      writes: [kindWrites[kindOf(name)]]});
    const tlsRoot = join(root, 'host-tls');
    await mkdir(tlsRoot, {recursive: true});
    const context = {installation, org, keys, tlsRoot, heldWrite,
      orgId: org.orgId, kind: kindOf(name)};
    const requestRef = await drive(context, ids);
    const manifest = {
      version: STATE_VERSION, phase: name,
      generated_by: {checkout: git('rev-parse', 'HEAD'),
        product_paths_changed_since_checkout: git('status', '--porcelain',
          '--', 'adapters', 'src', 'packages', 'spec')
          .split('\n').filter(line => line && !line.includes('/test/')),
        command: 'node adapters/connectors/salesforce/test/cross-version/' +
          'generate-update-state.mjs <output>'},
      runtime_bundle_cid: await runtimeBundleCid(),
      root, org: {origin: org.origin, port: new URL(org.origin).port,
        org_id: org.orgId},
      request: {ids, ref: requestRef},
      expected: {
        writes_during_generation: org.seen.filter(item =>
          item.method === 'PATCH' || item.method === 'POST').map(item =>
          `${item.method} ${decodeURIComponent(item.path.split('/')
            .slice(-2).join('/'))}`),
        records_after_generation: org.records(),
      },
    };
    await writeFile(join(root, 'keys.json'), JSON.stringify(keys));
    await mkdir(pristine, {recursive: true});
    execFileSync('tar', ['-cf', join(pristine, 'state.tar'), '-C', root, '.']);
    await writeFile(join(pristine, 'manifest.json'), JSON.stringify({
      ...manifest, digests: await digests(root)}, null, 2));
    return manifest;
  } finally {
    for (const after of afters.reverse()) await after();
  }
}

async function submitHeld(context, ids) {
  const host = await openHost(context);
  const client = await host.as('owner-token');
  const program = kindProgram(context.kind, context.installation.mappingRef,
    ids);
  const execution = await client.aql(program, {format: 'json',
    requestId: 'cross-version-update'});
  await waitFor(async () => (await execution.status()).status ===
    'waiting_checkpoint');
  await host.close();
  return execution;
}

async function approveStopped(context, execution) {
  const reviewer = await openHost(context);
  await approve(reviewer, execution, context.keys);
  await reviewer.close();
}

// Resume the approved Set in a Host process, and kill that process while the
// org holds the write.
async function killedWhileHeld(context) {
  const child = startHostProcess(context);
  const exited = new Promise(resolveExit => child.once('exit', resolveExit));
  await context.heldWrite;
  child.kill('SIGKILL');
  await exited;
}

const results = [];
results.push(await phase('held-for-approval', ['a00000000000001'],
  async context => (await submitHeld(context, ['a00000000000001'])).ref));
results.push(await phase('approval-saved', ['a00000000000001'],
  async (context, ids) => {
    const execution = await submitHeld(context, ids);
    await approveStopped(context, execution);
    return execution.ref;
  }));
results.push(await phase('unknown-after-send', ['a00000000000001'],
  async (context, ids) => {
    const execution = await submitHeld(context, ids);
    await approveStopped(context, execution);
    await killedWhileHeld(context);
    return execution.ref;
  }));
results.push(await phase('response-saved',
  ['a00000000000001', 'a00000000000003'], async (context, ids) => {
    const execution = await submitHeld(context, ids);
    await approveStopped(context, execution);
    await killedWhileHeld(context);
    return execution.ref;
  }));
// Sets of the other installed kinds, captured by the same factory.
for (const kind of ['create', 'upsert']) {
  results.push(await phase(`${kind}-held-for-approval`, ['a00000000000001'],
    async context => (await submitHeld(context, ['a00000000000001'])).ref));
  results.push(await phase(`${kind}-approval-saved`, ['a00000000000001'],
    async (context, ids) => {
      const execution = await submitHeld(context, ids);
      await approveStopped(context, execution);
      return execution.ref;
    }));
  results.push(await phase(`${kind}-unknown-after-send`, ['a00000000000001'],
    async (context, ids) => {
      const execution = await submitHeld(context, ids);
      await approveStopped(context, execution);
      await killedWhileHeld(context);
      return execution.ref;
    }));
}
console.log(JSON.stringify(results.map(result => ({phase: result.phase,
  writes: result.expected.writes_during_generation,
  runtime: result.runtime_bundle_cid})), null, 2));
process.exit(0);
