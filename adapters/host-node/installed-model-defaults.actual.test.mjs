import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {installModelProviders} from './installed-model.mjs';
import {runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

const path=process.env.ACTQL_TEST_MODEL_DEFAULTS_COMMON_RUNTIME;
assert.ok(path,'A matching ordinary Common runtime is required; do not skip this boundary');
const moon=await import(pathToFileURL(path));
const limits=()=>({maxBytes:4096,maxNodes:256,maxDepth:16,maxMembers:8,maxWork:100000});
const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':
  value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(key=>
    JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}':JSON.stringify(value);
const original=body=>{const wire=canonical(body);return{wire,
  cid:'sha256:'+createHash('sha256').update(wire).digest('hex')};};
function fixture({defaults=true}={}) {
  let calls=0,open=true,current=true,callbacks=0;
  const originals=providerBindingOriginals('models/actual-defaults',{selector:'m'});
  if(defaults){
    originals.configurationContract=original({...JSON.parse(originals.configurationContract.wire),
      required:['endpoint','principal','selector','tenant','model_defaults']});
    originals.configuration=original({...JSON.parse(originals.configuration.wire),model_defaults:{
      default_model:'m',models:[{model:'m',generation_config:{temperature:0.25,
        top_p:0.875,max_output_tokens:100}}]}});
  }
  const check=()=>{if(!current)throw Object.assign(new Error('OriginalLost'),{code:'OriginalLost'});};
  const checkNew=()=>{check();if(!open)throw Object.assign(new Error('HostClosing'),{code:'HostClosing'});};
  const providers=installModelProviders(moon,runtime=>{
    callbacks++;assert.equal(runtime,moon);
    return[{providerId:'models/actual-defaults',invoke(){calls++;assert.fail('No Provider call');},
      validatePrompt:()=>true,bindingOriginals:originals}];
  },check,checkNew);
  return{providers,selected:providers.get('models/actual-defaults'),originals,
    close:()=>{open=false;},loseCurrent:()=>{current=false;},
    counts:()=>({calls,callbacks})};
}

// Actual Common original admission and the real private Host registration
// function; the registered synchronous no-I/O Provider is an explicit fixture.
test('actual Common defaults use the original registration/configuration callback and binding',()=>{
  const f=fixture(),wire=f.originals.configuration.wire;
  const first=f.selected.resolveTaskDefaults(undefined,200n,limits());
  f.originals.configuration=original({replacement:true});
  const second=f.selected.resolveTaskDefaults('m',undefined,limits());
  assert.equal(first.value,second.value);
  assert.equal(first.binding.value,second.binding.value);
  assert.equal(first.binding.originals.configuration.wire,wire);
  assert.equal(JSON.parse(first.binding.wire).configuration_cid,
    'sha256:'+createHash('sha256').update(wire).digest('hex'));
  assert.ok(runtimeUnboxedReferenceOption(
    moon.clientProgramInstalledModelDefaultsGeneration(first.value,first.resolved)));
  assert.equal(first.readUsage.bytes,Buffer.byteLength(wire));
  assert.ok(first.readUsage.nodes>0&&first.readUsage.work>0);
  assert.deepEqual(f.counts(),{calls:0,callbacks:1});
});

test('actual Common rejects a foreign equal-wire profile pair and copied installation receiver',()=>{
  const first=fixture(),second=fixture();
  const a=first.selected.resolveTaskDefaults(undefined,undefined,limits());
  const b=second.selected.resolveTaskDefaults(undefined,undefined,limits());
  assert.notEqual(a.value,b.value);
  assert.equal(runtimeUnboxedReferenceOption(
    moon.clientProgramInstalledModelDefaultsGeneration(b.value,a.resolved)),undefined);
  assert.throws(()=>Reflect.apply(first.selected.resolveTaskDefaults,second.selected,
    [undefined,undefined,limits()]),{code:'InstalledModelDefaultsForeignOriginal'});
  assert.throws(()=>Reflect.apply(first.selected.resolveTaskDefaults,{...first.selected},
    [undefined,undefined,limits()]),{code:'InstalledModelDefaultsForeignOriginal'});
  assert.equal(first.counts().calls+second.counts().calls,0);
});

test('actual Host original currentness refuses stale or closing default resolution without invoking',()=>{
  const closing=fixture();closing.selected.resolveTaskDefaults(undefined,undefined,limits());
  closing.close();
  assert.throws(()=>closing.selected.resolveTaskDefaults(undefined,undefined,limits()),{code:'HostClosing'});
  const stale=fixture();stale.loseCurrent();
  assert.throws(()=>stale.selected.resolveTaskDefaults(undefined,undefined,limits()),{code:'OriginalLost'});
  const changed=fixture();changed.providers.set('models/actual-defaults',{...changed.selected});
  assert.throws(()=>changed.selected.resolveTaskDefaults(undefined,undefined,limits()),
    {code:'InferTrustedRuntimeOriginalChanged'});
  assert.equal(closing.counts().calls+stale.counts().calls+changed.counts().calls,0);
});

test('actual Common no-default unknown-model and invalid-token refusals create no invocation',()=>{
  const absent=fixture({defaults:false});
  assert.throws(()=>absent.selected.resolveTaskDefaults(undefined,undefined,limits()),{code:'MoonBitHostFailure'});
  const f=fixture();
  assert.throws(()=>f.selected.resolveTaskDefaults('foreign',undefined,limits()),{code:'MoonBitHostFailure'});
  assert.throws(()=>f.selected.resolveTaskDefaults(undefined,0n,limits()),{code:'MoonBitHostFailure'});
  assert.equal(absent.counts().calls+f.counts().calls,0);
});
