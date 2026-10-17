import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const entry=process.env.ACTQL_TEST_PROJECT_PUBLIC_NODE;
assert.ok(entry,'An ordinary matching actual public Local Host preparation is required');
for(const scenario of ['explicit-mock','default-mock','early-root-refusal']){
  test(`actual public profile selection keeps original Host refusal ${scenario}`,async()=>{
    const scratch=await createOwnedScratch({parent:tmpdir(),prefix:'actql-project-profile-host-',
      label:'Original public profile refusal'});
    await writeFile(join(scratch.path,'actql.config.json'),JSON.stringify({version:'actql-config/0.1',
      ...(scenario==='default-mock'?{profile:'mock'}:{})}));
    if(scenario==='early-root-refusal')await writeFile(join(scratch.path,'.state'),'original file');
    const script=`
      import assert from 'node:assert/strict';
      import {access,readFile} from 'node:fs/promises';
      const {connect}=await import(${JSON.stringify(pathToFileURL(entry).href)});
      let registrations=0,client,failure;
      const scenario=${JSON.stringify(scenario)};
      const installation={directory:'.state',
        ...(scenario==='early-root-refusal'?{}:{sourceProfilePath:'never-source.json',effectProfilePath:'never-effect.json'}),
        registerModelProviders(){registrations++;assert.fail('No Provider registration before profile/root admission');}};
      try{client=await connect({mode:'local',installation,...(scenario==='explicit-mock'?{profile:'mock'}:{})});}
      catch(error){failure=error;}
      finally{await client?.close();}
      assert.ok(failure,'A missing physical profile/root must not become an admitted Client');
      assert.equal(failure.code,scenario==='early-root-refusal'?'UnknownHostRootFormat':'InstalledProjectProfileUnavailable');
      assert.notEqual(failure.name,'ReferenceError');
      assert.notEqual(failure.cleanupPending,true,'Managed profile retirement must not hide the original root refusal');
      assert.equal(registrations,0);
      if(scenario==='early-root-refusal')assert.equal(await readFile('.state','utf8'),'original file');
      else await assert.rejects(access('.state'),{code:'ENOENT'});
      console.log(JSON.stringify({scenario,registrations,code:failure.code}));
    `;
    const child=spawnSync(process.execPath,['--input-type=module','-e',script],
      {cwd:scratch.path,encoding:'utf8',timeout:20000,maxBuffer:1024*1024});
    assert.ifError(child.error);assert.equal(child.status,0,child.stderr+'\n'+child.stdout);
    assert.equal(JSON.parse(child.stdout.trim().split('\n').at(-1)).registrations,0);
    scratch.passed();
  });
}
