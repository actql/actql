import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {machineCid} from './actql-spec-family.mjs';

export const schemaPath = 'spec/grammar/actql-regex-ast-0.1.schema.json';
export const contractPath = 'spec/contracts/actql-regex-ast.json';
export function regexAstContract(schema) {
  return {
    version: 'actql-regex-ast-contract/0.1',
    ast_version: 'actql-regex-ast/0.1',
    schema: {path: schemaPath, pointer: '', cid: machineCid(schema)},
    scope: 'Overrides inherited text-time regex AST representation and identity only; matching, grammar, flags and demand laws remain in force.',
    semantics: {
      scalar: 'integer_0_to_1114111_excluding_55296_to_57343_assignment_not_required',
      literal: 'closed_kind_literal_and_codepoint_one_exact_scalar',
      range: 'closed_kind_range_and_integer_start_end_inclusive_start_le_end_over_scalar_universe',
      escapes: {n: 10, r: 13, t: 9},
      normalization: 'source_text_obeys_NFC_LF_before_parsing_decoded_AST_scalars_are_not_text_normalized',
      ordering: 'retain_literal_sequence_class_item_branch_and_capture_occurrence_order',
      identity: 'ordinary_canonical_JSON_of_complete_AST_body_excluding_only_ast_cid',
      compatibility: 'old_string_literal_values_and_string_range_endpoints_rejected_no_silent_reinterpretation',
      backend: 'exact_expression_contract_and_local_AST_dependency_support_required_no_legacy_registry_relabeling',
      semantic_checks: 'range_order_capture_numbering_counts_and_quantifier_rules_require_separate_validation',
    },
  };
}
export function regexAstDependency(contract) {
  return {path:contractPath,pointer:'',cid:machineCid(contract)};
}
export function checkRegexAstContract(schema, contract, expression) {
  assert.deepEqual(schema.$defs.scalar,{description:'One Unicode scalar value, not a UTF-16 code unit or normalized text.',type:'integer',minimum:0,maximum:1114111,not:{minimum:55296,maximum:57343}});
  assert.deepEqual(schema.$defs.literal,{type:'object',additionalProperties:false,required:['kind','codepoint'],properties:{kind:{const:'literal'},codepoint:{$ref:'#/$defs/scalar'}}});
  assert.deepEqual(schema.$defs.range.properties.start,{$ref:'#/$defs/scalar'});
  assert.deepEqual(schema.$defs.range.properties.end,{$ref:'#/$defs/scalar'});
  assert.deepEqual(contract,regexAstContract(schema));
  assert.deepEqual(expression.regex_ast_contract,regexAstDependency(contract));
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const read = path => JSON.parse(readFileSync(path,'utf8'));
  const schema=read(schemaPath), expressionPath='spec/contracts/actql-expressions.json', expression=read(expressionPath);
  if (process.argv.includes('--write')) {
    const contract=regexAstContract(schema);
    writeFileSync(contractPath,JSON.stringify(contract,null,2)+'\n');
    expression.regex_ast_contract=regexAstDependency(contract);
    writeFileSync(expressionPath,JSON.stringify(expression,null,2)+'\n');
  }
  const contract=read(contractPath);
  checkRegexAstContract(schema,contract,expression);
  console.log('Regex scalar AST contract '+machineCid(contract));
}
