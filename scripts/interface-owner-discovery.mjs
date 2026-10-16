// Discover owner reference sidecars wherever their original owner places them.
// Their syntax snapshots and anchors are checked by the shared coverage reader;
// this loader does not assign semantic roles from directories or file names.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, realpathSync} from 'node:fs';
import {basename, isAbsolute, relative, resolve} from 'node:path';
import {repositoryFiles} from './distribution-interface-roots.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';

export function interfaceOwnerDeclarations(root, files = repositoryFiles(root)) {
  root = realpathSync(root);
  return files.filter(path => /(?:^|-)interface-boundaries\.json$/u.test(basename(path)) && !isConnectorTestFixture(path))
    .sort().map(path => {
      const actual = realpathSync(resolve(root, path)), child = relative(root, actual);
      assert(!isAbsolute(child) && child !== '..' && !child.startsWith('../'), 'Interface declaration escapes repository');
      const bytes = readFileSync(actual), value = JSON.parse(bytes);
      const declarations = Array.isArray(value) ? value : value.declarations;
      assert(Array.isArray(declarations) && declarations.length, `Missing interface declarations: ${path}`);
      return {id: path, sha256: createHash('sha256').update(bytes).digest('hex'), declarations,
        qualification: Array.isArray(value) ? 'existing-owner-reference-index' : value.qualification};
    });
}
