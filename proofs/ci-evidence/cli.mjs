import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog, protectedRegistrationRevision} from './actions.mjs';
import {actionInputs, gitTree} from './inputs.mjs';
import {canonicalReceipt, sealReceipt} from './receipts.mjs';
import {checkApplications} from './applications.mjs';
import {actionsReader} from '../../scripts/ci-main-base.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const json = path => JSON.parse(readFileSync(path, 'utf8'));
const currentRevision = () => execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
const exact = (value, fields) => assert.deepEqual(Object.keys(value ?? {}).sort(), [...fields].sort());

// This first public CLI is intentionally comparison-only. The model/API
// checker has reuse rejection tests, but production activation requires the
// forthcoming reviewed runtime closure and trusted checkpoint comparison.
export async function command(operation, request) {
  const catalog = readCatalog();
  if (operation === 'catalog') return catalog;
  if (operation === 'plan') {
    exact(request, ['candidateRevision', 'runtime']);
    assert.equal(request.candidateRevision, currentRevision());
    const tree = gitTree(root, request.candidateRevision);
    return {version: 'actql-verification-action-plan/0.1', candidateRevision: request.candidateRevision,
      mode: 'comparison', reuseAuthorized: false, actions: catalog.actions.map(action => ({
        actionId: action.id, acquisition: 'execute', reason: 'Comparison before reviewed activation',
        inputs: actionInputs({tree, revision: request.candidateRevision, action, runtime: request.runtime})}))};
  }
  if (operation === 'seal') {
    exact(request, ['actionId', 'origin', 'runtime', 'output', 'status', 'milliseconds']);
    const action = catalog.actions.find(entry => entry.id === request.actionId);
    assert(action, 'Unregistered action');
    assert.equal(request.origin.testedRevision, currentRevision());
    const inputs = actionInputs({tree: gitTree(root, currentRevision()), revision: currentRevision(), action, runtime: request.runtime});
    return sealReceipt({origin: request.origin, action, inputs, output: request.output,
      status: request.status, milliseconds: request.milliseconds});
  }
  assert.equal(operation, 'check', 'Use catalog, plan, seal or check');
  assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Final applications need independent Actions context');
  exact(request, ['context', 'runtime', 'entries']);
  assert.equal(request.context.candidateRevision, currentRevision());
  assert.equal(request.context.candidateRevision, process.env.GITHUB_SHA);
  assert.equal(request.context.repository, process.env.GITHUB_REPOSITORY);
  assert.equal(request.context.runId, Number(process.env.GITHUB_RUN_ID));
  assert.equal(request.context.runAttempt, Number(process.env.GITHUB_RUN_ATTEMPT));
  assert(request.entries.every(entry => entry.acquisition === 'fresh'), 'Cross-revision reuse is not activated');
  return checkApplications({root, ...request, protectedRevision: protectedRegistrationRevision,
    request: actionsReader({repository: process.env.GITHUB_REPOSITORY, token: process.env.ACTIONS_READ_TOKEN})});
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [operation, ...args] = process.argv.slice(2);
  if (operation === 'catalog') { assert.equal(args.length, 0); console.log(encode(await command(operation))); }
  else {
    assert.equal(args.length, 4, 'Use --request REQUEST.json --out RESULT.json');
    assert.equal(args[0], '--request'); assert.equal(args[2], '--out');
    const result = await command(operation, json(args[1]));
    writeFileSync(args[3], operation === 'seal' ? canonicalReceipt(result) : `${encode(result)}\n`, {flag: 'wx'});
  }
}
