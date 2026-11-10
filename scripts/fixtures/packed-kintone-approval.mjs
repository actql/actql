import test from 'node:test';
import {kintoneApprovalInstallation} from './kintone-approval/installed.fixture.mjs';
import {runInstalledRecordApprovalFixture} from './record-approval/installed.fixture.mjs';

test('ordinary installed kintone reviews, approves once and reads original Saved before status',
  {timeout: 100000}, t => runInstalledRecordApprovalFixture(t, kintoneApprovalInstallation({
    recordId: '9007199254740993', controlId: '9007199254740994',
    previousName: 'Before kintone approval', nextName: 'After kintone approval'})));
