import assert from 'node:assert/strict';
import test from 'node:test';
import {createHttpChatProvider} from './_internal/normal-http-chat.mjs';
import type {HttpChatProviderOptions} from '@actql/local-node';

type Configure = ReturnType<typeof createHttpChatProvider>;
type Runtime = Parameters<Configure>[0];
type Context = Parameters<Configure>[1];
const cid = 'sha256:' + 'a'.repeat(64);
const body = Object.freeze({wire:'{}',cid});
const key = 'ACTQL_TEST_DIRECT_HTTP_KEY';

function fixture() {
  const seen: string[] = [];
  const task = {name:'task',providerId:'model/fixture',taskCid:cid,modelSelector:'selector',
    promptCid:cid,outputSchemaCid:cid,promptPayloadWire:'{}'};
  const originals = Object.freeze({configuration:body,configurationContract:body,installationRevision:body});
  const profile = Object.freeze({oneOriginalProfile:true});
  const options: HttpChatProviderOptions = {
    providerId:task.providerId,modelSelector:task.modelSelector,modelId:'actual-model',
    endpoint:'https://fixture.invalid/v1/chat/completions',credentialEnvironment:key,
    dataHandlingContractWire:'{}',rawPolicies:{retention:body,metadata:body,clock:body,data:body},
    generation:{temperature:0,topP:1,maxOutputTokens:32},
    budget:{maxCalls:1n,maxRows:1,maxTokens:64n,maxCostUnits:100n,maxDurationMs:3000n},
    transportTimeouts:{connectMs:1000,headersMs:1000,bodyMs:1000,callMs:2000},
    observeEgress() {assert.fail('Startup does not observe egress');},
  };
  const runtime = Object.fromEntries(['clientProgramProjectHTTPChatRequest','clientProgramInstallAsyncModelProvider',
    'clientProgramModelRequestPreflight','clientProgramModelAsyncPhysicalRequestPlan',
    'clientProgramModelPhysicalCallForRequest','clientProgramModelPhysicalPending',
    'clientProgramModelPhysicalUnknown','clientProgramModelPhysicalSavedChat'].map(name =>
    [name, () => { assert.fail('Startup may not begin a physical operation'); }]));
  Object.assign(runtime, {
    clientProgramInstalledNodeModelDeadlineCapacity: () => [100n,200n],
    clientProgramStandardInferModelTransferBytes(attempts:bigint) { assert.equal(attempts,1n);return 131072n; },
    clientProgramModelResponseProfileTransportMatches(original:unknown,...limits:unknown[]) {
      assert.equal(original,profile);
      assert.deepEqual(limits,[32768,65536,8192,128,8192]);
      return true;
    },
  });
  const context:Context = {
    async prepareConfiguration(project) {return project();},
    registeredSdkSelected(id) {assert.equal(id,task.providerId);return false;},
    async runtimeIdentity() {return cid;},
    async artifactIdentity(locator) {
      assert.match(locator,/\/(normal-http-chat|original-chat-request)\.mjs$/u);
      return cid;
    },
    async prepareBindingOriginals(project) {
      const [revision,contract,configuration] = project().map(wire => JSON.parse(wire));
      assert(!Object.hasOwn(revision,'lock_artifact_cid'));
      assert.equal(configuration.adapter_kind,'portable-http');
      assert.equal(configuration.api_mode,'chat-completions');
      assert.equal(configuration.credential_reference,key);
      assert.equal(configuration.endpoint,options.endpoint);
      assert.equal(contract.physical_profile.active_slots,1);
      seen.push('binding');
      return originals;
    },
    async prepareRawPolicies(selected) {
      assert.deepEqual(selected,options.rawPolicies);
      return selected;
    },
    async prepareTasks(bindings) {
      assert.deepEqual(bindings,[{providerId:task.providerId,bindingOriginals:originals}]);
      return {
        tasks:[task],
        async verifyChatConfiguration(...original) {
          assert.deepEqual(original,[task.name,task.modelSelector,options.modelId,options.endpoint,'portable-http']);
          seen.push('verify');
        },
        async responseProfileFor(name, template) {
          const authored = JSON.parse(template());
          assert.equal(name,task.name);
          assert.equal(authored.adapter.sdk,null);
          assert.equal(authored.operation.endpoint,options.endpoint);
          seen.push('profile');return {profile};
        },
        async executionOriginalsFor(name, bounds) {
          assert.equal(name,task.name);
          assert.equal(bounds.maxAttempts,1n);
          assert.equal(bounds.maxWireBytes,131072n);
          seen.push('execution');
        },
        bindingOriginalsFor(id) {assert.equal(id,task.providerId);return originals;},
        async providerEntries(project) {seen.push('entries');return project();},
      };
    },
  };
  return {ctx:context,moon:runtime as Runtime,options,task,profile,seen};
}

test('configured direct Chat sends its original route, profile and Graph recipe to the existing Host without reading a key', async () => {
  const f=fixture(), original=process.env;
  let keyReads=0;
  process.env=new Proxy(original,{get(target,name) {
    if(name===key){keyReads++;assert.fail('Startup must leave the credential unread');}
    return Reflect.get(target,name);
  }});
  try {
    const configured=createHttpChatProvider(f.options);
    const [entry] = await configured(f.moon,f.ctx);
    assert(entry);
    assert.deepEqual(f.seen,['binding','verify','profile','execution','entries']);
    const declaration = entry.taskInstallations[0]!.entry;
    assert.equal(declaration.entryPersistence,'async');
    assert.equal(declaration.sdkStaticOriginals,undefined);
    assert.equal(declaration.originalReadInstallation,undefined);
    const recipe=declaration.originalReadRecipe as {nodeInstallation:{layout:{response_profile:unknown},
      installation:{sdk:unknown}}};
    assert.equal(recipe.nodeInstallation.installation.sdk,undefined);
    const raw = declaration.rawCaptureSelection as {installation:unknown; profile:unknown};
    assert.equal(raw.installation,recipe.nodeInstallation.installation);
    assert.equal(raw.profile,f.profile);
    assert.equal(recipe.nodeInstallation.layout.response_profile,f.profile);
    assert.equal(Object.hasOwn(recipe.nodeInstallation.layout,'program_definition_cid'),false);
    assert.equal(keyReads,0);
    await assert.rejects(configured(f.moon,f.ctx),{code:'InstalledHttpChatProviderConfigurationReused'});
  } finally { process.env=original; }
});

test('direct configuration refuses untrusted endpoint and an explicitly competing SDK selection before admission', async () => {
  const f=fixture();
  await assert.rejects(createHttpChatProvider({...f.options,endpoint:'http://fixture.invalid'})(f.moon,f.ctx),
    {code:'InvalidInstalledHttpChatProviderConfiguration'});
  await assert.rejects(createHttpChatProvider(f.options)(f.moon,{...f.ctx,registeredSdkSelected:()=>true}),
    {code:'InvalidInstalledHttpChatProviderConfiguration'});
  assert.deepEqual(f.seen,[]);
});
