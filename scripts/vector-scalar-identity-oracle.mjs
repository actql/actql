// Test-only preimages from retained authored grammar bytes and normative Values
// dependencies. No product compiler, serializer or issuer supplies expectations.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {currentValuesPreimages} from './temporal-join-current-preimages-oracle.mjs';
const directory='reviews/2026-10-13-frontend-vector-scalars/preimages/';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const canonical=value=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])])):value;
const cid=value=>'sha256:'+sha(JSON.stringify(canonical(value)));
export function vectorScalarIdentityOracle({current=true,rulesPath}={}) {
  const retained=JSON.parse(readFileSync(directory+'grammar.json','utf8'));
  const {grammar_manifest_cid:old,...body}=retained;
  assert.equal(cid(body),old);
  assert.equal(sha(readFileSync(directory+'query-rules.md')),body.query_text_rules_sha256);
  const next={...body,query_text_rules_sha256:sha(readFileSync(rulesPath??(current?'docs/spec/query-text.md':directory+'query-rules.md')))};
  return currentValuesPreimages({...next,grammar_manifest_cid:cid(next)},current?'authored-vector-scalar-source':'d879fb93ae19a314c44f5fb8e1fea1461bc3d0d5');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  assert.deepEqual(process.argv.slice(2),['--write']);
  for(const [name,current] of [['pre',false],['current',true]]) writeFileSync(directory+name+'-values.json',JSON.stringify(vectorScalarIdentityOracle({current}),null,2)+'\n');
}
