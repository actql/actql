// Source-boundary verification only. No package installation, SDK globals or
// native DuckDB peer is needed for the source-free Node observation fixture.
import {prepareSourceNodeClient} from '../adapters/host-node/fixtures/source-node-client.mjs';
await prepareSourceNodeClient({assemble: true, includeOtel: true, duckdb: false});
