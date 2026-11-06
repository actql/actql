import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {checkDriverRetirementSource, driverPath, scratchRetirementPath, inputStopPath, bridgeReclamationPath, importReclamationPath, strategyPath,blockAfter} from './driver-retirement-source.mjs';
import {retirementOverlay,retirementExecutable,retirementExecutionArtifacts} from './driver-retirement-overlay.mjs';
import {inspectDriverRetirement} from './driver-retirement-inspect.mjs';
import {snapshot,hash} from '../../inventory.mjs';
import {omitUnselectedTests,helperCompilation,helperImports,retirementCompilation,retirementPackageTargets,retirementJsOnlyFixtures} from './driver-retirement-compilation.mjs';
const root = fileURLToPath(new URL('../../../../',import.meta.url));
const read = p => readFileSync(root+p);
const changed = (path, from, to, anchor) => {
  const original = read(path).toString();
  const anchors = anchor === undefined ? [] : Array.isArray(anchor) ? anchor : [anchor];
  const body = anchors.reduce((source, entry) => blockAfter(source, entry), original);
  const pattern = new RegExp(from.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')
    .replace(/\s+/g,'\\s+'),'g');
  assert.equal([...body.matchAll(pattern)].length,1,
    'Mutation must reach unique actual boundary');
  const replacement = body.replace(pattern,to);
  assert.equal(original.split(body).length, 2, "Mutation owner closure must be unique");
  return p => p === path ? original.replace(body,replacement) : read(p);
};
test('executed Native artifact excludes same-basename Darwin debug data and missing executable',()=>{
  const debug=retirementExecutable+'.dSYM/Contents/Resources/DWARF/query_integration.whitebox_test.exe';
  assert.deepEqual(retirementExecutionArtifacts({[retirementExecutable]:'a'.repeat(64),[debug]:'b'.repeat(64)}),
    {[retirementExecutable]:'a'.repeat(64)});
  assert.throws(()=>retirementExecutionArtifacts({[debug]:'b'.repeat(64)}));
});
test('current driver/common owner source and additive Native overlay are admitted', () => {
  assert.equal(checkDriverRetirementSource(read).clearsProviderAfterCleanupSuccess,true);
  const {overlay,boundary} = retirementOverlay(read,snapshot(root));
  assert(boundary.compilation.omittedTests > 0);
  assert.equal(boundary.compilation.repositoryTestsRemoved,false);
  for(const path of retirementJsOnlyFixtures) {
    assert.equal(overlay[path],read(path).toString());
    assert.equal(boundary.compilation.inputs[path].preservedOriginalBytes,true);
    assert.deepEqual(boundary.compilation.inputs[path].omittedTests,[]);
  }
  assert.match(overlay[scratchRetirementPath],/println\(driver_retirement_probe\(provider, 0, 3\)\)/);
  assert.equal((overlay[scratchRetirementPath].match(/cleanup_managed_provider\(active\)/g)??[]).length,
    (read(scratchRetirementPath).toString().match(/cleanup_managed_provider\(active\)/g)??[]).length);
  assert.equal(overlay['src/query_integration/moon.pkg'].split('options(').length,2, 'Reuse existing package options');
  assert.match(overlay['src/query_integration/moon.pkg'], /cc-link-flags/);
  // Cleanup observers reuse the existing provider Ref and add no setup capture.
  assert(!overlay[driverPath].match(/driver_retirement_probe\(provider_execution, setup.task, [234]\)/));
  const host = 'src/query_integration/graph_host_custody_wbtest.mbt';
  for(const name of ['run_current_host_graph_relation_path','retry_graph_host_match_cleanup','assert_graph_host_match_rows']) {
    assert(boundary.compilation.inputs[host].keptDeclarations.some(d=>d.name===name));
    assert.equal((blockAfter(overlay[host],'fn '+name+'(').match(/assert_(?:true|eq)\(/g)??[]).length,
      (blockAfter(read(host).toString(),'fn '+name+'(').match(/assert_(?:true|eq)\(/g)??[]).length);
  }
});

// Completed scratch can retire while the original output remains live. That
// partial accounting cannot close retention, discard hooks or report cleanup.
for (const [name,from,to] of [
  ['unfinished task releases scratch', 'if !task_done(run, execution.task) {', 'if false {'],
  ['pending scratch releases its reservation',
    'if scratch_released && @resources.reservation_open(execution.reservation) {',
    'if @resources.reservation_open(execution.reservation) {'],
  ['current fence after provider observation is omitted',
    'if !task_execution_matches(run, execution) {', 'if false {'],
  ['partial release erases accounting failure', 'Err(issue) => return Err(issue)', 'Err(_) => ()'],
  ['partial release retires live retention',
    '@resources.settle_execution_reservation( run.ledger, execution.reservation, remaining_execution=0L, )',
    '@resources.settle_reservation(run.ledger, execution.reservation)'],
]) test('completed scratch correspondence rejects '+name,()=>{
  const mutated=changed(strategyPath,from,to,
    ['fn release_task_execution_owned(', 'if !execution.disposed']);
  assert.throws(()=>checkDriverRetirementSource(mutated));
});
test('completed scratch cannot acknowledge cleanup or discard original hooks',()=>{
  const original=read(strategyPath).toString();
  const branch=blockAfter(blockAfter(original, 'fn release_task_execution_owned('),
    'if !execution.disposed');
  const ending='\n    return Ok(false)\n  }';
  assert(branch.endsWith(ending), 'Mutation must reach the original partial-release return');
  assert.equal(original.split(branch).length,2, 'Completed scratch branch must be unique');
  for (const replacement of ['return Ok(true)', 'execution.hooks = None\nreturn Ok(false)']) {
    const replaced=branch.slice(0,-ending.length)+'\n    '+replacement+'\n  }';
    const mutated=path=>path===strategyPath?original.replace(branch,replaced):read(path);
    assert.throws(()=>checkDriverRetirementSource(mutated));
  }
});

test('selected Host helper retains transitive declarations and enum variants without weakening warning checks',()=>{
  const sources={a:'fn run_current_host_graph_relation_path() { leaf() }\nfn leaf() { accept(Second) }\nfn unused() { leaf() }',
    b:'enum Kind {\n First\n Second\n}\nfn accept(x : Kind) { ignore(x) }'};
  const r=helperCompilation(sources,'test { run_current_host_graph_relation_path() }');
  assert(!r.overlay.a.includes('fn unused'));
  assert(r.overlay.b.includes('enum Kind'));
  for(const [path,s] of Object.entries(sources))for(const d of r.inputs[path].keptDeclarations) {
    assert.equal(r.overlay[path].slice(d.begin,d.end),s.slice(d.begin,d.end));
  }
  const pkg='supported_targets = "+native"\nimport {\n "x/used" @used,\n "x/unused" @unused,\n} for "wbtest"\noptions(link: {})\n';
  const imports=helperImports(pkg,'fn f() { @used.f() }');
  assert(!imports.text.includes('x/unused'));assert(imports.text.includes('options(link: {})'));
  assert.deepEqual(imports.omitted,[{path:'x/unused',alias:'unused'}]);
  assert.throws(()=>helperImports(pkg.replace('"x/used" @used,','dynamic_import()'),r.referencedText));
});

test('Native fixture projection retains both original JS-only targets and native link metadata',()=>{
  const original=read('src/query_integration/moon.pkg').toString();
  const clause=`  targets: {
    "strategy_cleanup_current_js_wbtest.mbt": [ "js" ],
    "row_stream_current_js_wbtest.mbt": [ "js" ],
  },`;
  const added=clause.replace('  },','    "driver_retirement_native_wbtest.mbt": [ "native" ],\n  },');
  const projected=retirementPackageTargets(original);
  assert.equal(projected.split(added).length,2);
  assert.equal(projected.replace(added,clause),original);
  for(const path of retirementJsOnlyFixtures) {
    const name=path.split('/').at(-1);
    for(const changed of [original.replace(name,'unknown_wbtest.mbt'),
      original.replace(`"${name}": [ "js" ]`,`"${name}": [ "native" ]`),
      original.replace(clause,clause+'\n'+clause)]) {
      assert.throws(()=>retirementPackageTargets(changed),/Changed reviewed query fixture targets/);
    }
  }
});

test('Native fixture projection keeps both compiler-excluded JS files and refuses unreviewed foreign declarations',()=>{
  const pkg='src/query_integration/moon.pkg',fixture='src/query_integration/driver_retirement_native_wbtest.mbt';
  const host='src/query_integration/host_wbtest.mbt',unknown='src/query_integration/unreviewed_wbtest.mbt';
  const js='#external\npriv type Loader\nextern "js" fn load() -> Loader = "load"\n';
  const sources={[host]:'fn run_current_host_graph_relation_path() {}\n',
    ...Object.fromEntries(retirementJsOnlyFixtures.map(path=>[path,js]))};
  const originalPkg=read(pkg).toString();
  const source={sources:Object.fromEntries(Object.entries(sources).map(([path,text])=>[path,hash(text)]))};
  const overlay={[pkg]:retirementPackageTargets(originalPkg),[fixture]:'test { run_current_host_graph_relation_path() }'};
  const reader=path=>path===pkg?originalPkg:sources[path];
  const result=retirementCompilation(reader,source,overlay);
  for(const path of retirementJsOnlyFixtures) {
    assert.equal(overlay[path],js);
    assert.equal(result.inputs[path].preservedOriginalBytes,true);
    assert.deepEqual(result.inputs[path].omittedTests,[]);
    assert.throws(()=>retirementCompilation(reader,source,
      {[pkg]:retirementPackageTargets(originalPkg),[fixture]:overlay[fixture],[path]:''}),
      /Changed compiler-excluded JS fixture/);
  }
  const extra={...sources,[unknown]:js};
  const extraSource={sources:{...source.sources,[unknown]:hash(js)}};
  assert.throws(()=>retirementCompilation(path=>path===pkg?originalPkg:extra[path],extraSource,
    {[pkg]:retirementPackageTargets(originalPkg),[fixture]:overlay[fixture]}),/Unsupported helper declaration #/);
});

test('projection keeps complete immutable raw String constants and omits unreferenced literal ranges',()=>{
  const unused='let unused : String =\n  #|{ "brace": "}🙂", "test": "raw" }\n';
  const owned='priv let message : String =\n  #|first line leaf\n  #|second line { and }\n';
  const helpers='fn run_current_host_graph_relation_path() { use(message) }\nfn use(x : String) { ignore(x) }\nfn leaf() {}\n';
  const source=unused+'\n'+owned+'\n'+helpers;
  const result=helperCompilation({a:source},'test { run_current_host_graph_relation_path() }');
  const constant=result.inputs.a.keptDeclarations.find(d=>d.name==='message');
  assert(constant);assert.equal(source.slice(constant.begin,constant.end),owned);
  assert.equal(result.overlay.a.slice(constant.begin,constant.end),owned);
  assert(result.inputs.a.keptDeclarations.some(d=>d.name==='leaf'),'Identifiers in raw literals retain the conservative closure');
  const omitted=result.inputs.a.omittedDeclarations.find(d=>d.name==='unused');
  assert(omitted);assert.equal(source.slice(omitted.begin,omitted.end),unused);
  assert.match(result.overlay.a.slice(omitted.begin,omitted.end),/^[ \r\n]*$/);
  for(let i=0;i<source.length;i++) {
    if(i<omitted.begin || i>=omitted.end || /[\r\n]/.test(source[i])) assert.equal(result.overlay.a[i],source[i]);
  }
});
test('projection preserves complete quoted String constants without evaluating initializers',()=>{
  const owned='let message : String = '+JSON.stringify('{"value":"leaf🙂"}')+'\n';
  const source=owned+'fn leaf() {}\nfn run_current_host_graph_relation_path() { ignore(message) }\n';
  const result=helperCompilation({a:source},'test { run_current_host_graph_relation_path() }');
  const constant=result.inputs.a.keptDeclarations.find(d=>d.name==='message');
  assert(constant);assert.equal(result.overlay.a.slice(constant.begin,constant.end),owned);
  assert(result.inputs.a.keptDeclarations.some(d=>d.name==='leaf'));
});
for(const declaration of [
  'let x : String = open_store()\n',
  'let x =\n  #|raw\n',
  'let mut x : String =\n  #|raw\n',
  'let x : Int =\n  #|raw\n',
  'let x : String = "quoted" + effect()\n',
  'let x : String = "\\q"\n',
  'let x : String = "quoted" effect()\n',
  'let x : String = "quoted"\n + effect()\n',
  'let x : String = "\\{effect()}"\n',
  'let x : String =\n  $|\\{effect()}\n',
  'let x : String =\n  #|raw\n  + effect()\n',
  'pub let x : String =\n  #|raw\n',
]) test('projection refuses non-literal or unreviewed constant '+JSON.stringify(declaration),()=>{
  assert.throws(()=>helperCompilation({a:declaration+'fn run_current_host_graph_relation_path() {}\n'},
    'test { run_current_host_graph_relation_path() }'),/Unsupported helper|interpolated raw/);
});

test('local compilation preserves helpers and ignores braces in literals, interpolation and comments',()=>{
  const helper = 'fn helper() { assert_eq("}", "}") }\n';
  const first = 'test "omit { name }" { let x = "\\{if true { "}" } else { "{" }}"\n /* { /* } */ } */\n let y = \'{\'\n // }\n helper() }';
  const second = 'test {\n  let raw =\n    #|{ "test": "}" }\n  helper()\n}';
  const after = '\nfn last() { helper() }\n';
  const input = helper+first+'\n'+second+after;
  const result = omitUnselectedTests(input);
  assert.equal(result.omitted.length,2);
  assert(result.text.startsWith(helper)); assert(result.text.endsWith(after));
  assert.deepEqual(result.omitted.map(r=>r.digest),[hash(first),hash(second)]);
  for (let i=0;i<input.length;i++) {
    if (!result.omitted.some(r=>i>=r.begin&&i<r.end) || /[\r\n]/.test(input[i])) assert.equal(result.text[i],input[i]);
  }
});
for (const source of ['test "bad" {', 'test fn x() {}', 'fn x() { "unterminated }', 'test { /* never ends }', 'test {\n $|\\{x}\n}', '#[ignore]\ntest { }']) {
  test('compilation refuses ambiguous input '+JSON.stringify(source),()=>{
    assert.throws(()=>omitUnselectedTests(source));
  });
}
for (const [name,path,from,to,anchor] of [
  ['retirement progress stops advancing',scratchRetirementPath,'cursor.steps += 1L','cursor.steps += 0L'],
  ['retirement loses actual value reclamation work',driverPath,'finalization_reclamation_steps.val = @execution.managed_output_values_reclamation_steps(\n        values,\n      )','finalization_reclamation_steps.val = 0L','let release_owned_scratch = fn()'],
  ['ignore cleanup error',scratchRetirementPath,'Err(_) => false','Err(_) => true','fn release_local_managed_provider_scratch('],
  ['ignore physical stop',scratchRetirementPath,'if !@local.managed_provider_stopped(active) {','if false {','fn release_local_managed_provider_scratch('],
  ['retain provider forever',scratchRetirementPath,'provider.val = None','provider.val = Some(active)','fn release_local_managed_provider_scratch('],
  ['drop root before pending return',scratchRetirementPath,'return false','provider.val = None\nreturn false','if !@local.managed_provider_stopped(active)'],
  ['scratch witness accepts live root',driverPath,'(provider_execution.val is None || provider_completion_retained.val) &&','true &&','scratch_released: fn()'],
  ['pending provider fabricates retained completion',scratchRetirementPath,'@local.managed_provider_retained_completion(active)','true','fn release_local_managed_provider_scratch('],
  ['failed task uses completed provider handoff',scratchRetirementPath,'if completed &&','if true &&','fn release_local_managed_provider_scratch('],
  ['whole retention accepts scratch handoff',driverPath,'provider_execution.val is None &&','(provider_execution.val is None || provider_completion_retained.val) &&','retention_released: fn()'],
  ['scratch witness skips partial retirement',driverPath,'scratch_retirement.phase == Retired &&','true &&'],
  ['driver starts with retired cursor',driverPath,'let scratch_retirement = local_managed_scratch_retirement()','let scratch_retirement = {phase: Retired, index: 0}'],
  ['retirement skips active callback check',driverPath,'      scratch_uses.val != 0 ||','      false ||','let release_owned_scratch = fn()'],
  ['retirement skips physical provider custody',driverPath,'(provider_execution.val is Some(_) && !provider_completion_retained.val) ||','false ||','let release_owned_scratch = fn()'],
  ['retirement skips pending input revocation',driverPath,'(!live.val && input_stop.phase != Stopped)','false'],
  ['retirement drops pending admission owner',driverPath,'if !@execution.managed_output_values_scratch_released(values) {','if false {'],
  ['scratch witness skips pending input revocation',driverPath,'(live.val || input_stop.phase == Stopped) &&','true &&'],
  ['input revocation bulk closes',inputStopPath,'while steps < 64','while steps < 64000'],
  ['input revocation allows reentrancy',inputStopPath,'if cursor.advancing {','if false {'],
  ['input revocation skips import cancellation',inputStopPath,'!cancel_import(importer)','false'],
  ['input revocation skips pending bridge',inputStopPath,'!close_bridge(bridge)','false'],
  ['input revocation drops bridge root',inputStopPath,'let input = bridges[cursor.index].val','let input = bridges[cursor.index].val\nbridges[cursor.index].val = None'],
  ['cleanup skips pending input revocation',driverPath,'if !stop_owned_inputs() {','if false {'],
  ['driver bulk-reclaims one bridge',driverPath,'advance_close_managed_producer_bridge(bridge, 1)','advance_close_managed_producer_bridge(bridge, 64000)'],
  ['driver drops pending snapshot importer',driverPath,'retained_imports.push(importing)','ignore(importing)'],
  ['bridge mutates handed-off rows',bridgeReclamationPath,'if bridge.handed_off {','if false {'],
  ['bridge skips active reader',bridgeReclamationPath,'quantum <= 0 || bridge.admitted.buffer.reading','quantum <= 0'],
  ['import mutates completed rows',importReclamationPath,'if value.completed {','if false {'],
  ['import skips partial buffer',importReclamationPath,'if !advance_admitted_buffer_reclamation(value.admitted.buffer, quantum) {','if false {'],
  ['retirement starts complete',scratchRetirementPath,'{ phase: Bridges, index: 0, steps: 0L, }','{ phase: Retired, index: 0, steps: 0L, }'],
  ['retirement clears too many roots',scratchRetirementPath,'while steps < 64','while steps < 64000'],
  ['retirement skips read roots',scratchRetirementPath,'reads[cursor.index] = None','ignore(reads[cursor.index])'],
  ['retirement bulk-clears issuers',scratchRetirementPath,'issuers.pop() |> ignore','issuers.clear()'],
  ['late import writes reopen settled roots',scratchRetirementPath,'live && !settled && !disposed','live && !disposed'],
  ['reservation returned before scratch',strategyPath,'remaining_execution=if scratch_released { 0L } else { execution.scratch }','remaining_execution=0L'],
  ['ignore retention release',strategyPath,'if !scratch_released || !retention_released {','if !scratch_released {','fn release_task_execution_owned('],
  ['cleanup observation allows synchronous reentry',strategyPath,'CleanupChecking => return Ok(false)','CleanupChecking => ()','fn release_task_execution('],
  ['cleanup observation erases prior accounting refusal',strategyPath,'(Ok(false), CleanupRefused(issue)) => Err(issue)','(Ok(false), CleanupRefused(_)) => Ok(false)','fn release_task_execution('],
  ['cleanup observation marks refused accounting ready',strategyPath,'Err(issue) => CleanupRefused(issue)','Err(_) => CleanupReady','fn release_task_execution('],
  ['cleanup drops original observation while pending',strategyPath,'Ok(false) => previous','Ok(false) => CleanupReady','fn release_task_execution('],
  ['owned cleanup swallows failed holding release',strategyPath,'Err(issue) => return Err(issue)','Err(_) => ()','if execution.failed_holding is Some(holding)'],
  ['owned cleanup clears holding on refused release',strategyPath,'Err(issue) => return Err(issue)','Err(_) => execution.failed_holding = None','if execution.failed_holding is Some(holding)'],
  ['owned cleanup skips revoked output holding',strategyPath,'match release_captured_task_retention(run, execution.task)','match Ok(true)','fn release_task_execution_owned('],
  ['owned cleanup reports pending retention as success',strategyPath,'Ok(false) => return Ok(false)','Ok(false) => ()','match release_captured_task_retention(run, execution.task)'],
]) test('source rejects '+name,()=>{
  // A missing mutation target is a failed fixture, not a rejected mutation.
  const mutated = changed(path,from,to,anchor);
  assert.throws(()=>checkDriverRetirementSource(mutated));
});

function records() {
  return ['current_filter','current_edge_filter'].flatMap((variant,i)=> {
    const root=String(100+i),provider=String(900+i);
    const rootRecord=(phase,p)=>'ACTQL_DRIVER_ROOT:'+JSON.stringify({task:phase >= 2 ? 0 : 3,phase,root,rootRequestedBytes:16,provider:p});
    const ledger=(phase,execution)=>'ACTQL_DRIVER_LEDGER:'+JSON.stringify({phase,execution,retention:20,held:phase==='pending'?40:24,transfer:0,retiredHoldingBytes:16,liveOutputBytes:20});
    return ['ACTQL_DRIVER_CASE:'+variant,rootRecord(0,null),rootRecord(1,provider),
      rootRecord(2,provider),rootRecord(2,provider),ledger('pending',100),rootRecord(3,null),
      ledger('cleaned',60),rootRecord(4,null),ledger('repeated',60),'ACTQL_DRIVER_CASE_DONE:'+variant];
  });
}
test('two complete finite Host traces retain pending root and return scratch once',()=>{
  const result=inspectDriverRetirement(records().join('\n'));
  assert.equal(result.cases.length,2);assert.equal(result.physicalGCDestruction,false);
});
for (const [name,mutate] of [
  ['early root release',a=>{a[3]=a[3].replace('"provider":"900"','"provider":null');}],
  ['replacement provider identity',a=>{a[4]=a[4].replace('"900"','"901"');}],
  ['missing pending error',a=>{a.splice(4,1);}],
  ['missing successful clear',a=>{a.splice(6,1);}],
  ['same-size replacement root',a=>{a[6]=a[6].replace('"root":"100"','"root":"101"');}],
  ['duplicate scratch credit',a=>{a[9]=a[9].replace('"execution":60','"execution":59');}],
  ['unrelated holding release',a=>{a[7]=a[7].replace('"held":24','"held":23');}],
  ['replaced original holding quote',a=>{a[7]=a[7].replace('"retiredHoldingBytes":16','"retiredHoldingBytes":15');}],
  ['lost live output backing',a=>{for(let i=0;i<a.length;i++)a[i]=a[i].replace('"liveOutputBytes":20','"liveOutputBytes":25');}],
  ['missing original holding quote',a=>{a[5]=a[5].replace(',"retiredHoldingBytes":16','');}],
  ['missing second Host completion',a=>{a.pop();}],
  ['wrong ABI extent',a=>{a[1]=a[1].replace('"rootRequestedBytes":16','"rootRequestedBytes":24');}],
]) test('observation rejects '+name,()=>{
  const a=records();mutate(a);assert.throws(()=>inspectDriverRetirement(a.join('\n')));
});
