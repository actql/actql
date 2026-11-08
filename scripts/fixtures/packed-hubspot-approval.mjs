import test from 'node:test';
import {hubspotApprovalInstallation} from './hubspot-approval/installed.fixture.mjs';
import {runInstalledRecordApprovalFixture} from './record-approval/installed.fixture.mjs';

test('ordinary installed HubSpot reviews, approves once and reads original Saved before status',
  {timeout: 100000}, t => runInstalledRecordApprovalFixture(t, hubspotApprovalInstallation({
    recordId: '9007199254740993', controlId: '9007199254740994',
    previousName: 'Before HubSpot approval', nextName: 'After HubSpot approval'})));
