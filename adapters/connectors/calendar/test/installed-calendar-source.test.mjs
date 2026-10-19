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


import {checkInstalledCalendarSourceProfile,loadInstalledCalendarSource} from '../host/installed-calendar-source.mjs';
const limits={maxResponseBytes:4096,maxNodes:512,maxDepth:16,maxPages:4,maxRows:10,maxRequests:4,perPage:2,
  maxCursorUnits:128,maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:4096,maxRowsWireNodes:100,
  maxRowsWireDepth:8,maxDeclarationBytes:4096,maxDeclarationNodes:1000,maxSecretBytes:128,maxCaBytes:16384};
const profile={version:'actql-installed-calendar-source/0.1',connectorId:'fixture',siteProfilePath:'/unused/site.json',
  accountConfigurationWire:'{}',limits};

test('installed Calendar snapshots the closed profile without inventing grants or bounds',()=>{
  const selected=checkInstalledCalendarSourceProfile(profile);
  assert.deepEqual(selected,profile);assert(Object.isFrozen(selected)&&Object.isFrozen(selected.limits));
  for(const patch of [{perPage:251},{maxPages:5,maxRequests:4},{maxRows:0},{maxSecretBytes:2147483647}])
    assert.throws(()=>checkInstalledCalendarSourceProfile({...profile,limits:{...limits,...patch}}),{code:'InvalidInstalledCalendarSourceProfile'});
  for(const value of [{...profile,resource:'free_busy'},{...profile,siteProfilePath:'relative'},
    {...profile,limits:{...limits,unexpected:1}}])
    assert.throws(()=>checkInstalledCalendarSourceProfile(value),{code:'InvalidInstalledCalendarSourceProfile'});
  const changing={...profile};Object.defineProperty(changing,'connectorId',{enumerable:true,get(){throw Error('must not invoke a profile accessor');}});
  assert.throws(()=>checkInstalledCalendarSourceProfile(changing),{code:'InvalidInstalledCalendarSourceProfile'});
});

test('installed Calendar refuses missing actual capacity or material before profile I/O',async()=>{
  await assert.rejects(loadInstalledCalendarSource(profile,{}),{code:'CalendarReaderCapacityUnavailable'});
  await assert.rejects(loadInstalledCalendarSource(profile,{readerCapacity:{}}),{code:'CalendarCredentialMaterialUnavailable'});
});
