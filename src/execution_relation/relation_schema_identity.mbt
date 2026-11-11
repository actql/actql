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
  Closed
  NotFinished
}

///|
/// Identity of the complete resolved field-contract map. It is distinct from
/// a row object contract, a logical Relation value and a physical codec.
struct RelationSchemaIdentity {
  cid : String
  wire : String
  bytes : Int
  nodes : Int
  fields : Int
  field_names : Array[String]
}

///|
struct RelationSchemaIdentityPreparation {
  mut schema : @schema.Schema?
  mut hash_writer : @encode.Writer?
  mut wire_writer : @encode.Writer?
  max_frames : Int
  fields : Int
  mut pass : Int
  mut field : Int
  mut phase : Int
  mut key : @encode.OrderedKeyEmitCursor?
  mut contract : @contract.CheckedEmission?
  mut names : Array[String]
  mut identity : RelationSchemaIdentity?
  measurement_only : Bool
  mut measured : (Int, Int, Int)?
  mut closed : Bool
  mut name_headers : Int64
  mut name_utf16 : Int64
}

///|
/// Hashes the exact checked schema without rebuilding contracts or accepting
/// an adapter-supplied JSON body. Schema iteration is already canonical UTF-16
/// reference order, including qualified references.
pub fn start_relation_schema_identity(
  schema : @schema.Schema,
  limits : RelationSchemaIdentityLimits,
) -> Result[RelationSchemaIdentityPreparation, RelationSchemaIdentityIssue] {
  start_relation_schema_output(schema, limits, false)
}

///|
// The measuring interpretation uses this same field/contract continuation.
// It never allocates hash/text sinks or exposes an identity preparation.
fn start_relation_schema_output(
  schema : @schema.Schema,
  limits : RelationSchemaIdentityLimits,
  measurement_only : Bool,
) -> Result[RelationSchemaIdentityPreparation, RelationSchemaIdentityIssue] {
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
    let identity_writer = if measurement_only {
      @encode.measuring_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
    } else {
      @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
    }
    let wire_writer = if measurement_only {
      None
    } else {
      Some(@encode.writer(limits.max_bytes, limits.max_nodes, limits.max_depth))
    }
    // At most two pending child continuations per admitted value node, plus
    // fixed emission handles. No object-width-sized stack is constructed.
    let max_frames = Int64::min(
      2147483647L,
      2L * limits.max_nodes.to_int64() + 8L,
    ).to_int()
    Ok({
      schema: Some(schema),
      hash_writer: Some(identity_writer),
      wire_writer,
      max_frames,
      fields,
      pass: 0,
      field: 0,
      phase: 0,
      key: None,
      contract: None,
      names: [],
      identity: None,
      measurement_only,
      measured: None,
      closed: false,
      name_headers: 0L,
      name_utf16: 0L,
    })
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
pub fn cancel_relation_schema_identity(
  value : RelationSchemaIdentityPreparation,
) -> Bool {
  if value.closed {
    return false
  }
  value.closed = true
  if value.key is Some(cursor) {
    @encode.cancel_ordered_key(cursor)
  }
  if value.contract is Some(cursor) {
    @contract.cancel_checked_emission(cursor)
  }
  if value.hash_writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  if value.wire_writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  value.schema = None
  value.hash_writer = None
  value.wire_writer = None
  value.key = None
  value.contract = None
  value.names = []
  value.identity = None
  value.measured = None
  true
}

///|
/// Poll one field/contract transition or bounded Text fragment. Hash emission
/// precedes wire emission, preserving the original writer failure precedence.
pub fn advance_relation_schema_identity(
  value : RelationSchemaIdentityPreparation,
  quantum : Int,
) -> Result[(Bool, Int), RelationSchemaIdentityIssue] {
  if value.closed || quantum <= 0 {
    return Err(Closed)
  }
  if value.identity is Some(_) || value.measured is Some(_) {
    return Ok((true, 0))
  }
  try {
    let schema = value.schema.unwrap()
    let mut steps = 0
    while steps < quantum {
      steps += 1
      let writer = if value.pass == 0 {
        value.hash_writer.unwrap()
      } else {
        value.wire_writer.unwrap()
      }
      match value.phase {
        0 => {
          @encode.begin_ordered_object(writer)
          value.phase = 1
        }
        1 =>
          if value.field == value.fields {
            @encode.end_object(writer)
            if value.measurement_only {
              value.phase = 6
            } else if value.pass == 0 {
              value.pass = 1
              value.field = 0
              value.phase = 0
            } else {
              value.phase = 6
            }
          } else {
            let field = @schema.field_at(schema, value.field).unwrap()
            let name = @schema.reference_name_construction_extent(field.name)
            value.name_headers += name.scratch.record_headers
            value.name_utf16 += name.scratch_utf16_units
            value.key = Some(
              @encode.start_ordered_key(
                writer,
                @schema.field_reference_name_at(schema, value.field).unwrap(),
              ),
            )
            value.phase = 2
          }
        2 =>
          if @encode.advance_ordered_key(value.key.unwrap()) {
            value.key = None
            value.phase = 3
          }
        3 => {
          let field = @schema.field_at(schema, value.field).unwrap()
          if field.presence == @schema.Conditional {
            @encode.begin_ordered_object(writer)
            @encode.ordered_key(writer, "contract")
          }
          value.contract = Some(
            @contract.start_checked_emission(
              field.contract,
              writer,
              value.max_frames,
            ),
          )
          value.phase = 4
        }
        4 =>
          if @contract.advance_checked_emission(value.contract.unwrap()) {
            value.contract = None
            value.phase = 5
          }
        5 => {
          let field = @schema.field_at(schema, value.field).unwrap()
          if field.presence == @schema.Conditional {
            @encode.ordered_key(writer, "presence")
            @encode.string_value(writer, "conditional")
            @encode.end_object(writer)
          }
          value.field += 1
          value.phase = 1
        }
        6 =>
          // Identity mode owns one independent name per poll before its receipt.
          // Measurement mode completes without a name inventory or identity.
          if value.measurement_only {
            value.measured = Some(
              @encode.finish_measurement_usage(value.hash_writer.unwrap()),
            )
            return Ok((true, steps))
          } else if value.names.length() < value.fields {
            let field = @schema.field_at(schema, value.names.length()).unwrap()
            let name = @schema.reference_name_construction_extent(field.name)
            value.name_headers += name.scratch.record_headers
            value.name_utf16 += name.scratch_utf16_units
            value.names.push(
              @schema.field_reference_name_at(schema, value.names.length()).unwrap(),
            )
          } else {
            let wire = @encode.finish(value.wire_writer.unwrap())
            let (hash, bytes, nodes, _) = @encode.finish_hash_metrics(
              value.hash_writer.unwrap(),
            )
            value.identity = Some({
              cid: "sha256:" + hash,
              wire,
              bytes,
              nodes,
              fields: value.fields,
              field_names: value.names,
            })
            return Ok((true, steps))
          }
        _ => raise @encode.InvalidStructure
      }
    }
    Ok((false, steps))
  } catch {
    issue => {
      cancel_relation_schema_identity(value) |> ignore
      Err(Encoding(issue))
    }
  }
}

///|
pub fn finish_relation_schema_identity(
  value : RelationSchemaIdentityPreparation,
) -> Result[RelationSchemaIdentity, RelationSchemaIdentityIssue] {
  if value.closed {
    return Err(Closed)
  }
  guard value.identity is Some(identity) else { return Err(NotFinished) }
  value.closed = true
  value.schema = None
  value.hash_writer = None
  value.wire_writer = None
  value.identity = None
  value.names = []
  Ok(identity)
}

///|
/// Draining convenience form; resumable publication uses the same owner.
pub fn identify_relation_schema(
  schema : @schema.Schema,
  limits : RelationSchemaIdentityLimits,
) -> Result[RelationSchemaIdentity, RelationSchemaIdentityIssue] {
  let value = match start_relation_schema_identity(schema, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_relation_schema_identity(value, 64) {
      Ok((true, _)) => break
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  finish_relation_schema_identity(value)
}

///|
/// Exact complete field-map geometry through the original resumable codec.
/// Conditional presence wrappers, qualified/Unicode keys and nested contracts
/// retain their original encoding and limits. No wire, hash or identity is
/// constructed; this DATA does not reserve backing or admit another schema.
pub fn measure_relation_schema_identity(
  schema : @schema.Schema,
  limits : RelationSchemaIdentityLimits,
) -> Result[(Int, Int, Int), RelationSchemaIdentityIssue] {
  let value = match start_relation_schema_output(schema, limits, true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_relation_schema_identity(value, 64) {
      Err(issue) => return Err(issue)
      Ok((true, _)) => break
      Ok(_) => ()
    }
  }
  let measured = value.measured.unwrap()
  cancel_relation_schema_identity(value) |> ignore
  Ok(measured)
}

///|
pub fn relation_schema_cid(value : RelationSchemaIdentity) -> String {
  value.cid
}

///|
pub fn relation_schema_wire(value : RelationSchemaIdentity) -> String {
  value.wire
}

///|
pub fn relation_schema_field_names(
  value : RelationSchemaIdentity,
) -> Array[String] {
  value.field_names.copy()
}

///|
pub fn relation_schema_usage(value : RelationSchemaIdentity) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.fields)
}
