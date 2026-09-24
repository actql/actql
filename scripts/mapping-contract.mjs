const cid = {type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
const name = {type:'string',minLength:1};
const names = {type:'array',uniqueItems:true,items:name};

const valueSource = {
  oneOf:[
    {type:'object',additionalProperties:false,required:['field','null_behavior'],
      properties:{field:name,null_behavior:{enum:['reject','write_null','omit']}}},
    {type:'object',additionalProperties:false,required:['literal','null_behavior'],
      properties:{literal:{},null_behavior:{enum:['reject','write_null','omit']}}},
  ],
};

export function mappingContractBody() {
  return {
    schema:{
      type:'object',additionalProperties:false,
      required:[
        'schema','mapping_ref','version','target_ref',
        'connector_manifest_cid','resource_identity_cid',
        'target_schema_identity','target_schema','primary_identity',
        'writable_fields','required_fields','conversions',
        'permission_rules','required_permissions','minimum_approval',
        'row_mapping','mapping_contract_cid',
      ],
      properties:{
        schema:{const:'actql.mapping_contract/0.1'},
        mapping_ref:{type:'string',pattern:'^mapping:[A-Za-z0-9][A-Za-z0-9._/-]*\\.v[0-9]+$'},
        version:name,
        target_ref:{type:'string',pattern:'^connector://'},
        connector_manifest_cid:cid,
        resource_identity_cid:cid,
        target_schema_identity:cid,
        target_schema_reference:{type:'object',additionalProperties:false,
          required:['id','version','cid'],
          properties:{id:name,version:name,cid}},
        target_schema:{type:'object'},
        primary_identity:name,
        writable_fields:names,
        required_fields:names,
        conversions:{type:'array',items:{
          type:'object',additionalProperties:false,
          required:['target_field','source_contract_cid','conversion_law_cid'],
          properties:{target_field:name,source_contract_cid:cid,conversion_law_cid:cid},
        }},
        permission_rules:{type:'array',minItems:1,items:{
          type:'object',additionalProperties:false,
          required:['effect_kind','selector_class','write_fields','permissions'],
          properties:{
            effect_kind:{enum:['create','update','upsert','delete','store']},
            selector_class:{enum:['none','id','match','ids','external_id','where','key']},
            write_fields:names,
            permissions:{type:'array',minItems:1,uniqueItems:true,items:name},
          },
        }},
        required_permissions:names,
        minimum_approval:{enum:['none','required']},
        row_mapping:{type:'object',additionalProperties:valueSource},
        mapping_contract_cid:cid,
      },
    },
    semantics:{
      preimage:'entire_canonical_body_except_mapping_contract_cid',
      target_schema_identity:'canonical_cid_of_complete_target_schema_or_exact_external_schema_reference',
      permission_selection:'exactly_one_nonempty_rule_for_effect_kind_selector_class_and_exact_write_fields',
      row_mapping:'explicit_target_field_sources_no_implicit_same_name_copy',
      authority:'static_contract_not_current_resource_permission_or_apply_permit',
    },
  };
}
