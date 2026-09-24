import {existsSync, readFileSync} from 'node:fs';
import {join} from 'node:path';

// The standard Node Host imports this package through host-common. Keep its
// generated runtime and declaration closure explicit in isolated assemblies.
export const requiredClientWireFiles = Object.freeze([
  'package.json', 'index.mjs', 'index.d.ts',
  'client-host.generated.js', 'client-host.generated.d.ts',
  'publication.generated.js', 'publication.generated.d.ts',
]);

export function assertClientWireDependency(root) {
  for (const name of requiredClientWireFiles) {
    const path = join(root, 'packages/client-wire', name);
    if (!existsSync(path) || readFileSync(path).byteLength === 0) {
      throw new Error(`MissingClientWireDependency:${name}`);
    }
  }
}
