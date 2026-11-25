import assert from 'node:assert/strict';

type ValueContract = {$defs: {value_contract: {oneOf: {properties?: {type?: {const?: string}}}[]}}};
type Protocol = {schemas: Record<'author_value_contract' | 'canonical_value_contract', ValueContract>};

export function byteValuesBody(protocol: Protocol) {
  const grammar={type:'object',required:['type','nullable'],additionalProperties:false,
    properties:{type:{const:'bytes'},nullable:{type:'boolean'}}};
  for(const name of ['author_value_contract','canonical_value_contract'] as const){
    const branches=protocol.schemas[name].$defs.value_contract.oneOf
      .filter(value=>value.properties?.type?.const==='bytes');
    assert.deepEqual(branches,[grammar],'closed distinct BYTES grammar: '+name);
  }
  return {
    grammar,
    wire:{type:'string',
      pattern:'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/][AQgw]==|[A-Za-z0-9+/]{2}[AEIMQUYcgkosw048]=)?(?![\\s\\S])'},
    domain:'exact_octets_including_empty_nullable_governed_separately',
    identity:'same_octets_and_distinct_typed_bytes_domain',
    admission:'standard_alphabet_final_padding_zero_unused_bits_encoded_extent_within_existing_value_budget',
    assignment:'same_leaf_and_existing_nullability_recursive_structure_no_implicit_conversion',
  };
}
