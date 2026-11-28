// Declaration-only compatibility correction for the pinned MIT-licensed XYFlow system package.
import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {lstatSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const installation = 'node_modules/@xyflow/system';
const version = '0.0.83';
const integrity = 'sha512-a//eDjez3WZF47aaPTfVUDD0OINOq+WVwBZCRTqG+m0a5euX8EwlJ4jMY1Wxz0Ocj4xOeekJ70V22Pq0ll8RJw==';
const originalSha = '996f688cb1fa9ec6d13ba2b871558ce48d426f0122eadbc2595c57d764951e4c';
const correctedSha = 'a4d94c2f9ccb4f4928a638ef13990dfcc7cb24f6ce2158fd0765fe5451364644';
const declarations = ['dist/esm/types/nodes.d.ts', 'dist/umd/types/nodes.d.ts'];
const digest = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

function readRegular(path: string) {
  const stat = lstatSync(path);
  assert(stat.isFile() && realpathSync(path) === path, `Expected an original regular file: ${path}`);
  return {path, mode: stat.mode, bytes: readFileSync(path)};
}

export function prepareExplorerXYFlowTypes(repository: string): void {
  const root = realpathSync(repository);
  const lock = JSON.parse(readRegular(join(root, 'package-lock.json')).bytes.toString('utf8')) as {
    packages?: Record<string, {version?: unknown; integrity?: unknown}>;
  };
  const locked = lock.packages?.[installation];
  assert(locked?.version === version && locked.integrity === integrity, 'Unexpected XYFlow system dependency lock');
  const installed = join(root, installation);
  const manifest = JSON.parse(readRegular(join(installed, 'package.json')).bytes.toString('utf8')) as {
    name?: unknown; version?: unknown; license?: unknown;
  };
  assert(manifest.name === '@xyflow/system' && manifest.version === version && manifest.license === 'MIT',
    'Unexpected installed XYFlow system package');

  // Admit both original members first. A generic Omit does not preserve the
  // base optional-property proof under exactOptionalPropertyTypes. Intersect
  // with the same base Omit to supply it without widening NodeBase fields.
  const updates = declarations.flatMap(member => {
    const {path, mode, bytes} = readRegular(join(installed, member));
    const sha = digest(bytes);
    if (sha === correctedSha) return [];
    assert.equal(sha, originalSha, `Unexpected XYFlow declaration bytes: ${member}`);
    const next = Buffer.from(bytes.toString('utf8').replace(
      "= Omit<NodeType, 'measured'> & {",
      "= Omit<NodeType, 'measured'> & Omit<NodeBase, 'measured'> & {",
    ));
    assert.equal(digest(next), correctedSha, `Unexpected XYFlow declaration correction: ${member}`);
    return [{path, mode, next}];
  });
  for (const {path, mode, next} of updates) {
    const temporary = `${path}.${randomUUID()}.tmp`;
    writeFileSync(temporary, next, {flag: 'wx', mode: mode & 0o777});
    try {
      renameSync(temporary, path);
    } finally {
      rmSync(temporary, {force: true});
    }
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  prepareExplorerXYFlowTypes(fileURLToPath(new URL('../', import.meta.url)));
}
