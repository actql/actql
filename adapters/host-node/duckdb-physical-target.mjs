// Physical DuckDB names must survive logical canonical JSON normalization.
// Keep the existing approval envelope: readable names are display only;
// exact UTF-8 hex participates in installation, connector and approval identity.
export function duckDBPhysicalTarget({database, schema, table}) {
  const exact = name => Buffer.from(name, 'utf8').toString('hex');
  return Object.freeze({version: 'actql-installed-duckdb-target/0.1',
    database, schema, table,
    utf8_hex: Object.freeze({database: exact(database),
      schema: exact(schema), table: exact(table)})});
}
