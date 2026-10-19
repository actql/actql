import assert from 'node:assert/strict';
import test from 'node:test';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable,installedConnectorForTable} from '../../../host-node/installed-connectors.mjs';

test('ordinary installed Source selection reaches the Calendar-owned factory',()=>{
  const table=createInstalledConnectorTable(installedConnectors);
  const selected=installedConnectorForTable(table,'source',{version:'actql-installed-calendar-source/0.1'});
  assert.equal(selected.registration,'calendar');
  assert.equal(selected.providerBundle,'connectors/calendar/host_node');
});
