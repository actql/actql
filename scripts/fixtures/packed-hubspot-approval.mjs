import test from 'node:test';
import {hubspotApprovalInstallation} from './hubspot-approval/installed.fixture.mjs';
import {runInstalledRecordApprovalFixture, installedRecordReplyLossExpectation} from './record-approval/installed.fixture.mjs';
import {sharedRecordUpdateSelections} from './record-approval/cases.mjs';

const replyLossExpectation = installedRecordReplyLossExpectation();
test(replyLossExpectation === undefined
  ? 'ordinary installed HubSpot reviews, approves once and reads original Saved before status'
  : 'ordinary installed HubSpot applied-write reply loss and same-original lookup without resend',
  {timeout: 100000}, t => runInstalledRecordApprovalFixture(t,
    {...hubspotApprovalInstallation(sharedRecordUpdateSelections.hubspot), replyLossExpectation}));
