import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {installModelProviders} from './installed-model.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

// Explicit Common doubles isolate Host snapshot/current/receiver behavior.
// They do not admit a real profile, Task, physical Provider or resource grant.
const limits=()=>({maxBytes:4096,maxNodes:256,maxDepth:16,maxMembers:8,maxWork:100000});
const hash=wire=>'sha256:'+createHash('sha256').update(wire).digest('hex');
const canonical=body=>JSON.stringify(Object.fromEntries(Object.entries(body).sort(([a],[b])=>a.localeCompare(b))));
const ok=value=>({$tag:1,_0:value});
function fixture({readFailure,readThrow}={}) {
  let open=true,current=true;
  const calls={read:[],resolve:[],sends:0,installed:0};
  const originals=providerBindingOriginals('models/original');
  const moon={
    clientProgramInstallModelProvider(){calls.installed++;return Object.freeze({});},
    clientProgramReadInstalledModelDefaults(provider,installation,contract,configuration,...bounds){
      assert.equal(this,moon);calls.read.push({provider,installation,contract,configuration,bounds});
      if(readThrow)throw readThrow;
      if(readFailure)return {$tag:0,_0:readFailure};
      const body={version:'actql-model-provider-binding/0.1',provider_id:provider,
        installation_revision_cid:hash(installation),configuration_contract_cid:hash(contract),
        configuration_cid:hash(configuration)};
      const identity=hash(canonical(body));
      return ok(Object.freeze({binding:Object.freeze({identity,wire:canonical({...body,self_cid:identity})})}));
    },
    clientProgramInstalledModelDefaultsBinding(value){assert.equal(this,moon);return value.binding;},
    clientProgramInstalledModelDefaultsUsage(){assert.equal(this,moon);return {_0:200,_1:12,_2:400};},
    clientProgramResolveInstalledModelDefaults(value,model,tokens,maxWork){
      assert.equal(this,moon);calls.resolve.push({value,model,tokens,maxWork});
      return ok(Object.freeze({value,model,tokens}));
    },
    strategyRunEvidenceJson:value=>value.wire,
    strategyRunEvidenceIdentity:value=>value.identity,
  };
  const entry={providerId:'models/original',bindingOriginals:originals,
    invoke(){calls.sends++;},validatePrompt:()=>true};
  const currentCheck=()=>{if(!current)throw Object.assign(new Error('CurrentOriginalLost'),{code:'CurrentOriginalLost'});};
  const newCheck=()=>{currentCheck();if(!open)throw Object.assign(new Error('HostClosing'),{code:'HostClosing'});};
  const providers=installModelProviders(moon,()=>[entry],currentCheck,newCheck);
  return {moon,entry,originals,providers,selected:providers.get(entry.providerId),calls,
    close:()=>{open=false;},loseCurrent:()=>{current=false;}};
}

test('installed defaults use one captured actual registration and read original only once',()=>{
  const f=fixture(),bounds=limits();
  assert.equal(f.calls.read.length,0);
  const first=f.selected.resolveTaskDefaults(undefined,undefined,bounds);
  const second=f.selected.resolveTaskDefaults('explicit-model',200n,{...bounds});
  assert.equal(first.value,second.value);
  assert.equal(first.binding.value,second.binding.value);
  assert.deepEqual(first.readUsage,{bytes:200,nodes:12,work:400});
  assert.ok(Object.isFrozen(first)&&Object.isFrozen(first.readUsage));
  assert.equal(f.calls.read.length,1);
  assert.equal(f.calls.resolve.length,2);
  assert.equal(f.calls.resolve[0].model,undefined);
  assert.equal(f.calls.resolve[1].model,'explicit-model');
  assert.equal(f.calls.resolve[1].tokens,200n);
  assert.deepEqual(f.calls.read[0].bounds,[4096,256,16,8,100000]);
  assert.equal(f.calls.sends,0);
});

test('installed defaults reject copied or other-installation receivers before Core work',()=>{
  const first=fixture(),second=fixture();
  for(const receiver of [{...first.selected},second.selected,undefined]){
    assert.throws(()=>Reflect.apply(first.selected.resolveTaskDefaults,receiver,
      [undefined,undefined,limits()]),{code:'InstalledModelDefaultsForeignOriginal'});
  }
  assert.equal(first.calls.read.length,0);assert.equal(second.calls.read.length,0);
  assert.equal(first.calls.sends+second.calls.sends,0);
});

test('installed defaults reject replacement map members and closing Host without cancelling existing work',()=>{
  const changed=fixture();changed.providers.set('models/original',{...changed.selected});
  assert.throws(()=>changed.selected.resolveTaskDefaults(undefined,undefined,limits()),
    {code:'InferTrustedRuntimeOriginalChanged'});
  const closing=fixture();closing.selected.resolveTaskDefaults(undefined,undefined,limits());
  closing.close();
  assert.throws(()=>closing.selected.resolveTaskDefaults(undefined,undefined,limits()),{code:'HostClosing'});
  assert.equal(changed.calls.read.length,0);assert.equal(closing.calls.read.length,1);
  assert.equal(closing.calls.resolve.length,1);assert.equal(closing.calls.sends,0);
});

test('installed defaults retain original strings and callback receivers rather than later replacements',()=>{
  const f=fixture();const wire=f.originals.configuration.wire;
  f.originals.configuration.wire='{"replacement":true}';
  f.moon.clientProgramReadInstalledModelDefaults=()=>assert.fail('replacement reader');
  f.moon.clientProgramResolveInstalledModelDefaults=()=>assert.fail('replacement resolver');
  f.selected.resolveTaskDefaults(undefined,undefined,limits());
  assert.equal(f.calls.read[0].configuration,wire);
  assert.equal(f.calls.sends,0);
});

test('installed defaults retain changed-current refusal after the same reader without another read',()=>{
  const f=fixture();
  // The captured actual reader may complete before currentness changes. Keep
  // its output under the same Host; do not switch installation or reparse.
  const usage=f.moon.strategyRunEvidenceJson;
  f.moon.strategyRunEvidenceJson=value=>{f.loseCurrent();return usage(value);};
  assert.throws(()=>f.selected.resolveTaskDefaults(undefined,undefined,limits()),{code:'CurrentOriginalLost'});
  assert.throws(()=>f.selected.resolveTaskDefaults(undefined,undefined,limits()),{code:'CurrentOriginalLost'});
  assert.equal(f.calls.read.length,1);assert.equal(f.calls.sends,0);
});

test('installed defaults snapshot finite reader bounds and reject later envelope substitution',()=>{
  const f=fixture(),source=limits();let reads=0;
  Object.defineProperty(source,'maxWork',{enumerable:true,get(){reads++;return 100000;}});
  f.selected.resolveTaskDefaults(undefined,undefined,source);
  assert.equal(reads,1);
  assert.throws(()=>f.selected.resolveTaskDefaults(undefined,undefined,{...limits(),maxBytes:1}),
    {code:'InstalledModelDefaultsLimitsChanged'});
  for(const invalid of [null,{}, {...limits(),maxNodes:-1},{...limits(),maxWork:Infinity},
    Object.assign(Object.create(limits()),{'maxBytes,maxDepth,maxMembers,maxNodes,maxWork':1})]){
    assert.throws(()=>f.selected.resolveTaskDefaults(undefined,undefined,invalid),/InvalidInstalledModelDefaultsLimits/u);
  }
  assert.equal(f.calls.read.length,1);assert.equal(f.calls.resolve.length,1);
});

test('installed defaults do not promote changed DATA CID hints into a bound selection',()=>{
  const f=fixture();
  const originals=providerBindingOriginals('models/changed');
  originals.configuration.cid='sha256:'+'f'.repeat(64);
  const entry={...f.entry,providerId:'models/changed',bindingOriginals:originals};
  const selected=installModelProviders(f.moon,()=>[entry],()=>{}).get(entry.providerId);
  assert.throws(()=>selected.resolveTaskDefaults(undefined,undefined,limits()),
    {code:'InstalledModelProviderBindingMismatch'});
  assert.equal(f.calls.resolve.length,0);assert.equal(f.calls.sends,0);
});

test('legacy registration without required original runtime support supplies no default',()=>{
  const calls=[];
  const moon={clientProgramInstallModelProvider(){calls.push('install');return {};}};
  const selected=installModelProviders(moon,()=>[{providerId:'legacy',invoke(){calls.push('send');},
    validatePrompt:()=>true}],()=>{}).get('legacy');
  assert.throws(()=>selected.resolveTaskDefaults(undefined,undefined,limits()),
    {code:'InstalledModelDefaultsUnavailable'});
  assert.deepEqual(calls,['install']);
});

test('a refused original defaults read retains its exact failure and original reader bounds',()=>{
  const f=fixture({readFailure:Object.freeze({original:'refused profile'})});
  let failure;
  assert.throws(()=>f.selected.resolveTaskDefaults(undefined,undefined,limits()),error=>{
    failure=error;return error.code==='MoonBitHostFailure';
  });
  assert.throws(()=>f.selected.resolveTaskDefaults(undefined,undefined,limits()),error=>error===failure);
  assert.throws(()=>f.selected.resolveTaskDefaults(undefined,undefined,{...limits(),maxWork:200000}),
    {code:'InstalledModelDefaultsLimitsChanged'});
  assert.equal(f.calls.read.length,1);
  assert.equal(f.calls.resolve.length,0);assert.equal(f.calls.sends,0);
});

test('a thrown original defaults reader keeps the original throwable and never reads twice',()=>{
  const original=new TypeError('OriginalReaderFailure');
  const f=fixture({readThrow:original});
  for(let attempt=0;attempt<2;attempt++){
    assert.throws(()=>f.selected.resolveTaskDefaults(undefined,undefined,limits()),error=>error===original);
  }
  assert.equal(f.calls.read.length,1);assert.equal(f.calls.sends,0);
});
