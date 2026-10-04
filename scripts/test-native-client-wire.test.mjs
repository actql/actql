import assert from 'node:assert/strict';
import {test} from 'node:test';
import {clientWireCorpus, connection, profile, admission, ref} from './fixtures/client-wire-contract-corpus.mjs';
import {validClientProfile, validClientAdmission, validRunRef, validClientConnection} from '../packages/client-wire/index.mjs';
import {execFileSync, spawn} from 'node:child_process';
import {createServer} from 'node:https';
import {chmod, copyFile, mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const root = await mkdtemp(join(tmpdir(), 'actql-native-client-'));
const openssl = (...args) => execFileSync('openssl', args,
  {cwd: root, stdio: 'ignore'});
openssl('genrsa', '-out', 'ca.key', '2048');
openssl('req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
  '-subj', '/CN=ActQL Client Test CA', '-days', '1');
await writeFile(join(root, 'server.ext'),
  'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n');
await writeFile(join(root, 'client.ext'), 'extendedKeyUsage=clientAuth\n');
for (const [name, extension] of [['server', 'server.ext'],
  ['client', 'client.ext']]) {
  openssl('genrsa', '-out', `${name}.key`, '2048');
  openssl('req', '-new', '-key', `${name}.key`, '-out', `${name}.csr`,
    '-subj', `/CN=${name}`);
  openssl('x509', '-req', '-in', `${name}.csr`, '-CA', 'ca.crt',
    '-CAkey', 'ca.key', '-CAcreateserial', '-out', `${name}.crt`,
    '-days', '1', '-extfile', extension);
}

await writeFile(join(root,'connection.json'),JSON.stringify(connection));
await writeFile(join(root,'token.txt'),'scoped-token');
let reply=profile; let active; const requests=[];
const server=createServer({key:await readFile(join(root,'server.key')),cert:await readFile(join(root,'server.crt')),ca:await readFile(join(root,'ca.crt')),requestCert:true,rejectUnauthorized:true},async(req,res)=>{for await(const c of req){};requests.push(req.url);res.end(JSON.stringify(req.url.endsWith("/connect") ? reply : active.kind === "run_ref" ? {kind:'found',requestId:'fixed-request',ref:active.value,durability:'durable',lookupExpiresAt:'2026-10-04T10:00:00Z'} : active.value));});
const builtExecutable = new URL(
  '../_build/native/release/build/cmd/native_client/native_client.exe',
  import.meta.url).pathname;
const executable = join(root, 'actql-native-client');
await copyFile(builtExecutable, executable);
await chmod(executable, 0o755);
const emptyPath = join(root, 'empty-path');
await mkdir(emptyPath);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const endpoint = `https://127.0.0.1:${server.address().port}/`;
const library = process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY ??
  (process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4');
const common = ['--endpoint', endpoint,
  '--connection-root', root, '--connection-file', 'connection.json',
  '--token-root', root, '--token-file', 'token.txt',
  '--http-library', library, '--ca', join(root, 'ca.crt'),
  '--cert', join(root, 'client.crt'), '--key', join(root, 'client.key')];

function runProcess(command, commandArgs) {
  return new Promise((resolve, reject) => {
    // The installed binary must not rely on a repository cwd or find Node,
    // MoonBit, curl's CLI, or another build tool through PATH.
    const child = spawn(command, commandArgs, {cwd: root,
      env: {...process.env, PATH: emptyPath}});
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8').on('data', data => { stdout += data; });
    child.stderr.setEncoding('utf8').on('data', data => { stderr += data; });
    child.once('error', reject);
    child.once('close', code => resolve({code, stdout, stderr}));
  });
}
const runWith = (commonArgs, ...args) =>
  runProcess(executable, [...commonArgs, ...args]);
const run = (...args) => runWith(common, ...args);

try {
 await writeFile(join(root,'program.json'),'{}');
 for(const entry of clientWireCorpus) await test(entry.name,async()=>{
  active=entry; requests.length=0;
  const selected=entry.kind==='connection'?entry.value:entry.selected;
  reply=entry.kind==='profile'?entry.value:{...profile,mode:selected?.mode,owner:selected?.owner};
  await writeFile(join(root,'connection.json'),JSON.stringify(selected));
  await writeFile(join(root,'ref.json'),JSON.stringify(entry.kind==='run_ref'?entry.value:ref));
  const js={profile:()=>validClientProfile(entry.value,selected),admission:()=>validClientAdmission(entry.value,selected),run_ref:()=>validRunRef(entry.value),connection:()=>validClientConnection(entry.value)}[entry.kind]();
  assert.equal(js,entry.expected,'JS matches independent expected outcome');
  const args=entry.operation==='attach'?['attach','--ref-file','ref.json']:entry.kind==='admission'?['start','--program-file','program.json','--request-id','fixed-request']:entry.kind==='run_ref'?['lookup-request','--request-id','fixed-request']:['connect'];
  const actual=await run(...args);
  assert.equal(actual.code===0,entry.expected,`Native matches independent expected outcome: ${actual.stderr}`);
  if(entry.kind==='profile'&&!entry.expected){
   requests.length=0;
   const subsequent=await run('start','--program-file','program.json','--request-id','blocked-request');
   assert.notEqual(subsequent.code,0);
   assert.deepEqual(requests,['/actql/client/0.1/connect'],'malformed profile stops before submit');
  }
  if(entry.kind==='connection'&&!entry.expected) assert.equal(requests.length,0,'invalid connection stops before network');
 });
}finally{server.close();}
