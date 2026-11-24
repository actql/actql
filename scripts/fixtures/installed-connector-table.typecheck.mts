// Compile-only DATA/current-owner correspondence; importing a generated entry
// does not manufacture the original process-local table handle.
import {installedConnectors} from '../../adapters/connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable, assertInstalledConnectorTable} from '../../adapters/host-node/installed-connectors.mjs';
import type {InstalledConnectorEntry, InstalledConnectorTable} from '../../packages/local-node/index.d.ts';

const declarations: readonly InstalledConnectorEntry[] = installedConnectors;
const originalTable: InstalledConnectorTable = createInstalledConnectorTable(declarations);
const sameTable: InstalledConnectorTable = assertInstalledConnectorTable(originalTable);
// @ts-expect-error A declaration is DATA, not an issued table handle.
const fabricated: InstalledConnectorTable = installedConnectors[0];
// @ts-expect-error The generated declaration inventory is immutable.
installedConnectors.push({name: 'replacement'});
// @ts-expect-error Generated field contracts cannot be replaced through the view.
installedConnectors[0]!.name = 'replacement';
void [sameTable, fabricated];
