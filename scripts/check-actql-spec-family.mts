import { readFileSync, writeFileSync } from 'node:fs';
import { loadSpecFamily, validateFamilyLinks } from './actql-spec-family.mjs';
const family=loadSpecFamily();
validateFamilyLinks(family);
const outputs = new Map([
  ['spec/actql-requirement-evidence.json', JSON.stringify(family.registry,null,2)+'\n'],
]);
for(const [path,content] of outputs) {
  if(process.argv.includes('--write')) writeFileSync(path,content);
  else if(readFileSync(path,'utf8')!==content) throw new Error(`generated family artifact is stale: ${path}`);
}
console.log(JSON.stringify({documents:family.documents.length,requirements:family.entries.length,
  document_imports:family.reference_audit.document_imports.length,
  machine_imports:family.reference_audit.machine_imports.length,informative_references:family.reference_audit.informative_references.length,conformance:false}));
