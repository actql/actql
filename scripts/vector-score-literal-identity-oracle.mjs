// Independent identities reuse the existing complete Values oracle. Only
// authored source rules change; no product emitter supplies expected preimages.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {currentValuesPreimages} from './temporal-join-current-preimages-oracle.mjs';
const directory='reviews/2026-10-13-frontend-vector-score-literal/preimages/';
const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
const sha=v=>createHash('sha256').update(v).digest('hex');
const cid=v=>'sha256:'+sha(JSON.stringify(canonical(v)));
export function vectorScoreLiteralIdentityOracle({current=true,rulesPath}={}) {
 const {grammar_manifest_cid:old,...body}=JSON.parse(readFileSync(directory+'grammar.json','utf8'));
 assert.equal(cid(body),old);
 assert.equal(sha(readFileSync(directory+'query-rules.md')),body.query_text_rules_sha256);
 const next={...body,query_text_rules_sha256:sha(readFileSync(rulesPath??(current?'docs/spec/query-text.md':directory+'query-rules.md')))};
 return currentValuesPreimages({...next,grammar_manifest_cid:cid(next)},current?'authored-vector-score-literal':'9481599accca722e4a2747f6fa5b05af23045140');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
 assert.deepEqual(process.argv.slice(2),['--write']);
 for(const [name,current] of [['pre',false],['current',true]])writeFileSync(directory+name+'-values.json',JSON.stringify(vectorScoreLiteralIdentityOracle({current}),null,2)+'\n');
}
