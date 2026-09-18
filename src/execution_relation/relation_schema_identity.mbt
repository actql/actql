///|
/// Independent bounds for the complete resolved Relation field-contract map.
/// These limits do not borrow capacity from row payload or logical value
/// identity generation.
pub(all) struct RelationSchemaIdentityLimits {
  max_fields : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum RelationSchemaIdentityIssue {
  InvalidLimits
  FieldLimit
  Encoding(@encode.EncodeFailure)
}

///|
/// Identity of the complete resolved field-contract map. It is distinct from
/// a row object contract, a logical Relation value and a physical codec.
struct RelationSchemaIdentity {
  cid : String
  bytes : Int
  nodes : Int
  fields : Int
}

///|
/// Hashes the exact checked schema without rebuilding contracts or accepting
/// an adapter-supplied JSON body. Schema iteration is already canonical UTF-16
/// reference order, including qualified references.
pub fn identify_relation_schema(
  schema : @schema.Schema,
  limits : RelationSchemaIdentityLimits,
) -> Result[RelationSchemaIdentity, RelationSchemaIdentityIssue] {
  if limits.max_fields < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let fields = @schema.field_count(schema)
  if fields > limits.max_fields {
    return Err(FieldLimit)
  }
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_object(writer)
    for index = 0; index < fields; index = index + 1 {
      let field = @schema.field_at(schema, index).unwrap()
      @encode.key(writer, @schema.reference_name(field.name))
      @contract.emit_checked(field.contract, writer)
    }
    @encode.end_object(writer)
    let (hash, bytes, nodes, _) = @encode.finish_hash_metrics(writer)
    Ok({ cid: "sha256:" + hash, bytes, nodes, fields, })
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
pub fn relation_schema_cid(value : RelationSchemaIdentity) -> String {
  value.cid
}

///|
pub fn relation_schema_usage(value : RelationSchemaIdentity) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.fields)
}
