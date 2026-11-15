import {composeInstalledEffects} from './installed-effect-inventory.mjs';
import {loadInstalledSources} from './installed-source.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {parse} from 'acorn';
import {createInstalledHostServices, retireInstalledSourceInitialization, withInstalledSourceLoading}
  from './installed-host-services.mjs';
import {composeInstalledSourceEnvironment, composeInstalledInventoryEnvironment, releaseRetiredInstalledEnvironmentComposition,
  admitInstalledSourceFinalEnvironment, assertInstalledEnvironmentPublicationOriginal} from './installed-funded-environment.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {selectInstalledHostEnvironment, selectInstalledLocalMaterializationEnvironment} from './installed-host-policy.mjs';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {createInstalledLoaderParent} from './fixtures/installed-loader-parent.fixture.mjs';

assert.ok(process.env.ACTQL_TEST_ENVIRONMENT_RUNTIME, 'Select the matching generated Environment bridge');
const native = await import(pathToFileURL(process.env.ACTQL_TEST_ENVIRONMENT_RUNTIME));
const baseWire = readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8').trimEnd();
const ok = value => ({$tag: 1, _0: value});
function document(name, selectedBase = baseWire) {
  const body = JSON.parse(selectedBase);withFixtureConnector(body, `connector://${name}/records`);
  delete body.evidence_bundle_cid;
  return canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
}

// Actual generated wire/Environment constructors and quantities, real nominal
// Host services. Resource reservation replies are explicit component fixtures:
// these tests establish ordering/identity, not actual Root/Ledger admission.
function fixture() {
  const input = {}, unit = {}, capacity = {}, initial = {}, events = [];
  const state = {reads: 0, from: 0, retire: 0, refuse: false, cause: undefined, current: true, retireReady: true, reconciled: [], zero: new Set(), rawSlots: new Set(), rawSlotCompositions: [], checkerQuotes: [], reserved: [], delay: undefined};
  const moon = {...native};
  for (const name of ['ReconcileInstalledSourceConstruction', 'CompleteInstalledSourceMaterial',
    'BorrowInstalledSourceMaterial', 'BorrowedInstalledSourceEnvironment', 'ReturnInstalledSourceMaterial',
    'AbortUncontinuedSourceMaterial', 'BeginInstalledSourceIo', 'ChargeInstalledSourceIo',
    'MarkInstalledSourceIoTransferUncertain', 'FinishInstalledSourceIoAfterCleanup']) moon['clientProgram' + name] = () => ok();
  Object.assign(moon, {
    clientProgramInstalledSourceConstructionCapacity(...values) {
      const result = native.clientProgramInstalledSourceConstructionCapacity(...values);
      if (values.every(value => value === 0n)) state.zero.add(result._0);
      if (values[0] === 1n && values.slice(1).every(value => value === 0n)) state.rawSlots.add(result._0);
      return result;
    },
    clientProgramReconcileInstalledSourceConstruction(value, original, quote) {
      assert.equal(value, capacity); assert.equal(original, input);
      state.reconciled.push([...quote.providers]); return ok();
    },
    clientProgramTakeHostInitializationSourceCapacity(value) {assert.equal(value, initial);return ok({_0: input, _1: unit});},
    clientProgramContinueInstalledSourceMaterial(value, original) {assert.equal(value, unit);assert.equal(original, input);return ok(capacity);},
    clientProgramComposeInstalledSourceConstructionCapacity: (original, providers) => {
      if (!state.rawSlots.has(original)) return ok({original, providers});
      const result = native.clientProgramComposeInstalledSourceConstructionCapacity(original, providers);
      state.rawSlotCompositions.push({original, providers, result: result._0});
      events.push('raw-slot-quote');
      return result;
    },
    clientProgramCheckEnvironmentFromWireConstructionCapacity(value) {
      const result = native.clientProgramCheckEnvironmentFromWireConstructionCapacity(value);
      state.checkerQuotes.push(result);return result;
    },
    clientProgramReserveInstalledSourceConstruction(value, original, quote) {
      state.reserved.push([...quote.providers]);
      assert.equal(value, capacity);assert.equal(original, input);events.push('reserve');
      if (state.refuse) throw state.cause;return ok();
    },
    clientProgramRetireInstalledSourceMaterial(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);state.retire++;return ok(state.retireReady);
    },
    clientProgramReadCheckEnvironmentWire(wire, cid) {
      assert.equal(events.at(-1), 'reserve');state.reads++;events.push('read');
      const value = native.clientProgramReadCheckEnvironmentWire(wire, cid);
      return state.delay?.(value) ?? value;
    },
    clientProgramCheckEnvironmentFromWire(value, ...flags) {
      assert.equal(events.at(-1), 'reserve');state.from++;events.push('from');
      return native.clientProgramCheckEnvironmentFromWire(value, ...flags);
    },
  });
  const services = createInstalledHostServices({root: '/component/environment', principalId: 'component', moon,
    initialPreparation: initial, assertCurrent() {state.onCurrent?.();if (!state.current) throw new Error('OriginalLost');}});
  return {moon, services, state, events, compose: (...inputs) => composeInstalledSourceEnvironment(services, moon, ...inputs),
    inventory: (previous, member, accept = () => false) => composeInstalledInventoryEnvironment(services, moon, baseWire, previous, member, accept),
    close: () => retireInstalledSourceInitialization(services)};
}

const finalProfiles = Object.freeze({textTime:false,
  numericProfileCid:'sha256:'+'a'.repeat(64),graphLawCid:'sha256:'+'b'.repeat(64)});

// These scalar selectors are explicit fixtures, not Resource funding. The
// actual Environment parser, checker, Source constructor quantities and
// original association below use the retained real component namespace.
function localPolicyRuntime() {
  const original=Object.freeze({});
  return {...native,
    clientLocalResourcePolicyOriginal:()=>original,
    clientLocalResourcePolicyRowCeiling(value){assert.strictEqual(value,original);return 1000;},
    clientLocalResourcePolicyModelRequestByteCeiling(value){assert.strictEqual(value,original);return 1000n;}};
}

test('Local graph defaults enter the first funded Source wire without a later policy change', () => {
  const runtime=localPolicyRuntime();
  const selected=selectInstalledLocalMaterializationEnvironment(runtime,baseWire,undefined,undefined,undefined,true);
  const expected={...JSON.parse(baseWire).host_policy_profile.capacity,
    max_file_listing_items:1000,max_graph_construction_edges:1000,
    max_graph_construction_input_rows:1000,max_graph_construction_nodes:1000};
  assert.deepEqual(JSON.parse(selected).host_policy_profile.capacity,expected);
  const f=fixture(), source=document('graph-defaults',selected);
  const composed=composeInstalledSourceEnvironment(f.services,f.moon,selected,source);
  assert.equal(composed.wire,source);
  assert.deepEqual(composed.body.host_policy_profile.capacity,expected);
  assert.equal(composed.evidenceCid,contentCid(composed.body));
  assert.ok(['max_graph_construction_edges','max_graph_construction_input_rows','max_graph_construction_nodes']
    .every(key=>Object.hasOwn(composed.body.host_policy_profile.capacity,key)));
  const prepared=native.clientProgramPreparePublicSourceEnvironment(composed.admitted,
    JSON.stringify({environmentCid:composed.evidenceCid,aliases:[]}));
  assert.ok(prepared);
  assert.doesNotThrow(()=>assertInstalledEnvironmentPublicationOriginal(f.services,f.moon,composed,prepared,source));
  assert.equal(f.close(),true);
});

test('Local graph defaults preserve explicit values and leave generic published policy selection unchanged', () => {
  const runtime=localPolicyRuntime(),original=JSON.parse(baseWire).host_policy_profile.capacity;
  const explicit={...original,max_graph_construction_edges:17,max_graph_construction_nodes:23};
  const selected=selectInstalledLocalMaterializationEnvironment(runtime,baseWire,explicit,undefined,undefined,true);
  assert.deepEqual(JSON.parse(selected).host_policy_profile.capacity,
    {...explicit,max_graph_construction_input_rows:1000});
  const independent=selectInstalledLocalMaterializationEnvironment(runtime,baseWire,explicit);
  assert.deepEqual(JSON.parse(independent).host_policy_profile.capacity,explicit);
  assert.equal(selectInstalledHostEnvironment(runtime,baseWire),baseWire);
  const generic=selectInstalledHostEnvironment(runtime,baseWire,explicit);
  assert.deepEqual(JSON.parse(generic).host_policy_profile.capacity,explicit);
  assert.equal(Object.hasOwn(JSON.parse(generic).host_policy_profile.capacity,'max_graph_construction_input_rows'),false);
});

test('Table129 source-profile option uses the actual early-policy Host entrance', () => {
  const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  const host=tree.body.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='openInstalledHost');
  assert.ok(host);
  const declarations=[];
  const visit=node=>{
    if(node===null||typeof node!=='object')return;
    if(node.type==='VariableDeclarator'&&['selectBaseEnvironment','baseEnvironmentWire'].includes(node.id.name))declarations.push(node);
    for(const value of Object.values(node)){
      if(Array.isArray(value))value.forEach(visit);
      else if(value!==null&&typeof value==='object')visit(value);
    }
  };
  visit(host.body);assert.equal(declarations.length,2);
  const runtime=localPolicyRuntime();
  const select=(overrides={})=>{
    const calls=[];
    const values={mode:'local',effectInstallation:undefined,selectedSourcePaths:['source129.json'],selectedEffectPaths:[],
      originalInstallation:{sourceProfilePath:'source129.json'},moon:runtime,environmentSource:baseWire,
      hostCapacityPolicy:undefined,selectedLookupPolicy:undefined,requestMemory:undefined,
      calendarArtifact:undefined,modelInstallation:undefined,mockModels:undefined,project:undefined,
      installedProjectOriginalsForRuntime(project,moon){assert.strictEqual(moon,runtime);return project;},
      selectInstalledHostEnvironment,
      selectInstalledLocalMaterializationEnvironment(...args){calls.push(args[5]);return selectInstalledLocalMaterializationEnvironment(...args);},
      ...overrides};
    const body=declarations.map(node=>'const '+source.slice(node.start,node.end)+';').join('\n');
    const wire=new Function(...Object.keys(values),body+'\nreturn baseEnvironmentWire;')(...Object.values(values));
    return {wire,calls};
  };
  const selected=select();assert.deepEqual(selected.calls,[]);
  assert.equal(selected.wire,baseWire,'A loaded Source keeps its independently published generic policy');
  const f=fixture(),original=document('table-profile-path',selected.wire);
  const composed=composeInstalledSourceEnvironment(f.services,f.moon,selected.wire,original);
  assert.equal(composed.wire,original);
  assert.deepEqual(composed.body.host_policy_profile,JSON.parse(baseWire).host_policy_profile);
  assert.equal(f.close(),true);
  const ordinary=select({selectedSourcePaths:[],originalInstallation:{}});
  assert.deepEqual(ordinary.calls,[true]);
  assert.ok(['max_graph_construction_edges','max_graph_construction_input_rows','max_graph_construction_nodes']
    .every(key=>Object.hasOwn(JSON.parse(ordinary.wire).host_policy_profile.capacity,key)));
  for(const override of [{modelInstallation:{}},{mockModels:{}},{calendarArtifact:{}},{project:{modelRegistry:{}}}]){
    const independent=select({selectedSourcePaths:[],originalInstallation:{},...override});assert.deepEqual(independent.calls,[false]);
    assert.equal(Object.hasOwn(JSON.parse(independent.wire).host_policy_profile.capacity,'max_graph_construction_nodes'),false);
  }
  const declared=select({originalInstallation:{sourceProfilePath:'source129.json',declaredFileBaseEnvironmentWire:baseWire}});
  assert.equal(declared.wire,baseWire);assert.deepEqual(declared.calls,[]);
});

test('initial Environment admission retains its raw reference without promoting completed checker scratch', () => {
  const f=fixture();
  f.compose(baseWire);
  assert.equal(f.state.from,1);
  assert.equal(f.state.rawSlots.size,1);
  const slot=[...f.state.rawSlots][0];
  const fromIndex=f.events.indexOf('from');
  assert.ok(fromIndex>0);
  assert.equal(f.events[fromIndex-1],'reserve');
  assert.ok(f.state.reserved.some(providers=>providers.includes(slot)));
  assert.equal(f.state.rawSlotCompositions.length,0);
  assert.equal(f.state.checkerQuotes.length,1);
  const original=native.clientProgramSerializationCapacityBytes(f.state.checkerQuotes[0]);
  assert.ok(original._1>original._0);
  // Once the synchronous checker returns, only its real retained output and
  // the independently funded raw alias coexist. Its workspace is reusable.
  const last=f.state.reconciled.at(-1).map(value=>native.clientProgramSerializationCapacityBytes(value));
  assert.ok(last.some(value=>value._0===original._0&&value._1===original._0));
  assert.ok(last.every(value=>value._0!==original._1||value._1!==original._1));
  assert.equal(f.close(),true);
});
// Spy for this NEW bridge's caller forwarding only. The old retained namespace
// still lacks the graph/numeric port; shared Core tests separately exercise
// that real selection. This is not an actual new-ABI or normal qualification.
function installFinalForwarder(f, calls) {
  const capacity=f.moon.clientProgramInstalledSourceConstructionCapacity;
  const compose=f.moon.clientProgramComposeInstalledSourceConstructionCapacity;
  let finalControls;
  f.moon.clientProgramInstalledSourceConstructionCapacity=(...values)=>{
    const result=capacity(...values);
    if (values[0]===8n && values.slice(1).every(value=>value===0n)) finalControls=result._0;
    return result;
  };
  // Keep the fixture's outer reservation observer envelope, while the new
  // final native input itself gets an ACTUAL typed constructor quantity.
  f.moon.clientProgramComposeInstalledSourceConstructionCapacity=(original,providers)=>
    original===finalControls ? native.clientProgramComposeInstalledSourceConstructionCapacity(original,providers)
      : compose(original,providers);
  f.moon.clientProgramCheckEnvironmentFromWireWithGraphProfile = (raw,...flags) => {
    assert.equal(f.events.at(-1),'reserve');
    calls.push({raw,flags});
    return native.clientProgramCheckEnvironmentFromWire(raw,...flags.slice(0,7));
  };
}

test('final Source checker caller funds a new wrapper on the same actual wire and retains nominal publication', () => {
  const f=fixture(), value=f.compose(baseWire), calls=[];
  installFinalForwarder(f,calls);
  const reads=f.state.reads;
  const final=admitInstalledSourceFinalEnvironment(f.services,f.moon,value,finalProfiles);
  assert.equal(f.state.reads,reads,'no second original wire parser');
  assert.equal(final.wire,value.wire);assert.equal(final.body,value.body);
  assert.equal(calls.length,1);
  assert.deepEqual(calls[0].flags,[false,true,true,true,true,false,false,
    finalProfiles.numericProfileCid,finalProfiles.graphLawCid]);
  const prepared=native.clientProgramPreparePublicSourceEnvironment(final.admitted,
    JSON.stringify({environmentCid:final.evidenceCid,aliases:[]}));
  assert.ok(prepared);
  assert.doesNotThrow(()=>assertInstalledEnvironmentPublicationOriginal(f.services,f.moon,final,prepared,final.wire));
  assert.throws(()=>assertInstalledEnvironmentPublicationOriginal(f.services,f.moon,value,prepared,final.wire),
    {code:'ForeignInstalledEnvironmentOriginal'});
  assert.equal(f.close(),true);
});

test('final Source checker caller refuses copied foreign or current-lost originals before new construction', () => {
  const a=fixture(),b=fixture(), value=a.compose(baseWire), calls=[];
  installFinalForwarder(a,calls);installFinalForwarder(b,calls);
  assert.throws(()=>admitInstalledSourceFinalEnvironment(a.services,a.moon,{...value},finalProfiles),
    {code:'ForeignInstalledEnvironmentOriginal'});
  assert.throws(()=>admitInstalledSourceFinalEnvironment(b.services,b.moon,value,finalProfiles),
    {code:'ForeignInstalledEnvironmentOriginal'});
  a.state.current=false;
  assert.throws(()=>admitInstalledSourceFinalEnvironment(a.services,a.moon,value,finalProfiles),
    {message:'OriginalLost'});
  assert.equal(calls.length,0);a.state.current=true;a.close();b.close();
});

test('final Source checker caller preserves reservation refusal and refuses absent new runtime port', () => {
  const f=fixture(),value=f.compose(baseWire),calls=[];
  for(const port of ['clientProgramCheckEnvironmentFromWireConstructionCapacity',
    'clientProgramCheckEnvironmentFromWireWithGraphProfile']){
    const actual=f.moon[port];assert.equal(typeof actual,'function');
    delete f.moon[port];
    assert.throws(()=>admitInstalledSourceFinalEnvironment(f.services,f.moon,value,finalProfiles),
      {code:'InstalledFinalEnvironmentRuntimeUnavailable'});
    f.moon[port]=actual;
  }
  installFinalForwarder(f,calls);
  const cause=new Error('OriginalQuotaRefusal');f.state.refuse=true;f.state.cause=cause;
  assert.throws(()=>admitInstalledSourceFinalEnvironment(f.services,f.moon,value,finalProfiles),error=>error===cause);
  assert.equal(calls.length,0);f.state.refuse=false;f.close();
});

test('generated Environment constructors are prefunded once and reuse exact same-owner originals', () => {
  const f = fixture();
  const first = f.compose(baseWire, undefined, document('first'));
  assert.equal(f.state.reads, 2);assert.equal(f.state.from, 2);
  const second = f.compose(baseWire, first, document('second'));
  assert.equal(f.state.reads, 4);assert.equal(f.state.from, 4);
  const reused = f.compose(baseWire, second);
  assert.equal(reused, second);assert.equal(f.state.reads, 4);assert.equal(f.state.from, 4);
  assert.deepEqual(second.body.connector_catalogs.map(v => v.connector_id).sort(), ['first', 'second']);
  assert.ok(Object.isFrozen(second.body) && Object.isFrozen(second.body.connector_catalogs));
  assert.equal(f.close(), true);assert.equal(f.state.retire, 1);
});

test('foreign and copied equal-wire Environment originals cannot substitute for the funded issuer', () => {
  const a = fixture(), b = fixture();const value = a.compose(baseWire);
  assert.throws(() => b.compose(baseWire, value), {code: 'ForeignInstalledEnvironmentOriginal'});
  assert.throws(() => a.compose(baseWire, {...value}), {code: 'ForeignInstalledEnvironmentOriginal'});
  a.close();b.close();
});

test('reservation refusal precedes generated read and failed undefined cause cannot revive construction', () => {
  const f = fixture();f.state.refuse = true;
  let failures = 0;
  for (let index = 0; index < 2; index++) try {f.compose(baseWire);assert.fail('Expected refusal');}
  catch (cause) {assert.equal(cause, undefined);failures++;}
  assert.equal(failures, 2);assert.equal(f.state.reads, 0);assert.equal(f.state.from, 0);
  f.state.refuse = false;assert.equal(f.close(), true);assert.equal(f.state.retire, 1);
});

test('currentness loss prevents reuse without starting another native admission', () => {
  const f = fixture();const value = f.compose(baseWire);const reads = f.state.reads;
  f.state.current = false;
  assert.throws(() => f.compose(value), /OriginalLost/);
  assert.equal(f.state.reads, reads);f.state.current = true;f.close();
});


test('only the same Source retirement ACK releases retained composition state', () => {
  const f = fixture();f.compose(baseWire);
  assert.throws(() => releaseRetiredInstalledEnvironmentComposition(f.services),
    {code: 'InstalledSourceRetirementPending'});
  f.state.refuse = true;
  try {f.compose(baseWire, undefined, document('failed'));assert.fail('Expected refusal');}
  catch (cause) {assert.equal(cause, undefined);}
  f.state.refuse = false;f.state.retireReady = false;
  assert.equal(f.close(), false);
  assert.throws(() => releaseRetiredInstalledEnvironmentComposition(f.services),
    {code: 'InstalledSourceRetirementPending'});
  try {f.compose(baseWire);assert.fail('Pending owner must retain its failure');}
  catch (cause) {assert.equal(cause, undefined);}
  f.state.retireReady = true;assert.equal(f.close(), true);
  // Retaining the closed services no longer retains the old construction
  // owner/failure/base. A new attempt observes the actual retired material.
  assert.throws(() => f.compose(baseWire), {code: 'ForeignInstalledSourceInitialization'});
});

test('installed aggregate composition requires original services before any load', async () => {
  let loads = 0;
  for (const installationServices of [undefined, {}, {...fixture().services}]) {
    await assert.rejects(composeInstalledEffects(['unused'], {moon: native, baseEnvironmentWire: baseWire,
      installationServices}, async () => {loads++;}), {code: 'ForeignInstalledHostServices'});
    await assert.rejects(loadInstalledSources(['unused'], {moon: native,
      installationServices}), {code: 'ForeignInstalledHostServices'});
  }
  let reads = 0;
  const options = {moon: native, baseEnvironmentWire: baseWire,
    get installationServices() {return reads++ === 0 ? undefined : fixture().services;}};
  await assert.rejects(composeInstalledEffects(['unused'], options, async () => {loads++;}),
    {code: 'ForeignInstalledHostServices'});
  assert.equal(reads, 1);
  assert.equal(loads, 0);
});

const releasedSlots = f => f.state.reconciled.at(-1).filter(value => f.state.zero.has(value)).length;
test('inventory replacement releases only its prior shallow prefix and keeps member originals', () => {
  const f = fixture();
  const member = f.inventory(undefined, document('member'));
  const prefix = f.inventory(member, document('second'));
  const before = releasedSlots(f);
  const final = f.inventory(prefix, document('third'), () => true);
  const released = releasedSlots(f);
  assert.ok(released > before, 'retired prefix must release its own construction quantities');
  assert.throws(() => f.inventory(prefix, document('fourth')), {code: 'ForeignInstalledEnvironmentOriginal'});
  // This failed call latches the same owner; the earlier completed output
  // still contains the same member leaves, without a second parse or refund.
  assert.equal(final.body.connector_catalogs.find(value => value.connector_id === 'member'), member.body.connector_catalogs[0]);
  assert.equal(releasedSlots(f), released, 'rejected reuse cannot release another original');
  f.close();
});

test('escaped and normally borrowed inventory prefixes retain their original custody', () => {
  for (const escaped of [false, true]) {
    const f = fixture(), member = f.inventory(undefined, document('member'));
    const prefix = f.inventory(member, document('second'), () => escaped);
    if (!escaped) assert.equal(f.compose(baseWire, prefix), prefix);
    const before = releasedSlots(f);
    f.inventory(prefix, document('third'), () => true);
    assert.equal(releasedSlots(f), before);
    f.close();
  }
});

test('failed acceptance and lost currentness keep the previous inventory prefix funded', () => {
  for (const loss of [false, true]) {
    const f = fixture(), member = f.inventory(undefined, document('member'));
    const prefix = f.inventory(member, document('second'));
    const before = releasedSlots(f), original = new Error('OriginalAcceptanceRefusal');
    assert.throws(() => f.inventory(prefix, document('third'), () => {
      if (loss) {f.state.current = false; return false;}
      throw original;
    }), loss ? /OriginalLost/ : value => value === original);
    assert.equal(releasedSlots(f), before);
    f.state.current = true;f.close();
  }
});

test('failed asynchronous successor preserves prefix and Source borrow until its actual settle', async () => {
  const f = fixture(), member = f.inventory(undefined, document('member'));
  const prefix = f.inventory(member, document('second'));
  const before = releasedSlots(f);
  let settle;
  f.state.delay = value => f.state.reads === 6 ? new Promise(resolve => {settle = () => resolve(value);}) : value;
  assert.throws(() => f.inventory(prefix, document('third')), {code: 'InstalledSourceConstructorNotSynchronous'});
  assert.equal(releasedSlots(f), before);
  assert.equal(f.close(), false);
  settle(); await Promise.resolve(); await Promise.resolve();
  assert.equal(f.close(), true);
});

test('Environment owner refuses reentry even during its first nominal reader lookup', () => {
  const f = fixture(); let reentries = 0;
  f.state.onCurrent = () => {
    f.state.onCurrent = undefined;
    assert.throws(() => f.compose(baseWire), {code: 'InstalledEnvironmentConstructionReentry'});
    reentries++;
  };
  f.compose(baseWire);
  assert.equal(reentries, 1);
  f.close();
});

test('one-sided manifest borrowing retains the actual earlier prefix envelope', () => {
  const f = fixture(), member = f.inventory(undefined, document('member'));
  const prefix = f.inventory(member, document('second'));
  const before = releasedSlots(f);
  const final = f.inventory(prefix, baseWire, () => true);
  assert.equal(final.body.connector_manifest, prefix.body.connector_manifest);
  assert.equal(releasedSlots(f), before);
  f.close();
});

test('ordinary Environment composition preserves its real pending metadata-load parent', async () => {
  const parent = createInstalledLoaderParent({root: '/component/environment-loading', moon: native});
  parent.open();
  try {
    const result = await withInstalledSourceLoading(parent.services, async () => {
      const original = composeInstalledSourceEnvironment(parent.services, native, baseWire, undefined, document('loaded'));
      assert.ok(original.admitted);
      assert.equal(retireInstalledSourceInitialization(parent.services), false,
        'the same active metadata load still prevents parent retirement');
      return original;
    });
    assert.ok(Object.isFrozen(result));
  } finally {await parent.close();}
});

test('inventory retirement tracking still refuses a real pending metadata-load parent', async () => {
  const parent = createInstalledLoaderParent({root: '/component/inventory-loading', moon: native});
  parent.open();
  try {
    await assert.rejects(withInstalledSourceLoading(parent.services, async () => {
      assert.equal(retireInstalledSourceInitialization(parent.services), false);
      return composeInstalledInventoryEnvironment(parent.services, native, baseWire, undefined,
        document('loaded'), () => true);
    }), {code: 'ForeignInstalledSourceInitialization'});
  } finally {await parent.close();}
});
