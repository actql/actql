import test from 'node:test';
import {kintoneApprovalInstallation} from './kintone-approval/installed.fixture.mjs';
import {runInstalledRecordApprovalFixture} from './record-approval/installed.fixture.mjs';
import {sharedRecordUpdateSelections} from './record-approval/cases.mjs';

test('ordinary installed kintone reviews, approves once and reads original Saved before status',
  {timeout: 100000}, t => runInstalledRecordApprovalFixture(t,
    kintoneApprovalInstallation(sharedRecordUpdateSelections.kintone)));
