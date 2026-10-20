import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdir, mkdtemp, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {installHostRunAcceptance} from './client-checkpoints.mjs';
import {canonicalJson} from './local-account-config.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const configuration = (outcome = 'allow', principal = 'owner') => canonicalJson({
  version: 'actql-execution-account-config/0.1', account_id: 'account-only',
  entries: [{entry_id: 'request', outcome, principal: {any_of: [principal]},
    connection: {any_of: ['site']}, resource: {any_of: ['realization']},
    operation: {any_of: ['write']}, exclusions: []}],
});
const request = {requested: {logicalRequestScopeCid: cid('1'),
  intentFingerprintCid: cid('2')}, captured: {principalId: 'owner'}};
const options = authorization => ({authorization, namespaceId: 'local',
  authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'site',
  realizationKey: 'realization'});

test('Account-only acceptance uses the admitted tuple and exposes no Checkpoint capability', async () => {
  const installed = await installHostRunAcceptance(options({
    accountConfiguration: configuration()}));
  assert.equal(installed.checkpoints, undefined);
  assert.deepEqual(await installed.runAcceptance.acceptRun(request), {kind: 'dispatch'});
  await assert.rejects(installed.runAcceptance.acceptRun({...request,
    captured: {principalId: 'foreign'}}), {code: 'ClientConnectionDenied'});
  installed.runAcceptance.stop();
  await assert.rejects(installed.runAcceptance.acceptRun(request),
    {code: 'ExecutionAuthorizationStopped'});
  installed.runAcceptance.close();
  installed.runAcceptance.close();
});

for (const [name, accountConfiguration, code] of [
  ['Deny', configuration('deny'), 'ACTQL_E_ACCOUNT_DENIED'],
  ['foreign Account tuple', configuration('allow', 'foreign'), 'ACTQL_E_ACCOUNT_NO_MATCH'],
  ['missing Account', undefined, 'ACTQL_E_ACCOUNT_CONFIG_INVALID'],
  ['Delegate without a signer', configuration('delegate'), 'ACTQL_E_DELEGATION_UNAVAILABLE'],
]) {
  test(`Account-only ${name} refuses rather than creating a Run or Checkpoint`, async () => {
    const installed = await installHostRunAcceptance(options({accountConfiguration}));
    try { await assert.rejects(installed.runAcceptance.acceptRun(request), {code}); }
    finally { installed.runAcceptance.close(); }
    assert.equal(installed.checkpoints, undefined);
  });
}

test('Account-only file currentness is checked again before another request', async () => {
  const scratch = new URL('../../_build/account-only-run-acceptance/', import.meta.url);
  await mkdir(scratch, {recursive: true});
  const directory = await mkdtemp(join(scratch.pathname, 'account-'));
  const accountConfig = join(directory, 'account.json');
  await writeFile(accountConfig, configuration());
  const installed = await installHostRunAcceptance(options({accountConfig}));
  try {
    assert.deepEqual(await installed.runAcceptance.acceptRun(request), {kind: 'dispatch'});
    await writeFile(accountConfig, configuration('deny'));
    await assert.rejects(installed.runAcceptance.acceptRun(request));
  } finally { installed.runAcceptance.close(); }
});

test('Completed Account-only request scopes release their shared retained-decision budget', async () => {
  const installed = await installHostRunAcceptance(options({
    accountConfiguration: configuration(), maxRetainedDecisions: 1}));
  try {
    for (const digit of ['1', '2', '3']) {
      assert.deepEqual(await installed.runAcceptance.acceptRun({...request,
        requested: {...request.requested, intentFingerprintCid: cid(digit)}}),
      {kind: 'dispatch'});
    }
  } finally { installed.runAcceptance.close(); }
});

test('Explicit null, empty and partial Checkpoint options retain the existing rejection', async () => {
  for (const selected of [null, {reviewers: null}, {reviewers: []},
    {reviewers: undefined}, {hostKey: {}}, {checkpointTtlMs: 1000}, {decide() {}}]) {
    await assert.rejects(installHostRunAcceptance(options(selected === null ? null : {
      accountConfiguration: configuration(), ...selected})), error =>
      ['InvalidRemoteHostAuthorization', 'InvalidCheckpointReviewers'].includes(error.code));
  }
});

test('Account-only configuration preserves the shared diagnostic observer type rule', async () => {
  for (const observe of [null, {}]) {
    await assert.rejects(installHostRunAcceptance(options({
      accountConfiguration: configuration(), observe})),
    {code: 'InvalidRemoteHostAuthorization'});
  }
});

test('A valid or omitted shared diagnostic observer does not select Checkpoint signing', async () => {
  for (const observe of [() => {}, undefined]) {
    const installed = await installHostRunAcceptance(options({
      accountConfiguration: configuration(), observe}));
    try {
      assert.equal(installed.checkpoints, undefined);
      assert.deepEqual(await installed.runAcceptance.acceptRun(request), {kind: 'dispatch'});
    } finally { installed.runAcceptance.close(); }
  }
});
