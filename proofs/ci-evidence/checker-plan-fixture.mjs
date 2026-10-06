// Full-catalog proof data with real immutable Git input identities. These
// supplied observations are model fixtures, not API/physical execution facts.
import {encode} from '../bounded-session/action-inputs.mjs';
import {gitTree, hash, actionInputs} from './inputs.mjs';
import {catalogPath, validateCatalog} from './actions.mjs';
import {leanRecords} from './applications.mjs';

export const planRevision = 'a3f551fd1f02cbb86aef45710311962df47bcd90';

export function completeCheckerFixture(root) {
  const tree = gitTree(root, planRevision);
  const catalog = validateCatalog(JSON.parse(tree.read(catalogPath)));
  const context = {candidateRevision: planRevision};
  const runtime = {profile: 'checker-model-fixture', unresolved: ['no runtime acceptance supplied']};
  const required = [], applications = [];
  for (const action of catalog.actions) {
    const inputs = actionInputs({tree, revision: planRevision, action, runtime});
    const receipt = {action, inputs, origin: {testedRevision: planRevision, event: 'workflow_dispatch', branch: 'main'},
      execution: {units: action.minimumUnits}};
    const records = leanRecords(action, inputs, {receipt}, context, 'fresh');
    required.push(records.required); applications.push(records.application);
  }
  return {required, applications, sourceRevision: planRevision,
    dataDigest: hash(encode({required, applications})), catalogDigest: hash(encode(catalog))};
}
