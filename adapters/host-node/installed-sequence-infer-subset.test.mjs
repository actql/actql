import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';

// Real Common preparation and Values-prefix execution. The original generated
// fixture supplies model contracts only; this test never invokes a provider.
const source=readFileSync(new URL('../../src/client_infer_host/fixture.generated_wbtest.mbt',import.meta.url),'utf8');
const input=name=>source.match(new RegExp(`let ${name} : String =\\n\\s+#\\|([^\\n]+)`,'u'))[1];

test('actual StartInferInput selects Values-only prefix from a full installed contract original',()=>{
  const environment=moon.clientProgramCheckEnvironment(input('infer_fixture_environment'),
    input('infer_fixture_environment_cid'),false,false,true,false,false,false,false);
  const prepared=moon.clientProgramPreparationReady(moon.clientProgramPrepareEffectFreeWithParameters(
    input('infer_fixture_program'),'json',environment,undefined));
  assert.notEqual(prepared,undefined);
  const registry=readFileSync(new URL('../../spec/dependencies/aoa-pipeline-registry.json',import.meta.url),'utf8');
  const aoa=JSON.parse(readFileSync(new URL('../../spec/contracts/actql-aoa.json',import.meta.url),'utf8'));
  const values=JSON.stringify(aoa.execution_contracts['REL.values']);
  const fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
  const ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  const original=checked(moon.clientPrepareInstalledSequenceContracts(registry,values,fragment,ordered));
  const step=moon.clientProgramSelectedInferStep(prepared);
  assert.equal(moon.clientProgramStartInferInput(prepared,original,'{}',step),undefined,
    'Explicit mismatched Values body cannot select another contract');
  const active=moon.clientProgramStartInferInput(prepared,original,values,step);
  assert.notEqual(active,undefined,'Full installed bundle must allow its Values-only subset');
  try {
    let rows;
    for(let work=0;work<100000&&rows===undefined;work+=256) {
      rows=moon.clientProgramInferInputRows(checked(moon.clientProgramAdvanceInferInput(active,256)));
    }
    assert.notEqual(rows,undefined,'The real local prefix must complete within the fixture work envelope');
  } finally {
    moon.clientProgramCancelInferInput(active);
    assert.equal(checked(moon.clientProgramCleanupInferInput(active)),true);
  }
});
