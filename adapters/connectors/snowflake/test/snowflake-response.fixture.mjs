// Shared immutable response DATA only; no Core, Host, credential or Run setup.
export const decimal38 = '99999999999999999999999999999999999999';
export const readLimits = Object.freeze({maxBytes: 4096, maxNodes: 1000,
  maxDepth: 16, maxColumns: 16, maxNameUnits: 256, maxHandleUnits: 128,
  maxPartitions: 4, maxRows: 2, maxTotalRows: 2, maxRequests: 8,
  maxRequestBytes: 4096, maxContractPairs: 10, timeoutSeconds: 60,
  maxSecretBytes: 128, pollDelayMs: 0});

export function pending(handle = 'query-original') {
  return Buffer.from(JSON.stringify({code: '333334', statementHandle: handle,
    statementStatusUrl: 'https://foreign.invalid/do-not-follow'}));
}

export function resultBody({handle = 'query-original', parts = [2],
  rows = [['a1', decimal38, 'down'], ['a2', '0', null]], precision = 38} = {}) {
  return Buffer.from(JSON.stringify({statementHandle: handle, sqlState: '00000',
    resultSetMetaData: {format: 'jsonv2', numRows: parts.reduce((a, b) => a + b, 0),
      rowType: [{name: 'ACCOUNT_ID', type: 'TEXT', nullable: false},
        {name: 'ACTIVE_USERS', type: 'FIXED', precision, scale: 0, nullable: false},
        {name: 'TREND', type: 'TEXT', nullable: true}],
      partitionInfo: parts.map(rowCount => ({rowCount}))}, data: rows}));
}

export function metadataBody() {
  const names = ['TABLE_CATALOG', 'TABLE_SCHEMA', 'TABLE_NAME', 'COLUMN_NAME',
    'ORDINAL_POSITION', 'IS_NULLABLE', 'DATA_TYPE', 'NUMERIC_PRECISION',
    'NUMERIC_SCALE', 'CHARACTER_MAXIMUM_LENGTH'];
  return Buffer.from(JSON.stringify({statementHandle: 'metadata-original', sqlState: '00000',
    resultSetMetaData: {format: 'jsonv2', numRows: 3, rowType: names.map((name, i) => ({
      name, type: [4, 7, 8, 9].includes(i) ? 'FIXED' : 'TEXT', nullable: i >= 7,
      ...([4, 7, 8, 9].includes(i) ? {precision: 38, scale: 0} : {})})),
    partitionInfo: [{rowCount: 3}]}, data: [
      ['PRODUCT', 'USAGE', 'USAGE_30D', 'ACCOUNT_ID', '1', 'NO', 'TEXT', null, null, '256'],
      ['PRODUCT', 'USAGE', 'USAGE_30D', 'ACTIVE_USERS', '2', 'NO', 'NUMBER', '38', '0', null],
      ['PRODUCT', 'USAGE', 'USAGE_30D', 'TREND', '3', 'YES', 'TEXT', null, null, '256']]}));
}
