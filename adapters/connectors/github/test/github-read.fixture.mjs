import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Shared actual GitHub Credential/SQLite/HTTPS caller fixture. It exercises
// existing Owners with explicit fixture authority; it is not normal funding.
import assert from 'node:assert/strict';
import {generateKeyPairSync, randomUUID} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as commonMoon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as moon from '../../../../_build/js/release/build/connectors/github/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {callHttpsCredentialResource, openHttpsCredentialBinding, closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {GITHUB_GRAPHQL_READ_OPERATION, readGitHubIssuesByNode, readGitHubPullRequestsByNode, readGitHubIssueCommentsByNode} from '../site/github-issue-graphql-read.mjs';
import {graphqlRoute} from './github-graphql.fixture.mjs';

const control = runtimeCore(commonMoon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const A = {nodeId: 'R_A', databaseId: 1296269, nameWithOwner: 'octo/hello'};

export async function openGitHubReadFixture(t, state, {faults = [], beforeAuthorize, accounted = false, resource = 'issues'} = {}) {
  assert.ok(resource === 'issues' || resource === 'pull_requests' || resource === 'issue_comments');
  const readRows = resource === 'issues' ? readGitHubIssuesByNode
    : resource === 'pull_requests' ? readGitHubPullRequestsByNode : readGitHubIssueCommentsByNode;
  const fixture = await openHttpsExchangeFixture(t, {faults,
    routes: [graphqlRoute(() => state)]});
  const root = await mkdtemp(join(tmpdir(), 'actql-github-graphql-'));
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential-authority.key'), authority.privateKey.export({format: 'pem', type: 'pkcs8'}), {mode: 0o600});
  await writeFile(join(root, 'credential-authority.pub'), authority.publicKey.export({format: 'pem', type: 'spki'}));
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([['authority-a',
      new Map([['key-a', authority.publicKey]])]]),
  });
  let binding;
  let rowRun;
  t.after(async () => {
    if (binding !== undefined) assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    if (rowRun !== undefined) rowRun.close();
    journal.close();
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      await writeFile(join(root, 'physical-requests.json'), JSON.stringify(fixture.seen()), {mode: 0o600});
      t.diagnostic(`Retained GitHub GraphQL credential fixture: ${root}`);
    } else await rm(root, {recursive: true, force: true});
  });
  const scope = Object.freeze({
    issuerAuthority: 'authority-a', principal: 'principal-a',
    namespaceId: 'namespace-a', environment: 'production', siteKey: 'site-a',
    siteGeneration: 1, runtimeBundleCid: cid('a'),
    connectorRegistration: 'github', connectorRevision: 'github/0.1',
    resourceOrigin: fixture.origin, operation: GITHUB_GRAPHQL_READ_OPERATION,
    runInvocationCid: cid('b'), taskAttempt: 1, dispatchRequestCid: cid('c'),
    expiresUnixMilliseconds: 2_000_000_000_000n, maxUses: 32,
  });
  const grant = control.prepare(scope);
  journal.acceptGrant(signRemoteCredentialGrant(grant, control,
    {keyId: 'key-a', privateKey: authority.privateKey}), control);
  const credential = {control, journal, resolveSecret: async () => 'token-a',
    ca: fixture.ca, now: () => 1_999_999_999_999};
  if (accounted) {
    binding = openHttpsCredentialBinding({...credential, scope, maxSecretBytes: 128});
    credential.binding = binding;
    rowRun = await accountedGitHubRows(() => closeHttpsCredentialBinding(binding) === 'closed', resource);
  }
  let reads = 0;
  const read = (overrides = {}) => {
    const id = reads++;
    return readRows({moon, repository: A,
      credential,
      callResource: callHttpsCredentialResource,
      authorizationFor: async index => {
        await beforeAuthorize?.(index);
        return {grant, scope, useId: `read-${id}-${index}`};
      },
      limits: {maxPages: 5, maxRows: 100, maxBytes: 100_000,
        maxNodes: 10_000, maxDepth: 32, perPage: 100,
        maxRequestBytes: 16_384, maxSubjects: 100},
      ...(rowRun === undefined ? {} : {chargePage: rowRun.charge,
        consumeObservation: rowRun.observe, consumePage: rowRun.page}),
      ...overrides});
  };
  return {fixture, journal, read, rowRun, credential};
}

export async function accountedGitHubRows(verifyTransport, resource = 'issues') {
  const read = name => readFile(new URL('../../../../' + name, import.meta.url), 'utf8');
  const declaration = checked(commonMoon.clientProgramRowSourceRestoreRelationDeclaration(
    'gh', 'github', 'github/0.1', await read('src/connectors/github/source-views.json'), undefined));
  const declared = JSON.parse(commonMoon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const check = commonMoon.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  const view = declared.views.find(view => view.resource === resource);
  assert.ok(view);
  const publication = JSON.stringify({environmentCid: environment.evidenceCid, aliases: [{name: `gh.${resource}`,
    sourceRef: view.source_ref, sourceViewContractCid: view.view_cid, schemaContractCid: view.carrier_schema_cid}]});
  // This component explicitly selects the Query acquisition profile. Ordinary
  // unfiltered input uses the separate managed Whole-input path.
  const preparation = commonMoon.clientProgramPrepareSourceWithParameters(
    resource === 'issues' ? 'SELECT number, comments, state_reason, assignees, labels, url FROM gh.issues WHERE TRUE ORDER BY number'
      : resource === 'pull_requests' ? 'SELECT * FROM gh.pull_requests WHERE TRUE ORDER BY number'
      : 'SELECT * FROM gh.issue_comments WHERE TRUE ORDER BY id',
    'sql', check, publication, undefined, undefined);
  const program = commonMoon.clientProgramPreparationReady(preparation);
  assert.ok(program, commonMoon.clientProgramPreparationIssueCode(preparation));
  const aoa = JSON.parse(await read('spec/contracts/actql-aoa.json'));
  const values = JSON.stringify(aoa.execution_contracts['REL.values']);
  const fragment = JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
  const ordered = JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  const installedContracts = checked(commonMoon.clientPrepareInstalledSequenceContracts(
    await read('spec/dependencies/aoa-pipeline-registry.json'), values, fragment, ordered));
  const requirement = checked(commonMoon.clientProgramPrepareLocalQueryRequirement(program, 0, 0,
    installedContracts, values, fragment, ordered));
  const acquisition = checked(commonMoon.clientProgramRowSourcePrepareAcquisition(declaration, requirement,
    await read('spec/contracts/actql-query-acquisition.json'), await read('spec/contracts/actql-query-process-evidence.json')));
  const ledger = checked(commonMoon.clientProgramAcquisitionLedger(1, 1, 100000n, 100000000n, 100000000n, 0));
  const run = checked(commonMoon.clientProgramRowSourceStartAccounted(acquisition, randomUUID(), verifyTransport,
    ledger, 100000n, 100000n));
  checked(commonMoon.clientProgramRowSourceBegin(run, 100000, 5, 100, undefined));
  let charges = 0;
  let observations = 0;
  let receivedBytes = 0;
  return {
    charge: body => { charges++; receivedBytes += body.byteLength; return checked(commonMoon.clientProgramRowSourceChargePage(run, body)); },
    observe: charge => { observations++; return checked(commonMoon.clientProgramRowSourceConsumeObservationCharge(run, charge)); },
    page: (rows, _page, {charge}) => checked(commonMoon.clientProgramRowSourceAcceptChargedPage(run, charge, Buffer.from(JSON.stringify(rows)))),
    finish() {
      checked(commonMoon.clientProgramRowSourceFinish(run));
      const capture = checked(commonMoon.clientProgramRowSourceCapture(run));
      const source = checked(commonMoon.clientProgramRowSourceCaptureSource(capture));
      const relation = checked(commonMoon.clientProgramIdentifyCapturedSourceRelation(source));
      return commonMoon.clientProgramCapturedSourceRowCount(relation);
    },
    counts: () => ({charges, observations}),
    receivedBytes: () => receivedBytes,
    transferredBytes: () => ledgerUsageSnapshot(commonMoon.clientProgramMultiCapturedLedgerUsage(ledger)).transferredBytes,
    close() {
      checked(commonMoon.clientProgramRowSourceCloseAccounted(run));
      assert.deepEqual(ledgerUsageFieldsFor(commonMoon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
    },
  };
}
