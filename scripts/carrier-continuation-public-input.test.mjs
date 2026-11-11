import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {carrierContinuationSuccesses as successes,carrierContinuationRefusals as refusals}
  from './fixtures/carrier-continuation-source-input.mjs';
test('F01/F02 recipes retain independent ordered schema and the valid Graph-to-Events tail',()=>{
  assert.equal(successes.length,13);
  assert.equal(refusals.length,15);
  assert.equal(new Set([...successes,...refusals].map(item=>item.name)).size,28);
  const rows=[{node_key:1,occurred_ms:0}];
  const columns=['node_key','occurred_ms'].map(name=>({name,contract:{type:'number',nullable:false}}));
  for(const item of successes) {
    assert.deepEqual(item.results,{[item.format==='json'?'answer':'main']:{rows,columns}});
    if(item.format==='json') continue;
    assert.match(item.text,/KEY \(node_key\) PROPERTIES \(occurred_ms\)/u);
    assert.doesNotMatch(item.text,/PROPERTIES \(node_key/u);
    if(item.name.includes('events-')) {
      assert.match(item.text,/to_events\(id: node_key, time: occurred_ms\)/u);
      assert.match(item.text,/events\(\)/u);
    }
    assert.match(item.text,/ORDER BY node_key/u);
    if(item.name.includes('source-events-')) {
      assert.match(item.text,/FROM records WHERE id = 1/u);
      assert.deepEqual(item.sourceRows,[{id:2,amount:20},{id:1,amount:null},{id:3,amount:30}]);
      assert.equal(item.sourceReadSessionCount,1);
    } else assert.equal(item.sourceReadSessionCount,0);
  }
  assert.equal(successes.filter(item=>item.sourceReadSessionCount===1).length,4);
  assert.ok(refusals.every(item=>item.expectedCode==='ClientProgramInvalidInput'));
  const valid=JSON.parse(successes[0].text);
  const invalid=JSON.parse(refusals.at(-1).text);
  assert.deepEqual(valid.stages[0].steps[1].graph.nodes[0].labels[0].properties.columns,
    [{from:'occurred_ms',to:'occurred_ms'}]);
  assert.deepEqual(invalid.stages[0].steps[1].graph.nodes[0].labels[0].properties.columns,
    [{from:'node_key',to:'node_key'},{from:'occurred_ms',to:'occurred_ms'}]);
  const shadow=refusals.find(item=>item.name.endsWith('shadowed-events-sql'));
  assert.doesNotMatch(shadow.text,/PROPERTIES \(node_key/u);
  assert.match(shadow.text,/WITH g AS \(FROM source_rows \|> to_events/u);
});

test('the same declared carrier cases are selected, copied, retained and registered normally',()=>{
  const corpus=readFileSync('scripts/fixtures/packed-public-query.mjs','utf8');
  const driver=readFileSync('scripts/test-packed-public-query.mjs','utf8');
  assert.match(corpus,/carrierContinuationOnly \? \{successes: carrierContinuationSuccesses, refusals: carrierContinuationRefusals\}/u);
  assert.ok(corpus.includes('scopeInputs.successes.push(...carrierContinuationSuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...carrierContinuationRefusals)'));
  assert.ok(driver.includes("['scripts/fixtures/carrier-continuation-source-input.mjs', 'carrier-continuation-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_CARRIER_CONTINUATION_ONLY = '1'"));
  assert.ok(corpus.includes('await carrierContinuationReceipts.record(item, mode)'));
  assert.ok(corpus.includes('await carrierContinuationReceipts.complete()'));
  const selection=driver.slice(driver.indexOf('const narrowPublicQuery ='),driver.indexOf('.includes(flag));',driver.indexOf('const narrowPublicQuery =')));
  assert.ok(selection.includes("'--carrier-continuation-only'"));
  assert.ok(driver.includes("? ['carrier-continuation-receipts.local.json', 'carrier-continuation-receipts.remote.json']"));
  const invocation=driver.indexOf("await exerciseRetainedQueryRestart({ACTQL_TEST_RETAINED_COHORT_ONLY: '1'});");
  const restart=driver.lastIndexOf('\nif (',invocation)+1;
  const conditionEnd=driver.indexOf(') {',restart);
  const blockEnd=driver.indexOf('\n}',invocation);
  assert.ok(restart>driver.indexOf("['packed-query-transports.mjs']"));
  assert.ok(conditionEnd>restart && conditionEnd<invocation && blockEnd>invocation);
  const condition=driver.slice(restart,conditionEnd+3);
  assert.ok(condition.includes("process.argv.includes('--carrier-continuation-only')"));
  const block=driver.slice(restart,blockEnd+2);
  assert.ok(block.includes("await exerciseRetainedQueryRestart({ACTQL_TEST_RETAINED_COHORT_ONLY: '1'});"));
  assert.ok(block.endsWith('  return;\n}'),'the selected retained restart finishes inside the same closed block');
});

test('the original carrier introduction adds only its declared cases to the retained parent',()=>{
  const read=path=>JSON.parse(readFileSync(path,'utf8'));
  const before=read('scripts/fixtures/pre-carrier-continuation-public-query-inventory.json');
  // Exact full inventory bytes introduced by ffa02f23b99d910f9445f6487b6adb7d44e2ba6a.
  // Later independent registrations belong to the separately checked current pin.
  const introduced=readFileSync('scripts/fixtures/submitted-carrier-continuation-public-query-inventory.json');
  assert.equal(createHash('sha256').update(introduced).digest('hex'),
    'abc6f64b0d6b01a640f04692c2797a0ea4774fdc9a934f69f8552f2bb3d2ad48');
  const after=JSON.parse(introduced);
  assert.equal(after.version,before.version);
  assert.equal(after.inventorySha256,'6533dbebaea5fcf3e8da992a0c5b5d51a31249ffaa27691d173e7960cec56c21');
  assert.equal(before.totalCases,4046);
  assert.deepEqual(before.counts,{successes:2539,executionFailures:53,refusals:1454});
  assert.equal(after.totalCases,before.totalCases+successes.length+refusals.length);
  assert.deepEqual(after.counts,{successes:before.counts.successes+successes.length,
    executionFailures:before.counts.executionFailures,refusals:before.counts.refusals+refusals.length});
  assert.equal(after.sourceBaseline,before.sourceBaseline);
  assert.deepEqual(after.repeatedFailures,before.repeatedFailures);
  assert.deepEqual(after.profiles.slice(1),before.profiles.slice(1));
  assert.deepEqual(after.profiles[0].counts,{successes:before.profiles[0].counts.successes+successes.length,
    executionFailures:before.profiles[0].counts.executionFailures,refusals:before.profiles[0].counts.refusals+refusals.length});
});
