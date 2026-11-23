const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
const int64 = /^(?:0|-?[1-9][0-9]{0,18})$/u;
const minimumInt64 = -9223372036854775808n;
const maximumInt64 = 9223372036854775807n;
const unquotedDelimiters = new Set([0x2c, 0x0a, 0x0d]);

function fail(code, cause) {
  throw Object.assign(new Error(code, {cause}), {code});
}

function decodeField(bytes) {
  let text;
  try {text = decoder.decode(bytes);}
  catch (cause) {fail('InvalidLocalCsvEncoding', cause);}
  if (text.includes('\0')) fail('InvalidLocalCsvValue');
  return text;
}

// The caller supplies a member of the admitted Project connector JSON.
// Selection of a table never infers a path or a schema from a Program.
export function prepareLocalCsvTable(resource, table, limits) {
  const path = table?.path;
  if (typeof path !== 'string' || !path.isWellFormed() ||
    Buffer.byteLength(path) > limits.maxPathBytes) fail('InvalidLocalCsvPath');
  const components = path.split('/');
  if (components.length - 1 > limits.maxDepth || components.some(name =>
    name === '' || name === '.' || name === '..' || name.includes('\0'))) fail('InvalidLocalCsvPath');
  const columns = table.columns;
  if (columns === null || typeof columns !== 'object' || Array.isArray(columns)) fail('InvalidLocalCsvColumns');
  const names = Object.keys(columns);
  if (names.length === 0 || names.some(name => name === '' || !name.isWellFormed() || name.includes('\0') ||
    (columns[name] !== 'int64' && columns[name] !== 'string'))) fail('InvalidLocalCsvColumns');
  const key = Object.hasOwn(table, 'key') ? table.key : [];
  if (!Array.isArray(key) || (Object.hasOwn(table, 'key') && key.length === 0) ||
    new Set(key).size !== key.length || key.some(name => typeof name !== 'string' || !Object.hasOwn(columns, name))) {
    fail('InvalidLocalCsvKey');
  }
  // Initially one complete page. Both the raw file and its typed projection
  // must fit the existing Source page ceiling. Hold the raw response and its
  // native read block, decoded cells, key index, JSON text and RowRun wire at
  // the same time. Bound key index growth by the same row and input limits.
  const maxBytes = Math.min(limits.maxFileBytes, limits.maxPageBytes);
  const maxRows = Math.min(limits.maxFiles, limits.maxPageRows);
  const transport = Object.freeze({transferBytes: BigInt(maxBytes),
    executionBytes: 65536n + 32n * BigInt(maxBytes) + 8n * BigInt(limits.maxPageBytes) +
      256n * BigInt(maxRows) + 256n * BigInt(names.length)});
  return Object.freeze({resource, path, columnTypes: Object.freeze({...columns}), key: Object.freeze([...key]),
    maxBytes, maxRows, maxFieldBytes: maxBytes, transport});
}

// Keep only one record under construction. The input belongs to the original
// file reader, and the caller retains its backing until this cursor returns.
function* records(bytes, width, maxFieldBytes) {
  let offset = bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf ? 3 : 0;
  while (offset < bytes.length) {
    const fields = [];
    for (;;) {
      if (fields.length === width) fail('InvalidLocalCsvWidth');
      const quoted = bytes[offset] === 0x22;
      const start = quoted ? ++offset : offset;
      let end;
      if (quoted) {
        for (;;) {
          const quote = bytes.indexOf(0x22, offset);
          if (quote === -1) fail('InvalidLocalCsvQuote');
          if (quote - start > maxFieldBytes) fail('LocalCsvFieldLimit');
          offset = quote + 1;
          if (bytes[offset] !== 0x22) {end = quote; break;}
          offset++;
        }
      } else {
        while (offset < bytes.length && !unquotedDelimiters.has(bytes[offset])) {
          if (bytes[offset] === 0x22) fail('InvalidLocalCsvQuote');
          if (offset - start === maxFieldBytes) fail('LocalCsvFieldLimit');
          offset++;
        }
        end = offset;
      }
      const value = decodeField(bytes.subarray(start, end));
      fields.push(quoted ? value.replaceAll('""', '"') : value);
      if (offset === bytes.length) break;
      const separator = bytes[offset++];
      if (separator === 0x2c) continue;
      if (separator === 0x0d && bytes[offset] === 0x0a) offset++;
      else if (separator !== 0x0a) fail('InvalidLocalCsvSeparator');
      break;
    }
    if (fields.length !== width) fail('InvalidLocalCsvWidth');
    yield fields;
  }
}

function* localCsvRows(bytes, {columnTypes, key, maxBytes, maxRows, maxFieldBytes}) {
  if (!Buffer.isBuffer(bytes) || ![maxBytes,maxRows,maxFieldBytes].every(value =>
    Number.isSafeInteger(value) && value > 0)) fail('InvalidLocalCsvLimits');
  if (bytes.length > maxBytes) fail('LocalCsvBytesLimit');
  const names = Object.keys(columnTypes);
  const input = records(bytes, names.length, maxFieldBytes);
  const header = input.next().value;
  if (header === undefined || new Set(header).size !== names.length ||
    header.some(name => !Object.hasOwn(columnTypes, name))) fail('InvalidLocalCsvHeader');
  const keyRows = new Set();
  let rowCount = 0;
  for (const fields of input) {
    if (++rowCount > maxRows) fail('LocalCsvRowsLimit');
    for (let i = 0; i < header.length; i++) {
      if (columnTypes[header[i]] === 'string') continue;
      const value = fields[i];
      if (!int64.test(value)) fail('InvalidLocalCsvInt64');
      const number = BigInt(value);
      if (number < minimumInt64 || number > maximumInt64) fail('InvalidLocalCsvInt64');
    }
    const row = Object.fromEntries(header.map((name, i) => [name, fields[i]]));
    if (key.length) {
      const identity = JSON.stringify(key.map(name => row[name]));
      if (keyRows.has(identity)) fail('DuplicateLocalCsvKey');
      keyRows.add(identity);
    }
    yield row;
  }
}

export function encodeLocalCsvPage(bytes, table, maxPageBytes) {
  const parts = [];
  let size = 2;
  for (const row of localCsvRows(bytes, table)) {
    const wire = JSON.stringify(row);
    size += Buffer.byteLength(wire) + (parts.length === 0 ? 0 : 1);
    if (size > maxPageBytes) fail('LocalFilesPageBytesLimit');
    parts.push(wire);
  }
  if (size > maxPageBytes) fail('LocalFilesPageBytesLimit');
  return '[' + parts.join(',') + ']';
}
