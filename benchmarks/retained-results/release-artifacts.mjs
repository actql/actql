import {createHash} from 'node:crypto';
import {createReadStream} from 'node:fs';
import {join} from 'node:path';

// Generated release modules loaded by the two measured legs, including the
// parent/child process and retained-store bridges. Build outputs are ignored
// by Git, so a clean checkout does not establish their identity.
const modules = Object.freeze([
  'benchmark_obligations/benchmark_obligations.js',
  'connectors/duckdb/host_node/host_node.js',
  'connectors_builtin_node/connectors_builtin_node.js',
  'physical_strategy_example/physical_strategy_example.js',
  'physical_task_manifest_example/physical_task_manifest_example.js',
  'process_host_bridge/process_host_bridge.js',
  'retained_host_bridge/retained_host_bridge.js',
]);

// Read every byte on every invocation. A bounded 1 MiB stream reduces the
// per-chunk asynchronous overhead for the Native binary without caching an
// earlier identity or loading the entire binary into the parent heap.
export async function sha256File(path) {
  const hash = createHash('sha256');
  for await (const bytes of createReadStream(path, {highWaterMark: 1024 * 1024})) {
    hash.update(bytes);
  }
  return hash.digest('hex');
}

export async function releaseArtifactDigest(checkout) {
  const manifest = [];
  for (const name of modules) {
    const path = join(checkout, '_build/js/release/build', name);
    try {
      manifest.push([name, await sha256File(path)]);
    } catch (error) {
      throw new Error(`MissingOrUnreadableReleaseArtifact:${name}`, {cause: error});
    }
  }
  return createHash('sha256').update(JSON.stringify(manifest)).digest('hex');
}
