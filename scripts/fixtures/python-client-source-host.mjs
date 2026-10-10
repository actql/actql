// A real Host process over the existing installed fixture, with no SDK calls.
import {appendFileSync,readFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {getCACertificates,setDefaultCACertificates} from 'node:tls';
import {openInstalledRemoteHttpHost} from '../../adapters/host-node/embedded-local.mjs';
const installationPath=process.argv[2];
const installation=JSON.parse(readFileSync(installationPath,'utf8'));
const cert=readFileSync(installation.hostTls.certificatePath);
setDefaultCACertificates([...getCACertificates('default'),cert.toString('utf8')]);
const host=await openInstalledRemoteHttpHost({directory:installation.directory,
  sourceProfilePath:installation.sourceProfilePath,resolveSourceSecret:async()=> 'test-only-secret',
  effectProfilePath:installation.effectProfilePath,resolveEffectSecret:async()=> 'test-only-secret',
  authenticate:header=>header==='Bearer owner-token'?userInfo().username:undefined,
  authorization:{...installation.authorization,observe:(name,detail)=>{
    appendFileSync(`${installationPath}.python-owner-events.jsonl`,JSON.stringify({pid:process.pid,name,code:detail?.code})+'\n',{mode:0o600});
  }}});
const server=createServer({key:readFileSync(installation.hostTls.keyPath),cert},host.handler);
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
process.send({endpoint:`https://127.0.0.1:${server.address().port}/`,pid:process.pid});
let closing=false;
process.on('message',async message=>{
  if(message!=='close'||closing)return;
  closing=true;
  try{
    server.closeAllConnections();
    await new Promise(resolve=>server.close(resolve));
    await host.close();
    process.disconnect();
  }catch{
    console.error('PythonFixtureHostCleanupFailed');
    process.exitCode=1;
    process.disconnect();
  }
});
