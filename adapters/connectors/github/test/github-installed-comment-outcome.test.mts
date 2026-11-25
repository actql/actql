import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import type {AnyNode, FunctionDeclaration, Identifier, Property, VariableDeclarator} from 'acorn';
import type {projectGitHubCommentObservation} from '../site/github-comment-create.mjs';

type SiteInput = Parameters<typeof projectGitHubCommentObservation>[0];
type Codec = SiteInput['moon'];
type Subject = Readonly<{subjectId: string}>;
type ProjectInput = Readonly<Pick<SiteInput, 'observation' | 'headers'> & {request: Subject}>;
type Projection = Readonly<{kind: string; observation?: SiteInput['observation']; providerEvidence?: unknown}>;
type Install = (classify: typeof projectGitHubCommentObservation, provider: Codec,
  limits: ReturnType<typeof captureInstalledStandardCreateLimits>) => (input: ProjectInput) => Projection;
import {captureInstalledStandardCreateLimits} from '../../../host-node/installed-effect-plan.mjs';

// Execute the installed standard write classifier and the actual Site
// classifier with an explicit typed-provider port. No provider request, Account
// grant, claim, confirming read or terminal receipt is supplied by this fixture.
const load = (relative: string) => {
  const source = readFileSync(new URL(relative, import.meta.url), 'utf8');
  return {source, ast: parse(source, {ecmaVersion: 'latest', sourceType: 'module'})};
};
const installed = load('../host/installed-github-effect.mjs');
const site = load('../site/github-comment-create.mjs');
function declaration(module: ReturnType<typeof load>, name: string) {
  const matches = module.ast.body.flatMap<FunctionDeclaration | VariableDeclarator>(statement => {
    const node = statement.type === 'ExportNamedDeclaration'
      ? statement.declaration : statement;
    if (node?.type === 'FunctionDeclaration' && (node.id as Identifier).name === name) return [node];
    if (node?.type === 'VariableDeclaration') {
      return node.declarations.filter(entry => (entry.id as Identifier).name === name);
    }
    return [];
  });
  assert.equal(matches.length, 1, name);
  const node = matches[0];
  return node.type === 'VariableDeclarator'
    ? `const ${module.source.slice(node.start, node.end)};`
    : module.source.slice(node.start, node.end);
}
const callbacks: Pick<Property, 'start' | 'end'>[] = [];
function visit(node: AnyNode | null | undefined) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'Property' && (node.key as Identifier).name === 'classify') callbacks.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  }
}
visit(installed.ast);
assert.equal(callbacks.length, 1, 'the installed comment write has one classifier');
const projectSource = installed.source.slice(callbacks[0].start, callbacks[0].end);
const classify = compileFunction(['fail', 'count', 'pairs', 'checkLimits',
  'projectGitHubCommentObservation'].map(name => declaration(site, name)).join('\n') +
  '\nreturn projectGitHubCommentObservation;')() as typeof projectGitHubCommentObservation;
const installProject = compileFunction(declaration(installed, 'commentOutcome') +
  `\nreturn ({${projectSource}}).classify;`,
  ['projectGitHubCommentObservation', 'providerMoon', 'commentLimits']) as Install;

function fixture(outcome: unknown, {statusCode = 200, headers = [], failure}:
  Readonly<{statusCode?: number; headers?: SiteInput['headers']; failure?: unknown}> = {}) {
  const observation = Object.freeze({statusCode,
    body: Buffer.from('{"fixture":"original-provider-response"}')});
  const request = Object.freeze({subjectId: 'I_original'});
  let calls = 0, limitCalls = 0;
  const moon = {installedStandardCreateHttpLimits() {
    limitCalls++;return [100_000,100_000,10_000,32];
  }, githubCommentOutcomeJson(status: number, names: string[], values: string[], body: Uint8Array,
    maxBytes: number, maxNodes: number, maxDepth: number, subjectId: string) {
    calls++;
    assert.equal(status, statusCode);
    assert.deepEqual(names, (headers ?? []).map(entry => entry[0]));
    assert.deepEqual(values, (headers ?? []).map(entry => entry[1]));
    assert.equal(body, observation.body);
    assert.deepEqual([maxBytes, maxNodes, maxDepth], [100_000, 10_000, 32]);
    assert.equal(subjectId, request.subjectId);
    if (failure) throw failure;
    return JSON.stringify(outcome);
  }};
  const project = installProject(classify, moon, captureInstalledStandardCreateLimits(moon));
  assert.equal(limitCalls,1);
  return {observation, calls: () => calls,
    run: () => project({request, observation, headers}),
    withoutHeaders: () => project({request, observation})};
}

test('installed comment Created remains provider evidence pending actual confirmation', () => {
  const original = fixture({outcome: 'Created', id: 7, nodeId: 'IC_original'});
  const result = original.run();
  assert.equal(result.kind, 'provider-response');
  assert.equal(result.observation, original.observation);
  assert.deepEqual(result.providerEvidence, {kind: 'CreatedComment',
    comment_id: 7, node_id: 'IC_original'});
  for (const field of ['outcome', 'operation_ref', 'operationRef']) {
    assert.equal(Object.hasOwn(result, field), false, field);
  }
  assert.equal(original.calls(), 1);
});

test('installed comment preserves known provider refusals', () => {
  for (const [outcome, statusCode, code, details] of [
    [{outcome: 'Refused', status: 403}, 403, 'GitHubCommentRefused', {http_status: 403}],
    [{outcome: 'Rejected', type: 'NOT_FOUND'}, 200, 'GitHubCommentRejected',
      {http_status: 200, type: 'NOT_FOUND'}],
  ] as const) {
    const original = fixture(outcome, {statusCode});
    assert.deepEqual(original.run(), {kind: 'typed-failure-response',
      outcome: {state: 'failed', error: {code,
        message: 'GitHub did not create the comment', details}}});
    assert.equal(original.calls(), 1);
  }
});

test('installed comment preserves Unknown and the original projection error', () => {
  for (const [statusCode, headers, kind, calls] of [
    [200, [], 'unclassified-response', 1],
    [429, [], 'provider-response', 1],
    [403, undefined, 'provider-response', 0],
  ] as const) {
    // Pass absent headers explicitly: this is the recovered-response path.
    const original = fixture({outcome: 'Unknown'}, {statusCode, headers});
    const run = headers === undefined ? original.withoutHeaders() : original.run();
    assert.deepEqual(run, {kind});
    assert.equal(original.calls(), calls);
    assert.equal(Object.hasOwn(run, 'outcome'), false);
  }
  const primary = new Error('OriginalProjectionFailure');
  const original = fixture(undefined, {failure: primary});
  assert.throws(original.run, error => error === primary);
  assert.equal(original.calls(), 1);
});
