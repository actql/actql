// A real Host process over the existing installed fixture, with no SDK calls.
import {appendFileSync,readFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {getCACertificates,setDefaultCACertificates} from 'node:tls';
import {openInstalledRemoteHttpHost} from '../../adapters/host-node/embedded-local.mjs';
const installationPath=process.argv[2];
const installation=JSON.parse(readFileSync(installationPath,'utf8'));
const fault=process.argv[3]??'';
const cert=readFileSync(installation.hostTls.certificatePath);
setDefaultCACertificates([...getCACertificates('default'),cert.toString('utf8')]);
const host=await openInstalledRemoteHttpHost({directory:installation.directory,
  sourceProfilePath:installation.sourceProfilePath,resolveSourceSecret:async()=> 'test-only-secret',
  effectProfilePath:installation.effectProfilePath,resolveEffectSecret:async()=> 'test-only-secret',
  authenticate:header=>fault!=='revoked'&&header==='Bearer owner-token'?userInfo().username:undefined,
  authorization:{...installation.authorization,observe:(name,detail)=>{
    appendFileSync(`${installationPath}.python-owner-events.jsonl`,JSON.stringify({pid:process.pid,name,code:detail?.code})+'\n',{mode:0o600});
  },...(installation.epochNow===undefined?{}:{faultInjection:Object.assign(async()=>{},
    {submissionEpochTtlMs:1000,submissionEpochNow:()=>installation.epochNow})})}});
let lost=false;
const server=createServer({key:readFileSync(installation.hostTls.keyPath),cert},(request,response)=>{
  const operation=request.url.split('/').at(-1);
  appendFileSync(`${installationPath}.python-requests.jsonl`,JSON.stringify({pid:process.pid,operation})+'\n',{mode:0o600});
  if(!lost&&operation===fault){
    lost=true;
    response.end=()=>{response.destroy();return response;};
  }else if(fault==='read-prefix'&&operation==='read'){
    const write=response.write.bind(response);
    const prefix=value=>Buffer.from(value??'').filter(byte=>byte!==0x1e);
    response.write=(value,...args)=>write(prefix(value),...args);
    response.end=value=>{if(value!==undefined)write(prefix(value));setTimeout(()=>response.destroy(),50);return response;};
  }else if(fault==='status-extra-field'&&operation==='status'){
    const end=response.end.bind(response);
    response.end=value=>end(JSON.stringify({...JSON.parse(value.toString()),unexpected:true}));
  }
  return host.handler(request,response);
});
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
