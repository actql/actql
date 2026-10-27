import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {signatureRoleIdentityOracle,signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
import {currentValuesPreimages} from './sequence-current-preimages-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const pre='reviews/2026-10-12-frontend-sequence-predicate-ast/preimages/';
const sha=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
// Original e5dc source and its grammar-bound values remain separate fixed evidence.
export const retainedSequenceIdentityOracle=()=>signatureRoleIdentityOracle({
 beforePath:'scripts/fixtures/pre-sequence-values-identities.json',
 grammarPath:pre+'submitted-query-grammar.ebnf',rulesPath:pre+'submitted-query-rules.md',
 sourceRevision:'authored-sequence-predicate-ast'});
export function sequenceIdentityOracle() {
 const {grammar_manifest_cid:oldPin,...body}=read(pre+'pre-current-grammar-manifest.json');
 assert.equal(signatureRoleCid(body),oldPin);
 const expression=read('spec/contracts/actql-expressions.json');
 const language=readFileSync('docs/spec/language.md','utf8');
 const start=language.indexOf('<a id="expression-text"></a>');
 const end=language.indexOf('<a id="predicates"></a>',start);
 assert(start>=0&&end>start);
 const protocol=read('spec/contracts/actql-protocol-schemas.json');
 const updated={...body,
  source_grammar_cid:signatureRoleCid(protocol.artifact_schemas.executable_plan.properties.execution_material.properties.program),
  structural_text_grammar_sha256:sha('spec/grammar/actql-text-0.1.ebnf'),
  structural_text_rules_sha256:sha('docs/spec/structural-text.md'),
  expression_contract_cid:signatureRoleCid(expression),
  expression_text_grammar_sha256:sha(expression.grammar),
  expression_text_rules_sha256:createHash('sha256').update(language.slice(start,end)).digest('hex'),
  query_text_grammar_sha256:sha('spec/grammar/actql-query-0.1.ebnf'),query_text_rules_sha256:sha('docs/spec/query-text.md')};
 const grammar={...updated,grammar_manifest_cid:signatureRoleCid(updated)};
 return currentValuesPreimages(grammar,'authored-sequence-current-main-adoption');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
 assert.deepEqual(process.argv.slice(2),['--write']);
 const before=currentValuesPreimages(read(pre+'pre-current-grammar-manifest.json'),'d879fb93ae19a314c44f5fb8e1fea1461bc3d0d5');
 const expected=sequenceIdentityOracle();
 writeFileSync('scripts/fixtures/pre-current-sequence-values-identities.json',JSON.stringify(before,null,2)+'\n');
 writeFileSync('scripts/fixtures/current-sequence-values-identities.json',JSON.stringify(expected,null,2)+'\n');
 console.log(JSON.stringify({grammar:expected.grammar.grammar_manifest_cid,run:expected.run_preimages.run.run_definition_cid}));
}
