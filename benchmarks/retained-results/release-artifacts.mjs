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
  'process_host_bridge/process_host_bridge.js',
  'retained_host_bridge/retained_host_bridge.js',
]);

export async function releaseArtifactDigest(checkout) {
  const manifest = [];
  for (const name of modules) {
    const hash = createHash('sha256');
    const path = join(checkout, '_build/js/release/build', name);
    try {
      for await (const bytes of createReadStream(path)) hash.update(bytes);
    } catch (error) {
      throw new Error(`MissingOrUnreadableReleaseArtifact:${name}`, {cause: error});
    }
    manifest.push([name, hash.digest('hex')]);
  }
  return createHash('sha256').update(JSON.stringify(manifest)).digest('hex');
}
