import test from 'node:test';
import {kintoneApprovalInstallation} from './kintone-approval/installed.fixture.mjs';
import {runInstalledRecordApprovalFixture, installedRecordReplyLossExpectation} from './record-approval/installed.fixture.mjs';
import {sharedRecordUpdateSelections} from './record-approval/cases.mjs';

const replyLossExpectation = installedRecordReplyLossExpectation();
test(replyLossExpectation === undefined
  ? 'ordinary installed kintone reviews, approves once and reads original Saved before status'
  : 'ordinary installed kintone applied-write reply loss and same-original lookup without resend',
  {timeout: 100000}, t => runInstalledRecordApprovalFixture(t,
    {...kintoneApprovalInstallation(sharedRecordUpdateSelections.kintone), replyLossExpectation}));
