///|
pub enum Reshape {
  Unpivot(
    columns~ : Array[KeyField],
    keep~ : Array[KeyField],
    name_column~ : String,
    value_column~ : String
  )
  JsonPick(column~ : @schema.FieldName, path~ : Array[String], output~ : String)
  Unnest(
    column~ : @schema.FieldName,
    element~ : String,
    index~ : String?,
    outer~ : Bool,
    max_items~ : Int64?
  )
}

///|
/// Detached retained syntax; max_items is the array bound, not a row proof.
pub fn reshape(value : CheckedOperation) -> Reshape? {
  value.reshape.map(r => {
    match r {
      Unpivot(columns~, keep~, name_column~, value_column~) =>
        Unpivot(
          columns=columns.copy(),
          keep=keep.copy(),
          name_column~,
          value_column~,
        )
      JsonPick(column~, path~, output~) =>
        JsonPick(column~, path=path.copy(), output~)
      Unnest(column~, element~, index~, outer~, max_items~) =>
        Unnest(column~, element~, index~, outer~, max_items~)
    }
  })
}

///|
pub fn json_pick_source(
  value : CheckedOperation,
) -> (@schema.FieldName, String)? {
  match value.reshape {
    Some(JsonPick(column~, output~, ..)) => Some((column, output))
    _ => None
  }
}

///|
pub fn unpivot_columns_count(value : CheckedOperation) -> Int {
  match value.reshape {
    Some(Unpivot(columns~, ..)) => columns.length()
    _ => 0
  }
}

///|
pub fn unpivot_column_at(value : CheckedOperation, index : Int) -> KeyField? {
  match value.reshape {
    Some(Unpivot(columns~, ..)) => columns.get(index)
    _ => None
  }
}

///|
pub fn unpivot_keep_count(value : CheckedOperation) -> Int {
  match value.reshape {
    Some(Unpivot(keep~, ..)) => keep.length()
    _ => 0
  }
}

///|
pub fn unpivot_keep_at(value : CheckedOperation, index : Int) -> KeyField? {
  match value.reshape {
    Some(Unpivot(keep~, ..)) => keep.get(index)
    _ => None
  }
}

///|
pub fn unpivot_outputs(value : CheckedOperation) -> (String, String)? {
  match value.reshape {
    Some(Unpivot(name_column~, value_column~, ..)) =>
      Some((name_column, value_column))
    _ => None
  }
}

///|
pub fn json_pick_path_count(value : CheckedOperation) -> Int {
  match value.reshape {
    Some(JsonPick(path~, ..)) => path.length()
    _ => 0
  }
}

///|
pub fn json_pick_path_at(value : CheckedOperation, index : Int) -> String? {
  match value.reshape {
    Some(JsonPick(path~, ..)) => path.get(index)
    _ => None
  }
}

///|
fn add_reshape_field(
  b : Budget,
  source : @decode.Cursor,
  name : String,
  contract : @contract.Contract,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
  added : Map[String, Bool],
  fields : Array[(@schema.FieldName, @contract.Contract)],
) -> Unit raise Stop {
  field_name(b, source, name)
  if visible.contains(name) {
    fail(source, InputCollision(name))
  }
  if added.contains(name) {
    fail(source, DuplicateOutput(name))
  }
  added[name] = true
  fields.push((@schema.Unqualified(name), contract))
}

///|
// Binary search reads opaque fields without copying a wide contract per segment.
fn pick_field(
  b : Budget,
  source : @decode.Cursor,
  fields : @contract.Fields,
  key : String,
) -> @contract.Contract raise Stop {
  let mut lo = 0
  let mut hi = @contract.field_count(fields)
  while lo < hi {
    spend(b, source)
    let mid = lo + (hi - lo) / 2
    let f = @contract.field_at(fields, mid).unwrap()
    let order = @canonical.compare_utf16(f.name, key)
    if order < 0 {
      lo = mid + 1
    } else if order > 0 {
      hi = mid
    } else {
      return f.contract
    }
  }
  fail(source, UnknownField(key))
}

///|
fn check_reshape(
  b : Budget,
  operation : Operation,
  body : @decode.Cursor,
  input : @schema.Schema,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
) -> (Reshape, Array[(@schema.FieldName, @contract.Contract)]) raise Stop {
  let keys = if operation is JsonPick {
    ["column", "path", "output"]
  } else {
    ["column", "as", "with_index", "outer"]
  }
  let obj = decoded(@decode.closed_object(body, keys), body)
  let column_source = decoded(@decode.required(obj, "column"), body)
  let column_text = decoded(@decode.text(column_source), column_source)
  let column = input_reference(b, column_source, column_text, visible)
  let contract = visible.get(column_text).unwrap().0
  let fields : Array[(@schema.FieldName, @contract.Contract)] = []
  let count = @schema.field_count(input)
  spend(b, body, count~)
  for i in 0..<count {
    let f = @schema.field_at(input, i).unwrap()
    fields.push((f.name, f.contract))
  }
  let added : Map[String, Bool] = Map([])
  let details = if operation is JsonPick {
    let path_source = decoded(@decode.required(obj, "path"), body)
    let segments = decoded(@decode.elements(path_source), path_source)
    if segments.is_empty() {
      fail(path_source, EmptyBody)
    }
    spend(b, path_source, count=segments.length())
    let path : Array[String] = []
    let mut selected = contract
    let mut nullable = contract.nullable
    for segment in segments {
      let key = decoded(@decode.text(segment), segment)
      // Keys are exact object keys, never a nested expression or JSONPath.
      selected = match selected.shape {
        @contract.Object(fields) => pick_field(b, segment, fields, key)
        @contract.Json => fail(segment, ShapeEvidenceRequired)
        _ => fail(segment, ExpectedObject)
      }
      nullable = nullable || selected.nullable
      path.push(key)
    }
    let output_source = decoded(@decode.required(obj, "output"), body)
    let output = decoded(@decode.text(output_source), output_source)
    add_reshape_field(
      b,
      output_source,
      output,
      @contract.with_nullability(selected, nullable),
      visible,
      added,
      fields,
    )
    Reshape::JsonPick(column~, path~, output~)
  } else {
    let (item, max_items) = match contract.shape {
      @contract.Array(item, max_items~) => (item, max_items)
      _ => fail(column_source, ExpectedArray)
    }
    let outer = match @decode.lookup(obj, "outer") {
      None => false
      Some(s) =>
        match @decode.view(s) {
          BoolValue(v) => v
          _ => fail(s, InvalidBody)
        }
    }
    let element_source = decoded(@decode.required(obj, "as"), body)
    let element = decoded(@decode.text(element_source), element_source)
    add_reshape_field(
      b,
      element_source,
      element,
      @contract.with_nullability(item, outer || item.nullable),
      visible,
      added,
      fields,
    )
    let index = match @decode.lookup(obj, "with_index") {
      None => None
      Some(s) => {
        let name = match @decode.view(s) {
          BoolValue(true) => element + "_index"
          TextValue(name) => name
          _ => fail(s, InvalidBody)
        }
        add_reshape_field(
          b,
          s,
          name,
          @contract.primitive(NumberType, nullable=outer),
          visible,
          added,
          fields,
        )
        Some(name)
      }
    }
    Reshape::Unnest(column~, element~, index~, outer~, max_items~)
  }
  (details, fields)
}
