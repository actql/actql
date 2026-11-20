import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

// Actual imported installed static service, original public template and
// current Common bridge. This is a source-checkout caller regression, not
// packed RC execution, a Model invocation or an Effect approval/write.
for (const [template, program, target] of [
  ['churn-risk-mock', 'churn-risk.aql', 'connector://salesforce/Account'],
  ['deal-review-mock', 'deal-review.aql', 'connector://salesforce/Opportunity'],
]) {
  test(`installed static Plan retains original ${template} INFER and Effect without executing either`, async () => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-static-model-',
      label: `original ${template} static Plan`});
    const project = scaffoldProject(join(scratch.path, 'project'), template);
    const before = await readFile(join(project.directory, 'mock/data.json'));
    const source = await readFile(join(project.directory, program), 'utf8');
    const cwd = process.cwd();
    let client, primary;
    process.chdir(project.directory);
    try {
      client = await connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
        installation: {directory: '.actql-static'}});
      const plan = await client.plan(source, {format: 'aql'});
      assert.equal(plan.version, 'actql-effectful-static-plan-view/0.1');
      assert.equal(plan.computation.scope, 'computation_component');
      assert.equal(plan.computation.plan_view.logical_map.steps.filter(step => step.operator === 'infer').length, 1);
      assert.equal(plan.effect_set.members.length, 1);
      assert.equal(plan.effect_set.members[0].effect_kind, 'update');
      assert.equal(plan.effect_set.members[0].contract.declared_target, target);
      assert.deepEqual(await readFile(join(project.directory, 'mock/data.json')), before);

    } catch (error) {primary = error;}
    finally {
      try {await client?.close();}
      catch (error) {primary = primary === undefined ? error :
        new AggregateError([primary, error], 'Original static Plan and cleanup failed');}
      finally {process.chdir(cwd);}
    }
    if (primary !== undefined) throw primary;
    scratch.passed();
    scratch.close();
  });
}
