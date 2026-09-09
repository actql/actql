import { readFileSync, existsSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { normalizedParagraphs } from './actql-requirement-extraction.mjs';

export const fingerprint = entry => createHash('sha256').update(`${entry.text}\0${entry.keyword}\0${entry.keyword_index}`).digest('hex');
const canonical = value => value && typeof value === 'object'
  ? Array.isArray(value) ? '['+value.map(canonical).join(',')+']'
    : '{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}'
  : JSON.stringify(value);
export const machineCid = value => 'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
export const documentCid = source => 'sha256:'+createHash('sha256').update(source).digest('hex');

/** Explicit imports, never inferred from prose or a nearby hyperlink. */
export function validateNormativeImports(documents) {
  const imports = [];
  for (const d of documents) {
    const declared = d.normative_imports ?? [];
    const markers = [...d.source.matchAll(/<!-- normative-import: ([^\n]+) -->/gu)].map(m=>m[1]);
    if (new Set(markers).size !== markers.length) throw new Error(`duplicate normative import ${d.path}`);
    const expected = declared.map(r=>`${r.owner} ${r.version}`);
    if (JSON.stringify([...markers].sort()) !== JSON.stringify([...expected].sort())) throw new Error(`unregistered normative import ${d.path}`);
    if (JSON.stringify(declared.map(r=>r.owner).sort()) !== JSON.stringify(d.normative_dependencies.map(id=>documents.find(t=>t.document_id===id)?.spec_id).sort())) throw new Error(`normative import closure mismatch ${d.path}`);
    for (const ref of declared) {
      const target = documents.find(t=>t.spec_id===ref.owner);
      if (!target || !target.source.includes(`version: ${ref.version}\n`)) throw new Error(`normative import version mismatch ${d.path}`);
      if (ref.document_cid !== documentCid(target.source)) throw new Error(`normative document import CID mismatch ${d.path}`);
      imports.push({from:d.spec_id,...ref});
    }
  }
  return imports;
}
export function loadSpecFamily(manifestPath = 'spec/spec-family.json') {
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const documents = manifest.documents.map(d => ({ ...d, source: readFileSync(d.path, 'utf8'), registry: JSON.parse(readFileSync(d.evidence, 'utf8')) }));
  const ids = new Set(documents.map(d => d.document_id));
  if (ids.size !== documents.length || !ids.size) throw new Error('duplicate or empty specification owners');
  const visit = (id, stack = []) => {
    if (stack.includes(id)) throw new Error(`normative dependency cycle: ${[...stack,id].join(' -> ')}`);
    const d = documents.find(d => d.document_id === id);
    if (!d) throw new Error(`missing normative owner ${id}`);
    for (const dependency of d.normative_dependencies) visit(dependency,[...stack,id]);
  };
  documents.forEach(d => visit(d.document_id));
  const documentImports = validateNormativeImports(documents);
  const forbidden=[['language','execution'],['language','contracts'],['language','artifacts'],['language','run'],['language','conformance'],['discovery','collection'],['discovery','run'],['collection','run-graph'],['artifacts','run']];
  for(const [from,to] of forbidden)if(documents.find(d=>d.document_id===from)?.normative_dependencies.includes(to))throw new Error(`forbidden normative dependency ${from} -> ${to}`);
  const entries = [], requirements = [], seen = new Set();
  const machineOwners = new Set();
  for (const d of documents) {
    if (d.registry.document_id !== d.spec_id) throw new Error(`wrong evidence owner ${d.evidence}`);
    const dependencies=d.normative_dependencies.map(id=>documents.find(other=>other.document_id===id).spec_id);
    if(!d.source.includes(`spec_id: ${d.spec_id}\n`) || !d.source.includes(`normative_dependencies: [${dependencies.join(', ')}]`)) throw new Error(`descriptor/frontmatter mismatch ${d.path}`);
    for(const ref of d.machine_contracts ?? []) {
      const key=ref.path+'#'+ref.pointer;
      if(machineOwners.has(key))throw new Error(`machine contract has multiple owners: ${key}`);
      machineOwners.add(key);
      const object=JSON.parse(readFileSync(ref.path,'utf8'));
      if (ref.version !== undefined && ref.version !== object.version) throw new Error(`machine import version mismatch ${key}`);
      const value=ref.pointer.split('/').slice(1).reduce((v,k)=>v?.[k.replace(/~1/g,'/').replace(/~0/g,'~')],object);
      if(value===undefined || machineCid(value)!==ref.cid)throw new Error(`owned machine contract identity mismatch ${key}`);
      if(!d.source.includes(`${relative(dirname(d.path),ref.path)}#${ref.pointer} ${ref.cid}`))throw new Error(`missing explicit machine reference ${key}`);
    }
    const body = d.source.replace(/^---\n[\s\S]*?\n---\n/u,'');
    const extracted = normalizedParagraphs(body);
    const byHash = new Map(d.registry.requirements.map(r => [r.statement_sha256,r]));
    if(byHash.size!==d.registry.requirements.length || new Set(d.registry.requirements.map(r=>r.requirement_id)).size!==d.registry.requirements.length)throw new Error(`duplicate owner-local registry entry ${d.evidence}`);
    const marks=[...body.matchAll(/^<!-- requirement-block: ([^\n]+) -->$/gmu)];
    const marked=new Set();
    for(const [i,m] of marks.entries()) {
      const keys=m[1].split(' ').map(k=>d.spec_id+'/'+k);
      const actual=normalizedParagraphs(body.slice(m.index+m[0].length,marks[i+1]?.index ?? body.length))
        .map(e=>byHash.get(fingerprint(e))?.requirement_id);
      if(JSON.stringify(actual)!==JSON.stringify(keys))throw new Error(`requirement block mismatch ${d.spec_id}: ${m[1]}`);
      keys.forEach(k=>{if(marked.has(k))throw new Error(`duplicate requirement block ${k}`);marked.add(k);});
    }
    if(marked.size!==extracted.length)throw new Error(`unmarked normative requirement in ${d.path}`);
    const matched = new Set();
    for (const e of extracted) {
      const r = byHash.get(fingerprint(e));
      if (!r) throw new Error(`unmapped normative requirement in ${d.spec_id}#${e.section}: ${e.text}`);
      if (!r.requirement_id.startsWith(d.spec_id+'/') || seen.has(r.requirement_id)) throw new Error(`duplicate or foreign owner-local requirement ${r.requirement_id}`);
      if (r.source.anchor !== e.section) throw new Error(`wrong requirement source anchor ${r.requirement_id}`);
      seen.add(r.requirement_id); matched.add(r.statement_sha256);
      entries.push({...e,document_id:d.spec_id,document_path:d.path}); requirements.push(r);
    }
    if (matched.size !== byHash.size) throw new Error(`stale owner-local registry ${d.evidence}`);
  }
  for(const file of new Set(documents.flatMap(d=>(d.machine_contracts ?? []).map(r=>r.path)))) {
    const source=JSON.parse(readFileSync(file,'utf8'));
    for(const collection of ['schemas','artifact_schemas'])for(const key of Object.keys(source[collection]??{})) {
      if(!machineOwners.has(`${file}#/${collection}/${key}`))throw new Error(`unowned machine schema ${file}#/${collection}/${key}`);
    }
    if(source.laws && !machineOwners.has(file+'#/laws'))throw new Error(`unowned machine laws ${file}`);
  }
  const informativeReferences = documents.flatMap(d=>[...d.source.matchAll(/\]\(([^)]+)\)/gu)].flatMap(([,target])=> {
    const other=documents.find(t=>resolve(t.path)===resolve(dirname(d.path),target.split('#')[0]));
    return other && other.spec_id!==d.spec_id && !d.normative_dependencies.includes(other.document_id) ? [{from:d.spec_id,to:other.spec_id,target}] : [];
  }));
  return {manifest,documents,entries,reference_audit:{document_imports:documentImports,
    machine_imports:documents.flatMap(d=>(d.machine_contracts??[]).map(ref=>({owner:d.spec_id,...ref}))),
    informative_references:informativeReferences},registry:{version:'actql-requirement-evidence/0.1',generated_from:manifestPath,requirements}};
}

export function validateFamilyLinks(family) {
  const byPath = new Map(family.documents.map(d=>[resolve(d.path),d]));
  for (const d of family.documents) {
    const anchors=[...d.source.matchAll(/<a id="([^"]+)"><\/a>/gu)].map(m=>m[1]);
    if(new Set(anchors).size!==anchors.length) throw new Error(`duplicate anchor in ${d.path}`);
    if(/^#{1,6} (?:\d+\.|Appendix [A-Z]\.)|§\d/mu.test(d.source)) throw new Error(`global numbering in owner ${d.path}`);
    for(const [,target] of d.source.matchAll(/\]\(([^)]+)\)/gu)) {
      if(/^[a-z]+:/u.test(target)) continue;
      const [file,anchor]=target.split('#'), absolute=resolve(dirname(d.path),file||relative(dirname(d.path),d.path));
      if(!existsSync(absolute)) throw new Error(`broken file link ${d.path}: ${target}`);
      const other=byPath.get(absolute);
      if(other && anchor && !other.source.includes(`<a id="${anchor}"></a>`)) throw new Error(`broken anchor ${d.path}: ${target}`);
    }
  }
}
