import test from 'node:test';
import {hubspotApprovalInstallation} from './hubspot-approval/installed.fixture.mjs';
import {runInstalledRecordApprovalFixture} from './record-approval/installed.fixture.mjs';
import {sharedRecordUpdateSelections} from './record-approval/cases.mjs';

test('ordinary installed HubSpot reviews, approves once and reads original Saved before status',
  {timeout: 100000}, t => runInstalledRecordApprovalFixture(t,
    hubspotApprovalInstallation(sharedRecordUpdateSelections.hubspot)));
