import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { canonicalJson, maxCapacityReportBytes, safePath } from './ci-artifacts.mjs';
const prefix = '.artifacts/relation-pipeline/';
export function pipelineEvidenceReader(directory, sourceRoot = fileURLToPath(new URL('../../', import.meta.url))) {
  const local = path => {
    assert(path.startsWith(prefix), 'Non-local evidence reference');
    return join(directory, safePath(path.slice(prefix.length)));
  };
  const read = path => readFileSync(path.startsWith(prefix) ? local(path) : join(sourceRoot,safePath(path)));
  // Native inspection tools need the SAME verified physical input that this
  // reader opens, including before relocated parts have been joined.
  Object.defineProperty(read,'resolveArtifact',{value:local});
  const report = path => canonicalJson(join(directory, safePath(path)),
    /^capacity\/parts\/L-C[01]\.json$/u.test(path) ? maxCapacityReportBytes : 32 * 1024 ** 2);
  return {local, read, report};
}
