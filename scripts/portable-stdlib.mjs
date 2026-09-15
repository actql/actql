// Audited pinned runtime inventory, including implicit prelude/builtin edges.
// Package membership alone never licenses arbitrary FFI: emitted JS is separately
// checked and the physical seed is adapted through an exact declaration pin.
import {readFileSync, readdirSync, writeFileSync, mkdirSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {inspectCore, tokens} from './portable-core.mjs';

const groups = [
  ['In-memory collection/value operations; no environment authority granted.',
    ['array','buffer','hashmap','hashset','immut/sorted_map','lazy','list','option','ref','set','sorted_set','tuple']],
  ['Exact/in-memory arithmetic or representation conversion; generated target intrinsics are audited.',
    ['bigint','char','double','float','int','int16','int64','uint','uint16','uint64','v128','internal/strconv']],
  ['In-memory parsing/encoding; test-only imports are not production edges.',
    ['encoding/utf8','json','string','string/internal/regex_engine','string/internal/regex_engine/ast',
      'string/internal/regex_engine/symbol_map','string/internal/regex_parser',
      'internal/regex_engine/automata','internal/regex_engine/shared_types','internal/regex_engine/shared_types/rechar_set']],
  ['Implicit compiler/runtime dependency. Printing is not permitted in product Core; generated JS must contain no console/I/O. Physical hash entropy requires the explicit Host-seed adapter.',
    ['prelude','builtin','abort','debug','error','test']],
];
export const auditedPackages = Object.fromEntries(groups.flatMap(([reason,names]) => names.map(name => [name,reason])));
const hash = value => createHash('sha256').update(value).digest('hex');

// Only used after the entire manifest has matched its audited source digest.
// Tokenization avoids reading commented imports and quoted descriptions as edges.
export function auditedImports(source) {
  const ts = tokens(source), result = [];
  for (let i = 0; i < ts.length; i++) {
    if (ts[i].kind !== 'word' || ts[i].value !== 'import') continue;
    if (ts[++i]?.value !== '{') throw new Error('UnauditedStdlibImport');
    const paths = [];
    while (ts[++i] && ts[i].value !== '}') {
      if (ts[i].kind === 'string') paths.push(ts[i].value);
    }
    if (!ts[i]) throw new Error('UnauditedStdlibImport');
    if (ts[i+1]?.value === 'for') {
      if (!['test','wbtest'].includes(ts[i+2]?.value)) throw new Error('UnauditedStdlibScope');
      i += 2;
    } else result.push(...paths);
  }
  return result;
}

export function inspectStdlib(root, home, recorded, record = false) {
  if (!home) throw new Error('PinnedMoonHomeRequired');
  const pin = JSON.parse(readFileSync(join(root,'toolchain.json'),'utf8'));
  if (recorded && (recorded.version !== pin.version || recorded.core !== pin.core.sha256)) {
    throw new Error('UnauditedStdlibVersion');
  }
  const external = Object.keys(inspectCore(root).external).map(path => path.slice('moonbitlang/core/'.length));
  const pending = ['prelude','builtin',...external], entries = {};
  while (pending.length) {
    const name = pending.pop();
    if (Object.hasOwn(entries,name)) continue;
    if (!Object.hasOwn(auditedPackages,name)) throw new Error(`UnreviewedStdlibPackage: ${name}`);
    const directory = join(home,'lib/core',name);
    const files = readdirSync(directory,{withFileTypes:true})
      .filter(entry => entry.isFile() && !/_(?:wb)?test\.mbt$/.test(entry.name) &&
        entry.name !== 'pkg.generated.mbti' && !/\.md$/.test(entry.name))
      .map(entry => entry.name).sort();
    const digests = files.map(file => [file,hash(readFileSync(join(directory,file)))]);
    const digest = hash(JSON.stringify(digests));
    if (!record && recorded?.packages[name]?.digest !== digest) {
      throw new Error(`UnauditedStdlibSource: ${name}`);
    }
    const dependencies = auditedImports(readFileSync(join(directory,'moon.pkg'),'utf8'));
    for (const path of dependencies) {
      if (!path.startsWith('moonbitlang/core/')) throw new Error(`UnreviewedStdlibExternal: ${path}`);
      pending.push(path.slice('moonbitlang/core/'.length));
    }
    entries[name] = {digest, reason:auditedPackages[name], dependencies, files:files.length};
  }
  return {version:pin.version,core:pin.core.sha256,
    packages:Object.fromEntries(Object.entries(entries).sort(([a],[b]) => a.localeCompare(b)))};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../',import.meta.url));
  const path = join(root,'scripts/fixtures/portable-stdlib.json');
  const record = process.argv.includes('--record-reviewed-sources');
  const recorded = record ? undefined : JSON.parse(readFileSync(path,'utf8'));
  const result = inspectStdlib(root,process.env.MOON_HOME,recorded,record);
  if (record) {
    mkdirSync(join(root,'scripts/fixtures'),{recursive:true});
    writeFileSync(path,JSON.stringify(result,null,2)+'\n');
  }
  else if (JSON.stringify(recorded) !== JSON.stringify(result)) throw new Error('StdlibInventoryMismatch');
  console.log(JSON.stringify({version:result.version,packages:Object.keys(result.packages).length,
    note:'Pinned runtime inventory; generated-runtime portability checks remain mandatory.'}));
}
