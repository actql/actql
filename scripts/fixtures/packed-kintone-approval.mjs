import test from 'node:test';
import {kintoneApprovalInstallation} from './kintone-approval/installed.fixture.mjs';
import {runInstalledRecordApprovalFixture, installedRecordDecision, installedRecordReplyLossExpectation} from './record-approval/installed.fixture.mjs';
import {sharedRecordUpdateSelections} from './record-approval/cases.mjs';

const replyLossExpectation = installedRecordReplyLossExpectation();
const decision = installedRecordDecision();
test(decision === 'rejected'
  ? 'ordinary installed kintone rejects the original checkpoint without provider writes'
  : replyLossExpectation === undefined
  ? 'ordinary installed kintone reviews, approves once and reads original Saved before status'
  : 'ordinary installed kintone applied-write reply loss and same-original lookup without resend',
  {timeout: 100000}, t => runInstalledRecordApprovalFixture(t,
    {...kintoneApprovalInstallation(sharedRecordUpdateSelections.kintone), replyLossExpectation, decision}));
