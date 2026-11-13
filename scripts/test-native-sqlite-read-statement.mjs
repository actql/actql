// Existing Native macOS job only. Missing preparation or any empty/failed
// group refuses; no private actor may build a replacement normal component.
import assert from 'node:assert/strict';
import {runFocusedTests} from './test-execution.mjs';
assert(process.env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION,
  'The same job exact-source Native component preparation is required');
process.exitCode = runFocusedTests('node', ['scripts/native-sqlite-read-statement.test.mjs'],
  {cwd: process.cwd(), timeout: 240000, maxBuffer: 4 * 1024 * 1024, expectedTests: 3});
