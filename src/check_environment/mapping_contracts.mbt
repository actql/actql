///|
pub(all) enum MappingShapeIssue {
  InvalidLimits
  MappingLimit
  WorkLimit
  InvalidMapping(Int)
  IdentityMismatch(Int)
  TargetSchemaMismatch(Int)
  InvalidTargetSchema(Int)
  DuplicateMapping(String)
} derive(Eq, Debug)

///|
pub struct MappingContractShape {
  item : Member
  mapping_ref : String
  target_ref : String
  cid : String
  target_schema : @row.Schema
  primary_identity : String
  writable_fields : Array[String]
  required_fields : Array[String]
}

///|
pub struct MappingContractShapes {
  environment : WireEnvironment
  entries : Array[MappingContractShape]
  by_ref : Map[String, Int]
  work : Int
}

///|
pub fn mapping_shape_count(value : MappingContractShapes) -> Int {
  value.entries.length()
}

///|
pub fn mapping_shape_at(
  value : MappingContractShapes,
  index : Int,
) -> MappingContractShape? {
  value.entries.get(index)
}

///|
pub fn mapping_shape_for(
  value : MappingContractShapes,
  reference : String,
) -> MappingContractShape? {
  match value.by_ref.get(reference) {
    Some(index) => Some(value.entries[index])
    None => None
  }
}

///|
pub fn mapping_shape_environment(
  value : MappingContractShapes,
) -> WireEnvironment {
  value.environment
}

///|
pub fn mapping_shape_work(value : MappingContractShapes) -> Int {
  value.work
}

///|
pub fn mapping_shape_member(value : MappingContractShape) -> Member {
  value.item
}

///|
pub fn mapping_shape_reference(value : MappingContractShape) -> String {
  value.mapping_ref
}

///|
pub fn mapping_shape_target(value : MappingContractShape) -> String {
  value.target_ref
}

///|
pub fn mapping_shape_cid(value : MappingContractShape) -> String {
  value.cid
}

///|
pub fn mapping_shape_target_schema(value : MappingContractShape) -> @row.Schema {
  value.target_schema
}

///|
pub fn mapping_shape_primary_identity(value : MappingContractShape) -> String {
  value.primary_identity
}

///|
pub fn mapping_shape_writable_fields(
  value : MappingContractShape,
) -> Array[String] {
  value.writable_fields.copy()
}

///|
pub fn mapping_shape_required_fields(
  value : MappingContractShape,
) -> Array[String] {
  value.required_fields.copy()
}

///|
priv suberror MappingShapeStop {
  MappingShapeStop(MappingShapeIssue)
}

///|
fn mapping_shape_required(
  object : @decode.ObjectView,
  key : String,
  index : Int,
) -> @decode.Cursor raise MappingShapeStop {
  match @decode.lookup(object, key) {
    Some(value) => value
    None => raise MappingShapeStop(InvalidMapping(index))
  }
}

///|
fn mapping_shape_text(
  object : @decode.ObjectView,
  key : String,
  index : Int,
) -> String raise MappingShapeStop {
  match @decode.text(mapping_shape_required(object, key, index)) {
    Ok(value) if !value.is_empty() => value
    _ => raise MappingShapeStop(InvalidMapping(index))
  }
}

///|
fn mapping_shape_cid_text(
  object : @decode.ObjectView,
  key : String,
  index : Int,
) -> String raise MappingShapeStop {
  let value = mapping_shape_text(object, key, index)
  if value.length() != 71 || !value.has_prefix("sha256:") {
    raise MappingShapeStop(InvalidMapping(index))
  }
  for at in 7..<value.length() {
    let digit = value[at].to_int()
    if !((digit >= 0x30 && digit <= 0x39) || (digit >= 0x61 && digit <= 0x66)) {
      raise MappingShapeStop(InvalidMapping(index))
    }
  }
  value
}

///|
fn mapping_shape_names(
  object : @decode.ObjectView,
  key : String,
  index : Int,
  schema : @row.Schema,
  max_work : Int,
  work : Ref[Int],
) -> Array[String] raise MappingShapeStop {
  let array = mapping_shape_required(object, key, index)
  let count = match @decode.array_length(array) {
    Some(value) => value
    None => raise MappingShapeStop(InvalidMapping(index))
  }
  if count > max_work - work.val {
    raise MappingShapeStop(WorkLimit)
  }
  work.val += count
  let names = []
  let seen : Map[String, Bool] = Map([])
  for at in 0..<count {
    let name = match @decode.text(@decode.element_at(array, at).unwrap()) {
      Ok(value) if !value.is_empty() => value
      _ => raise MappingShapeStop(InvalidMapping(index))
    }
    if seen.contains(name) || @row.lookup_reference(schema, name) is None {
      raise MappingShapeStop(InvalidMapping(index))
    }
    seen[name] = true
    names.push(name)
  }
  names
}

///|
fn mapping_shape_identity(
  root : @decode.Cursor,
  limits : Limits,
) -> String raise MappingShapeStop {
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_except(root, writer, Some("mapping_contract_cid"))
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    "sha256:" + digest
  } catch {
    _ => raise MappingShapeStop(WorkLimit)
  }
}

///|
/// Validates the closed resolved Mapping body, its self-CID, checked target
/// schema, primary key, and field inventories. Permission-rule selection,
/// conversion laws, row mapping values, current authority, and apply admission
/// are deliberately not conferred by this intermediate proof.
pub fn check_mapping_contract_shapes(
  environment : WireEnvironment,
  limits : Limits,
  max_work : Int,
) -> Result[MappingContractShapes, MappingShapeIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_members < 0 ||
    max_work < 0 {
    return Err(InvalidLimits)
  }
  let count = member_count(environment, MappingContracts)
  if count > limits.max_members {
    return Err(MappingLimit)
  }
  let work = Ref(0)
  let entries = []
  let by_ref : Map[String, Int] = Map([])
  try {
    for index in 0..<count {
      if work.val >= max_work {
        raise MappingShapeStop(WorkLimit)
      }
      work.val += 1
      let item = member_at(environment, MappingContracts, index).unwrap()
      let root = member_body(item)
      let object = match
        @decode.closed_object(root, [
          "schema", "mapping_ref", "version", "target_ref", "connector_manifest_cid",
          "resource_identity_cid", "target_schema_identity", "target_schema_reference",
          "target_schema", "primary_identity", "writable_fields", "required_fields",
          "conversions", "permission_rules", "required_permissions", "minimum_approval",
          "row_mapping", "mapping_contract_cid",
        ]) {
        Ok(value) => value
        Err(_) => raise MappingShapeStop(InvalidMapping(index))
      }
      if mapping_shape_text(object, "schema", index) !=
        "actql.mapping_contract/0.1" {
        raise MappingShapeStop(InvalidMapping(index))
      }
      let mapping_ref = mapping_shape_text(object, "mapping_ref", index)
      if !@contract_ref.valid_mapping_ref(mapping_ref) {
        raise MappingShapeStop(InvalidMapping(index))
      }
      let target_ref = mapping_shape_text(object, "target_ref", index)
      if !target_ref.has_prefix("connector://") {
        raise MappingShapeStop(InvalidMapping(index))
      }
      ignore(mapping_shape_text(object, "version", index))
      ignore(mapping_shape_cid_text(object, "connector_manifest_cid", index))
      ignore(mapping_shape_cid_text(object, "resource_identity_cid", index))
      let cid = mapping_shape_cid_text(object, "mapping_contract_cid", index)
      if cid != mapping_shape_identity(root, limits) {
        raise MappingShapeStop(IdentityMismatch(index))
      }
      let target = mapping_shape_required(object, "target_schema", index)
      let target_cid = mapping_shape_cid_text(
        object, "target_schema_identity", index,
      )
      let expected_target = hash(target, limits, false).0 catch {
          _ => raise MappingShapeStop(WorkLimit)
        }
      match @decode.lookup(object, "target_schema_reference") {
        None =>
          if target_cid != expected_target {
            raise MappingShapeStop(TargetSchemaMismatch(index))
          }
        Some(reference) => {
          let external = match
            @decode.closed_object(reference, ["id", "version", "cid"]) {
            Ok(value) => value
            Err(_) => raise MappingShapeStop(InvalidMapping(index))
          }
          ignore(mapping_shape_text(external, "id", index))
          ignore(mapping_shape_text(external, "version", index))
          if target_cid != mapping_shape_cid_text(external, "cid", index) {
            raise MappingShapeStop(TargetSchemaMismatch(index))
          }
        }
      }
      let contract = match
        @value_contract.read_checked(target, {
          max_nodes: limits.max_nodes,
          max_depth: limits.max_depth,
          max_text_bytes: limits.max_bytes,
        }) {
        Ok(value) => value
        Err(_) => raise MappingShapeStop(InvalidTargetSchema(index))
      }
      let schema = match @row.from_object(contract) {
        Ok(value) => value
        Err(_) => raise MappingShapeStop(InvalidTargetSchema(index))
      }
      let primary_identity = mapping_shape_text(
        object, "primary_identity", index,
      )
      let primary = match @row.lookup_reference(schema, primary_identity) {
        Some(value) => value
        None => raise MappingShapeStop(InvalidTargetSchema(index))
      }
      let primary_contract = @row.field_contract(primary)
      let schema_object = @decode.open_object(target).unwrap()
      let fields = match @decode.lookup(schema_object, "fields") {
        Some(value) =>
          match @decode.open_object(value) {
            Ok(value) => value
            Err(_) => raise MappingShapeStop(InvalidTargetSchema(index))
          }
        None => raise MappingShapeStop(InvalidTargetSchema(index))
      }
      let primary_wire = match @decode.lookup(fields, primary_identity) {
        Some(value) => @decode.open_object(value).unwrap()
        None => raise MappingShapeStop(InvalidTargetSchema(index))
      }
      let primary_type = mapping_shape_text(primary_wire, "type", index)
      if @decode.lookup(primary_wire, "nullable") is None ||
        @decode.boolean(@decode.lookup(primary_wire, "nullable").unwrap()) !=
        Ok(false) ||
        !["string", "number", "boolean", "date", "timestamp", "decimal"].contains(
          primary_type,
        ) ||
        !@value_contract.key_comparable(primary_contract, primary_contract) {
        raise MappingShapeStop(InvalidTargetSchema(index))
      }
      let writable = mapping_shape_names(
        object, "writable_fields", index, schema, max_work, work,
      )
      let required = mapping_shape_names(
        object, "required_fields", index, schema, max_work, work,
      )
      let writable_index : Map[String, Bool] = Map([])
      for name in writable {
        writable_index[name] = true
      }
      for name in required {
        if !writable_index.contains(name) {
          raise MappingShapeStop(InvalidMapping(index))
        }
      }
      for key in ["conversions", "permission_rules", "required_permissions"] {
        if @decode.array_length(mapping_shape_required(object, key, index))
          is None {
          raise MappingShapeStop(InvalidMapping(index))
        }
      }
      if @decode.object_length(
          mapping_shape_required(object, "row_mapping", index),
        )
        is None {
        raise MappingShapeStop(InvalidMapping(index))
      }
      let minimum = mapping_shape_text(object, "minimum_approval", index)
      if minimum != "none" && minimum != "required" {
        raise MappingShapeStop(InvalidMapping(index))
      }
      if by_ref.contains(mapping_ref) {
        raise MappingShapeStop(DuplicateMapping(mapping_ref))
      }
      by_ref[mapping_ref] = entries.length()
      entries.push({
        item,
        mapping_ref,
        target_ref,
        cid,
        target_schema: schema,
        primary_identity,
        writable_fields: writable,
        required_fields: required,
      })
    }
    Ok({ environment, entries, by_ref, work: work.val, })
  } catch {
    MappingShapeStop(issue) => Err(issue)
  }
}
