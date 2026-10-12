// Independent closed envelope vectors; old Plan/Run identity domains remain exact.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {validWireRunPlanViewShape,validWirePlanViewShape} from '../packages/client-wire/index.mjs';
import {buildClientHostWire} from './generate-client-host-wire.mjs';
import {ref,cid} from './fixtures/interactive-run-control-vectors.mjs';
import {planOriginal} from '../adapters/host-node/fixtures/original-plan-journal.mjs';
const envelope=()=>({version:'actql-run-plan-view/0.1',run_ref:structuredClone(ref),plan_view:JSON.parse(planOriginal.planViewWire)});
test('Run Plan is closed and does not replace Plan View or manufacture an identity',()=>{
  const view=envelope();assert.equal(validWireRunPlanViewShape(view),true);
  assert.equal(validWirePlanViewShape(view.plan_view),true);
  assert.equal(validWirePlanViewShape(view),false);
  for (const value of [ {...view,run_ref:undefined},{...view,plan_view:undefined},
    {...view,version:'actql-plan-view/0.1'},{...view,self_cid:cid('0')},
    {...view,run_ref:{...ref,principal:'copied'}},
    {...view,plan_view:{...view.plan_view,provider_io:1}},
    {...view,plan_view:{...view.plan_view,preview:{}}} ]) assert.equal(validWireRunPlanViewShape(value),false);
});
test('Native shape stays test-only and follows the same resolved closed schema',()=>{
  const registry=JSON.parse(readFileSync('spec/contracts/actql-client-host.json','utf8'));
  const protocol=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'));
  const generated=buildClientHostWire(registry,protocol);
  assert.match(generated.nativeTests,/fn wire_run_plan_view_shape\(/u);
  assert.doesNotMatch(generated.native,/fn wire_run_plan_view_shape\(/u);
  assert.deepEqual(registry.operations['run-plan'],['connection','ref','maxWireBytes','maxNodes','maxDepth']);
});
