// Installed DuckDB physical representation for managed values. This digest
// identifies exact Parquet bytes/column meaning, not ActQL logical content.
import {createHash} from 'node:crypto';

const codecContract = 'actql-duckdb-managed-parquet/0.1\n' +
  'parquet:c0..cN=logical-columns;o=logical-row-ordinal;' +
  '__actql_occurrence=source-occurrence\n' +
  'supported=DOUBLE,VARCHAR;ordered-by-o;duplicates-preserved;' +
  'store-integrity-required';

export const managedParquetCodecContractCid =
  `sha256:${createHash('sha256').update(codecContract).digest('hex')}`;
