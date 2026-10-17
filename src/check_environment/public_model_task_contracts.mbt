///|
/// A checked public Task field map and its canonical schema. This is syntax
/// normalization, not an installed Task, Provider registration or authority.
struct PublicModelTaskContract {
  original : @decode.Cursor
  contract : @value_contract.Contract
  wire : String
  cid : String
  work : Int
  nodes : Int
  text : Int
}

///|
priv enum PublicTaskTypeFrame {
  Type(@decode.Cursor)
  Fields(@decode.Cursor, Int, Int)
  Members(@decode.Cursor, Int, Int, Bool, Bool)
  Copy(@decode.Cursor)
  CopyFields(@decode.Cursor, Int, Int)
  CopyItems(@decode.Cursor, Int, Int)
  End
}

///|
/// Only type positions expand shorthand. Enum strings and other values pass
/// unchanged to the existing ValueContract reader, including rejected fields.
/// Active-ancestry frames do not copy all pending siblings or a second type AST.
fn public_task_type_wire(
  root : @decode.Cursor,
  b : ModelTaskBudget,
) -> String raise ModelTaskStop {
  let count = match @decode.object_length(root) {
    Some(n) if n <= b.limits.bodies.max_members => n
    Some(_) => model_task_fail(TaskLimit, root)
    None => model_task_fail(InvalidObjectContract, root)
  }
  try {
    let writer = @encode.writer(
      b.limits.bodies.max_bytes,
      b.limits.bodies.max_nodes,
      b.limits.bodies.max_depth,
    )
    @encode.begin_object(writer)
    @encode.key(writer, "type")
    @encode.string_value(writer, "object")
    @encode.key(writer, "nullable")
    @encode.bool_value(writer, false)
    @encode.key(writer, "fields")
    @encode.begin_object(writer)
    let pending = [End, Fields(root, 0, count)]
    while pending.pop() is Some(frame) {
      model_task_charge(b, 1, root)
      match frame {
        End => @encode.end_object(writer)
        Fields(source, index, length) =>
          if index == length {
            @encode.end_object(writer)
          } else {
            let (key, child) = @decode.field_at(source, index).unwrap()
            model_task_charge(b, key.length(), child)
            @encode.key(writer, key)
            pending.push(Fields(source, index + 1, length))
            pending.push(Type(child))
          }
        Type(source) =>
          if @decode.text(source) is Ok(kind) {
            model_task_charge(b, kind.length(), source)
            @encode.begin_object(writer)
            @encode.key(writer, "type")
            @encode.string_value(writer, kind)
            @encode.key(writer, "nullable")
            @encode.bool_value(writer, false)
            @encode.end_object(writer)
          } else {
            let length = match @decode.object_length(source) {
              Some(n) => n
              None => model_task_fail(InvalidBody, source)
            }
            // Snapshot only the two structural discriminants. Do not allocate
            // a field map or detach an array of all caller-owned children.
            model_task_charge(b, length, source)
            let mut kind = None
            let mut nullable_present = false
            for i in 0..<length {
              let (key, child) = @decode.field_at(source, i).unwrap()
              model_task_charge(b, key.length(), child)
              if key == "type" {
                kind = @decode.text(child).to_option()
              } else if key == "nullable" {
                nullable_present = true
              }
            }
            @encode.begin_object(writer)
            if !nullable_present {
              @encode.key(writer, "nullable")
              @encode.bool_value(writer, false)
            }
            pending.push(
              Members(
                source,
                0,
                length,
                kind == Some("object"),
                kind == Some("array"),
              ),
            )
          }
        Members(source, index, length, object_type, array_type) =>
          if index == length {
            @encode.end_object(writer)
          } else {
            let (key, child) = @decode.field_at(source, index).unwrap()
            model_task_charge(b, key.length(), child)
            @encode.key(writer, key)
            pending.push(
              Members(source, index + 1, length, object_type, array_type),
            )
            if object_type &&
              key == "fields" &&
              @decode.object_length(child) is Some(n) {
              @encode.begin_object(writer)
              pending.push(Fields(child, 0, n))
            } else if array_type && key == "items" {
              pending.push(Type(child))
            } else {
              pending.push(Copy(child))
            }
          }
        Copy(source) =>
          if @decode.object_length(source) is Some(n) {
            @encode.begin_object(writer)
            pending.push(CopyFields(source, 0, n))
          } else if @decode.array_length(source) is Some(n) {
            @encode.begin_array(writer)
            pending.push(CopyItems(source, 0, n))
          } else {
            match @decode.view(source) {
              NullValue => @encode.null_value(writer)
              BoolValue(v) => @encode.bool_value(writer, v)
              NumberValue(v) => @encode.number_value(writer, v)
              TextValue(v) => {
                model_task_charge(b, v.length(), source)
                @encode.string_value(writer, v)
              }
              _ => model_task_fail(InvalidBody, source)
            }
          }
        CopyFields(source, index, length) =>
          if index == length {
            @encode.end_object(writer)
          } else {
            let (key, child) = @decode.field_at(source, index).unwrap()
            model_task_charge(b, key.length(), child)
            @encode.key(writer, key)
            pending.push(CopyFields(source, index + 1, length))
            pending.push(Copy(child))
          }
        CopyItems(source, index, length) =>
          if index == length {
            @encode.end_array(writer)
          } else {
            pending.push(CopyItems(source, index + 1, length))
            pending.push(Copy(@decode.element_at(source, index).unwrap()))
          }
      }
    }
    @encode.finish(writer)
  } catch {
    ModelTaskStop(e) => raise ModelTaskStop(e)
    _ => model_task_fail(BodyLimit, root)
  }
}

///|
/// Normalize one public input/output field map through the existing authored
/// ValueContract grammar. No default/meta/Parameter rules or implicit optional
/// fields are introduced. Bodies bound each intermediate and checked wire;
/// contracts bound the complete semantic tree, including duplicate enumerants.
pub fn read_public_model_task_contract(
  root : @decode.Cursor,
  limits : ModelTaskLimits,
) -> Result[PublicModelTaskContract, ModelTaskIssue] {
  if limits.max_work < 0 ||
    limits.bodies.max_bytes < 0 ||
    limits.bodies.max_nodes < 0 ||
    limits.bodies.max_depth < 0 ||
    limits.bodies.max_members < 0 ||
    limits.contracts.max_nodes < 0 ||
    limits.contracts.max_depth < 0 ||
    limits.contracts.max_text_bytes < 0 {
    return Err({ kind: InvalidLimits, source: Some(root), })
  }
  let b = { limits, work: 0, contract_nodes: 0, contract_text: 0, }
  try {
    let normalized = public_task_type_wire(root, b)
    // Reserve both complete bounded parser/admission traversals before either
    // builds its tree. These are computational bounds, not physical funding.
    for _ in 0..<2 {
      model_task_charge(b, limits.bodies.max_bytes, root)
      model_task_charge(b, limits.bodies.max_nodes, root)
    }
    let syntax = match
      @source.parse_json(normalized, {
        max_input_bytes: limits.bodies.max_bytes,
        max_nodes: limits.bodies.max_nodes,
        max_depth: limits.bodies.max_depth,
      }) {
      Ok(v) => v
      Err(_) => model_task_fail(BodyLimit, root)
    }
    let cursor = match
      @decode.admit(syntax, {
        max_nodes: limits.bodies.max_nodes,
        max_depth: limits.bodies.max_depth,
        max_string_bytes: limits.bodies.max_bytes,
        max_total_string_bytes: limits.bodies.max_bytes,
      }) {
      Ok(v) => v
      Err(_) => model_task_fail(BodyLimit, root)
    }
    model_task_charge(b, limits.bodies.max_bytes, root)
    model_task_charge(b, limits.bodies.max_nodes, root)
    let (contract, nodes, text) = match
      @value_contract.read_author_usage(cursor, limits.contracts) {
      Ok(v) => v
      Err(e) => model_task_fail(InvalidValueContract(e), root)
    }
    // Checked emission has its own bounded traversal/output; the normalized
    // author bytes are never used as the checked schema identity.
    model_task_charge(b, limits.bodies.max_bytes, root)
    model_task_charge(b, limits.bodies.max_nodes, root)
    let wire = @value_contract.stringify_checked(
      contract,
      limits.bodies.max_bytes,
      limits.bodies.max_nodes,
      limits.bodies.max_depth,
    ) catch {
      _ => model_task_fail(BodyLimit, root)
    }
    model_task_charge(b, limits.bodies.max_bytes, root)
    let cid = "sha256:" + @sha.hex(@utf8.encode(wire))
    Ok({ original: root, contract, wire, cid, work: b.work, nodes, text, })
  } catch {
    ModelTaskStop(e) => Err(e)
  }
}

///|
pub fn public_model_task_contract(
  value : PublicModelTaskContract,
) -> @value_contract.Contract {
  value.contract
}

///|
pub fn public_model_task_contract_schema(
  value : PublicModelTaskContract,
) -> (String, String) {
  (value.wire, value.cid)
}

///|
pub fn public_model_task_contract_usage(
  value : PublicModelTaskContract,
) -> (Int, Int, Int) {
  (value.work, value.nodes, value.text)
}

///|
pub fn public_model_task_contract_original(
  value : PublicModelTaskContract,
) -> @decode.Cursor {
  value.original
}
