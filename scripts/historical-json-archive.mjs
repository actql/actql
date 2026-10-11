import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {archiveDirectory, boundedEncoding, decodeSnapshot, format, packSnapshots, readArchive} from './historical-json.mjs';

const validPath = path => /^(?:portability\/corpus\/historical|scripts\/fixtures)\/pre-[a-z0-9-]+\.json$/.test(path);
export function checkArchive(archive) {
  if (archive.manifest?.format !== format) throw new Error('Unknown archive format');
  for (const [digest, node] of Object.entries(archive.objects)) {
    if (!/^[0-9a-f]{64}$/.test(digest) || createHash('sha256').update(boundedEncoding(node)).digest('hex') !== digest) throw new Error('Object digest mismatch');
  }
  const paths = Object.keys(archive.manifest.snapshots);
  if (paths.length === 0) throw new Error('Empty archive');
  for (const path of paths) {
    if (!validPath(path)) throw new Error(`Invalid snapshot path: ${path}`);
    decodeSnapshot(archive, path);
  }
  return paths.length;
}

export function importSnapshots(previous, inputs) {
  if (previous) checkArchive(previous);
  for (const path of Object.keys(inputs)) {
    if (!validPath(path)) throw new Error(`Invalid snapshot path: ${path}`);
    if (previous && Object.hasOwn(previous.manifest.snapshots, path)) throw new Error(`Already archived: ${path}`);
  }
  const next = packSnapshots(inputs);
  if (previous) {
    Object.assign(next.objects, previous.objects);
    Object.assign(next.manifest.snapshots, previous.manifest.snapshots);
  }
  next.objects = Object.fromEntries(Object.entries(next.objects).sort());
  next.manifest.snapshots = Object.fromEntries(Object.entries(next.manifest.snapshots).sort());
  checkArchive(next);
  return next;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [command = 'check', ...args] = process.argv.slice(2);
  if (command === 'check') {
    if (args.length) throw new Error('Usage: historical-json-archive.mjs check');
    console.log(`Verified ${checkArchive(readArchive())} historical snapshots (raw bytes and canonical digests).`);
  } else if (command === 'import') {
    const initial = args[0] === '--initial';
    if (initial) args.shift();
    if (args.length === 0) throw new Error('Supply explicit original snapshot paths');
    if (new Set(args).size !== args.length) throw new Error('Duplicate snapshot path');
    const previous = initial ? null : readArchive();
    // This command retains original inputs. Remove them only after independent review.
    const inputs = Object.fromEntries(args.map(path => {
      if (!validPath(path)) throw new Error(`Invalid snapshot path: ${path}`);
      return [path, readFileSync(path, 'utf8')];
    }));
    const archive = importSnapshots(previous, inputs);
    const directory = resolve(archiveDirectory);
    if (initial) mkdirSync(directory); // Refuse to overwrite an existing archive.
    writeFileSync(resolve(directory, 'objects.json'), `${JSON.stringify(archive.objects)}\n`);
    const receipts = Object.fromEntries(Object.entries(archive.manifest.snapshots).map(([path, {root, ...receipt}]) => [path, receipt]));
    writeFileSync(resolve(directory, 'receipts.json'), `${JSON.stringify(receipts, null, 2)}\n`);
    writeFileSync(resolve(directory, 'manifest.json'), `${JSON.stringify(archive.manifest)}\n`);
    console.log(`Verified and stored ${Object.keys(archive.manifest.snapshots).length} snapshots; original inputs retained.`);
  } else if (command === 'export') {
    if (args.length !== 1) throw new Error('Supply an empty export directory');
    const archive = readArchive();
    checkArchive(archive);
    const target = resolve(args[0]);
    mkdirSync(target); // Never overwrite a checkout or existing export.
    for (const path of Object.keys(archive.manifest.snapshots)) {
      const file = resolve(target, path);
      mkdirSync(dirname(file), {recursive: true});
      writeFileSync(file, `${JSON.stringify(decodeSnapshot(archive, path), null, 2)}\n`, {flag: 'wx'});
    }
    console.log(`Exported original bytes to ${target}`);
  } else throw new Error(`Unknown command: ${command}`);
}
