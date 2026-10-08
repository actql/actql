import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {connect} from '@actql/node';
import {createInstalledConnectorTable} from '@actql/local-node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {runInstalledConnectorTableAcceptance} from './connector-table-acceptance.mjs';

assert.throws(() => createRequire(import.meta.url).resolve('@duckdb/node-api'),
  {code: 'MODULE_NOT_FOUND'});
const result = await runInstalledConnectorTableAcceptance({connect,
  createInstalledConnectorTable, openInstalledRemoteHttpHost,
  directory: join(process.cwd(), 'connector-table-hosts'),
  program: await readFile(new URL('./table-values.json', import.meta.url), 'utf8')});
console.log('PACKED_CONNECTOR_TABLE', JSON.stringify(result));
