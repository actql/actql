import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {hubspotApprovalInstallation} from './hubspot-approval/installed.fixture.mjs';
import {runInstalledRecordApprovalFixture, installedRecordDecision, installedRecordReplyLossExpectation} from './record-approval/installed.fixture.mjs';

const replyLossExpectation = installedRecordReplyLossExpectation();
const decision = installedRecordDecision();
test(decision === 'rejected'
  ? 'ordinary installed HubSpot rejects the original checkpoint without provider writes'
  : replyLossExpectation === undefined
  ? 'ordinary installed HubSpot reviews, approves once and reads original Saved before status'
  : 'ordinary installed HubSpot applied-write reply loss and same-original lookup without resend',
  {timeout: 100000}, t => runInstalledRecordApprovalFixture(t,
    {createInstallation: hubspotApprovalInstallation,
      casePath: fileURLToPath(new URL('./hubspot-approval/case.json', import.meta.url)), replyLossExpectation, decision}));
