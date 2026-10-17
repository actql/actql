import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const publicEntry=process.env.ACTQL_TEST_PROJECT_PUBLIC_NODE;
const runtime=process.env.ACTQL_TEST_PUBLIC_MODEL_TASK_RUNTIME;
assert.ok(publicEntry&&runtime,'Matching actual public Host assembly and Common runtime are required');
const fixture=new URL('../../scripts/fixtures/model-provider-binding-fixture.mjs',import.meta.url).href;
const declaration='task: model-task:project\ninput:\n  notes: string\noutput:\n  enabled: boolean\ninstructions: Original é\n';
const query="SELECT DISTINCT 'id' AS id |> EXTEND 'note' AS notes |> INFER `model-task:project` INPUT (notes = notes) AS result";

for(const scenario of ['checked','changed-registry','wrong-task','missing-provider']){
  test(`actual public Local Host preserves original Project Task ${scenario}`,async()=>{
    const scratch=await createOwnedScratch({parent:tmpdir(),prefix:'actql-project-host-',
      label:'Actual public Local Project Task installation'});
    await writeFile(join(scratch.path,'actql.config.json'),
      '{"version":"actql-config/0.1","model_tasks":"./tasks.json"}');
    await writeFile(join(scratch.path,'tasks.json'),JSON.stringify({version:'actql-model-tasks/0.1',
      tasks:{'model-task:project':'./task.yaml'},providers:{'models/project-fixture':{type:'fixture'}},
      default_provider:'models/project-fixture'}));
    await writeFile(join(scratch.path,'task.yaml'),scenario==='wrong-task'
      ?declaration.replace('model-task:project','model-task:foreign'):declaration);
    const script=`
      import assert from 'node:assert/strict';
      import {createHash} from 'node:crypto';
      import {readFile,writeFile,access} from 'node:fs/promises';
      import {providerBindingOriginals} from ${JSON.stringify(fixture)};
      const {connect}=await import(${JSON.stringify(pathToFileURL(publicEntry).href)});
      const expected=await import(${JSON.stringify(pathToFileURL(runtime).href)});
      const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}':JSON.stringify(value);
      const original=body=>{const wire=canonical(body);return {wire,cid:'sha256:'+createHash('sha256').update(wire).digest('hex')};};
      const binding=providerBindingOriginals('models/project-fixture');
      const handling=original({schema:'actql.contract/0.1',id:'project-fixture-policy',version:'fixture-r1',kind:'request_data_handling',body:{accepted_classifications:['public'],allowed_regions:['fixture'],retention:'none',training_use:'forbidden'}});
      binding.configurationContract=original({...JSON.parse(binding.configurationContract.wire),required:['endpoint','principal','selector','tenant','model_defaults']});
      binding.configuration=original({...JSON.parse(binding.configuration.wire),model_defaults:{default_model:'first',models:[{model:'first',data_handling:{...JSON.parse(handling.wire),cid:handling.cid},generation_config:{temperature:0,top_p:1,max_output_tokens:100}}]}});
      let registrations=0,sends=0;
      const installation={directory:'.state',registerModelProviders(actual){
        registrations++;assert.strictEqual(actual,expected);
        return ${JSON.stringify(scenario)}==='missing-provider'?[]:[{providerId:'models/project-fixture',bindingOriginals:binding,validatePrompt:()=>true,invoke(){sends++;assert.fail('No Model I/O during checking');}}];
      }};
      let client;
      try{
        if(${JSON.stringify(scenario)}==='wrong-task'){
          // The declared foreign Task is absent from this original registry;
          // Common's selection Owner refuses before a Host can be returned.
          await assert.rejects(connect({mode:'local',installation}),{code:'MoonBitHostFailure'});
        }else if(${JSON.stringify(scenario)}==='missing-provider'){
          await assert.rejects(connect({mode:'local',installation}),{code:'InstalledModelDefaultsUnavailable'});
        }else{
          client=await connect({mode:'local',installation});
          const outcome=await client.check(${JSON.stringify(query)},{kind:'text',scope:'bound_input',format:'sql'});
          assert.equal(outcome.outcome,'completed',JSON.stringify(outcome));
          assert.equal(outcome.report.verdict,'verified',JSON.stringify(outcome));
          if(${JSON.stringify(scenario)}==='changed-registry'){
            const registry=JSON.parse(await readFile('tasks.json','utf8'));
            await writeFile('tasks.json',JSON.stringify({...registry,tasks:{}}));
            await assert.rejects(connect({mode:'local',installation}),{message:'InstalledHostConfigurationMismatch'});
          }
        }
      }finally{await client?.close();}
      assert.equal(registrations,1);assert.equal(sends,0);
      await assert.rejects(access('.state/publication/owner/owner.json'),{code:'ENOENT'});
      console.log(JSON.stringify({scenario:${JSON.stringify(scenario)},registrations,sends,closed:true}));
    `;
    const child=spawnSync(process.execPath,['--input-type=module','-e',script],
      {cwd:scratch.path,encoding:'utf8',timeout:20000,maxBuffer:1024*1024});
    assert.ifError(child.error);
    assert.equal(child.status,0,child.stderr+'\n'+child.stdout);
    assert.deepEqual(JSON.parse(child.stdout.trim().split('\n').at(-1)),
      {scenario,registrations:1,sends:0,closed:true});
    scratch.passed();
  });
}
