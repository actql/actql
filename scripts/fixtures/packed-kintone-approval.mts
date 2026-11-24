import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {kintoneApprovalInstallation} from './kintone-approval/installed.fixture.mjs';
import {runInstalledRecordApprovalFixture, installedRecordDecision, installedRecordHttpCase,
  installedRecordReplyLossExpectation} from './record-approval/installed.fixture.mjs';

const replyLossExpectation = installedRecordReplyLossExpectation();
const decision = installedRecordDecision();
const selectedCase = installedRecordHttpCase(fileURLToPath(new URL('./kintone-approval/case.json', import.meta.url)));
test(process.env.ACTQL_RECORD_APPROVAL_HTTP_CASE !== undefined ? 'ordinary installed kintone executes the authored HTTP case'
  : decision === 'rejected'
  ? 'ordinary installed kintone rejects the original checkpoint without provider writes'
  : replyLossExpectation === undefined
  ? 'ordinary installed kintone reviews, approves once and reads original Saved before status'
  : 'ordinary installed kintone applied-write reply loss and same-original lookup without resend',
  {timeout: 100000}, t => runInstalledRecordApprovalFixture(t,
    {createInstallation: kintoneApprovalInstallation, ...selectedCase, replyLossExpectation, decision}));
