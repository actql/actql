// Independent fixture oracle: rehash the retained complete Values preimages
// after the two authored query-text inputs change. No product compiler,
// canonicalizer, manifest generator or execution output is imported.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const canonical = value => {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') return `{${Object.keys(value)
    .sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
};
export const signatureRoleCid = body => `sha256:${sha(Buffer.from(canonical(body), 'utf8'))}`;
const reseal = (value, field, changes) => {
  const {[field]: previous, ...body} = value;
  assert.equal(signatureRoleCid(body), previous, `Invalid retained ${field}`);
  const next = {...body, ...changes};
  return {...next, [field]: signatureRoleCid(next)};
};

export function signatureRoleIdentityOracle({
  beforePath = 'scripts/fixtures/pre-sga-signature-role-values-identities.json',
  grammarPath = 'spec/grammar/actql-query-0.1.ebnf',
  rulesPath = 'docs/spec/query-text.md',
  sourceRevision = 'authored-sga-signature-roles',
} = {}) {
  const before = read(beforePath);
  const {grammar_manifest_cid: beforeCid, ...oldGrammar} = before.grammar;
  assert.equal(signatureRoleCid(oldGrammar), beforeCid);
  // The operation/Program/expression contracts and all Values dependencies are
  // unchanged in this frontend-only unit. Only the two source grammar inputs
  // are rehashed from authored bytes, before consulting any generated pin.
  const grammarBody = {...oldGrammar,
    query_text_grammar_sha256: sha(readFileSync(grammarPath)),
    query_text_rules_sha256: sha(readFileSync(rulesPath))};
  const grammar = {...grammarBody, grammar_manifest_cid: signatureRoleCid(grammarBody)};
  const old = before.run_preimages;
  const template = reseal(old.template, 'bound_invocation_template_cid', {
    grammar_manifest_cid: grammar.grammar_manifest_cid});
  const executable = reseal(old.executable, 'executable_plan_cid', {
    execution_material: {...old.executable.execution_material,
      grammar_manifest_cid: grammar.grammar_manifest_cid,
      invocation_template_cid: template.bound_invocation_template_cid}});
  const compiled = reseal(old.compiled, 'compiled_plan_cid', {
    executable_plan_cid: executable.executable_plan_cid});
  const run = reseal(old.run, 'run_definition_cid', {
    compiled_plan_cid: compiled.compiled_plan_cid,
    invocation_template_cid: template.bound_invocation_template_cid});
  return {...before, source_revision: sourceRevision, prepared: false,
    grammar, run_preimages: {template, executable, compiled, run}};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.deepEqual(process.argv.slice(2), ['--write']);
  const expected = signatureRoleIdentityOracle();
  writeFileSync('scripts/fixtures/submitted-sga-signature-role-values-identities.json',
    JSON.stringify(expected, null, 2) + '\n');
  console.log(JSON.stringify({grammar: expected.grammar.grammar_manifest_cid,
    template: expected.run_preimages.template.bound_invocation_template_cid,
    executable: expected.run_preimages.executable.executable_plan_cid,
    compiled: expected.run_preimages.compiled.compiled_plan_cid,
    run: expected.run_preimages.run.run_definition_cid}));
}
