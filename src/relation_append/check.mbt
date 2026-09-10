///|
fn preflight(
  b : Budget,
  s : @decode.Cursor,
  schema : @schema.Schema,
) -> Unit raise Stop {
  spend(b, s)
  let count = @schema.field_count(schema)
  spend(b, s, n=count)
  let work : Array[(@contract.Contract, Int)] = []
  for i in 0..<count {
    let f = @schema.field_at(schema, i).unwrap()
    charge(b, s, @schema.reference_name(f.name))
    work.push((f.contract, 1))
  }
  while work.pop() is Some((c, depth)) {
    spend(b, s)
    if depth > b.limits.max_depth {
      fail(s, BudgetExceeded)
    }
    match c.shape {
      @contract.Array(item, ..) => work.push((item, depth + 1))
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        spend(b, s, n=count)
        for i in 0..<count {
          let f = @contract.field_at(fields, i).unwrap()
          charge(b, s, f.name)
          work.push((f.contract, depth + 1))
        }
      }
      @contract.ResourceRef(resource_kind~) => charge(b, s, resource_kind)
      @contract.ArtifactRef(media_type=Some(media)) => charge(b, s, media)
      _ => ()
    }
  }
}

///|
priv enum PairWork {
  Visit(@contract.Contract, @contract.Contract, ContractSegment?)
  Leave
}

///|
// Count exact contract pairs while locating mismatches. Only the failing path
// is copied; deep successful walks do not retain quadratic path arrays.
fn join_field(
  b : Budget,
  s : @decode.Cursor,
  field : @schema.FieldName,
  left : @contract.Contract,
  right : @contract.Contract,
) -> @contract.Contract raise Stop {
  let work = [PairWork::Visit(left, right, None)]
  let path : Array[ContractSegment] = []
  let mut pairs = 0
  while work.pop() is Some(frame) {
    match frame {
      Leave => ignore(path.pop())
      Visit(a, c, segment) => {
        spend(b, s)
        pairs += 1
        if segment is Some(segment) {
          path.push(segment)
          work.push(Leave)
        }
        match (a.shape, c.shape) {
          (@contract.Array(x, ..), @contract.Array(y, ..)) =>
            work.push(Visit(x, y, Some(Item)))
          (@contract.Object(x), @contract.Object(y)) => {
            let count = @contract.field_count(x)
            if count != @contract.field_count(y) {
              fail(s, IncompatibleContracts(field, path.copy()))
            }
            spend(b, s, n=count)
            for i = count - 1; i >= 0; i = i - 1 {
              let a = @contract.field_at(x, i).unwrap()
              let c = @contract.field_at(y, i).unwrap()
              if a.name != c.name {
                fail(s, IncompatibleContracts(field, path.copy()))
              }
              work.push(Visit(a.contract, c.contract, Some(Field(a.name))))
            }
          }
          // Never call a recursive relation with a renewed whole-call budget.
          (@contract.Array(_, ..), _)
          | (@contract.Object(_), _)
          | (_, @contract.Array(_, ..))
          | (_, @contract.Object(_)) =>
            fail(s, IncompatibleContracts(field, path.copy()))
          _ => {
            let compatible = @contract.join_nullability(a, c, 1) catch {
              _ => fail(s, BudgetExceeded)
            }
            if compatible is None {
              fail(s, IncompatibleContracts(field, path.copy()))
            }
          }
        }
      }
    }
  }
  // Construction uses the same established recursive relation. Debit its
  // measured pair count before calling it, once for this field's full tree.
  spend(b, s, n=pairs)
  let joined = @contract.join_nullability(left, right, pairs) catch {
    _ => fail(s, BudgetExceeded)
  }
  match joined {
    Some(v) => v
    None => fail(s, IncompatibleContracts(field, []))
  }
}

///|
// Internal injective map key; never a public field name or identity preimage.
fn typed_key(name : @schema.FieldName) -> String {
  match name {
    @schema.Unqualified(n) => "u:" + n
    @schema.Qualified(Left, n) => "l:" + n
    @schema.Qualified(Right, n) => "r:" + n
  }
}

///|
fn check_impl(
  body : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  limits : Limits,
) -> CheckedAppend raise Stop {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    fail(body, InvalidLimits)
  }
  let b : Budget = {
    limits,
    work: limits.max_work,
    text: limits.max_text_bytes,
    nodes: limits.max_nodes,
  }
  preflight(b, body, left)
  preflight(b, body, right)
  spend(b, body)
  if b.nodes < 1 || limits.max_depth < 1 {
    fail(body, BudgetExceeded)
  }
  b.nodes -= 1
  let obj = match @decode.closed_object(body, ["with"]) {
    Ok(v) => v
    Err(_) => fail(body, InvalidBody)
  }
  let source = match @decode.required(obj, "with") {
    Ok(v) => v
    Err(_) => fail(body, InvalidBody)
  }
  spend(b, source)
  if b.nodes < 1 {
    fail(source, BudgetExceeded)
  }
  b.nodes -= 1
  charge(b, source, "with")
  let with_name = match @decode.text(source) {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
  charge(b, source, with_name)
  if with_name == "" || @canonical.normalize_nfc_lf(with_name) != Ok(with_name) {
    fail(source, InvalidName(with_name))
  }
  let (output, alignment) = align(b, source, left, right)
  {
    source: body,
    with_name,
    left,
    right,
    output,
    alignment,
    usage: {
      work: limits.max_work - b.work,
      text_bytes: limits.max_text_bytes - b.text,
      nodes: limits.max_nodes - b.nodes,
    },
  }
}

///|
fn align(
  b : Budget,
  source : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
) -> (@schema.Schema, Array[Alignment]) raise Stop {
  let count = @schema.field_count(left)
  let right_count = @schema.field_count(right)
  // Typed keys prevent a spelling match from discarding provenance.
  let right_fields : Map[String, Int] = Map([])
  spend(b, source, n=right_count)
  for i in 0..<right_count {
    right_fields[typed_key(@schema.field_at(right, i).unwrap().name)] = i
  }
  let fields : Array[(@schema.FieldName, @contract.Contract)] = []
  let alignment : Array[Alignment] = []
  spend(b, source, n=count)
  for i in 0..<count {
    let a = @schema.field_at(left, i).unwrap()
    let j = match right_fields.get(typed_key(a.name)) {
      Some(v) => v
      None => fail(source, MissingField(Right, a.name))
    }
    let c = @schema.field_at(right, j).unwrap()
    fields.push((a.name, join_field(b, source, a.name, a.contract, c.contract)))
    alignment.push({ field: a.name, left_index: i, right_index: j, })
    ignore(right_fields.remove(typed_key(a.name)))
  }
  if !right_fields.is_empty() {
    // Deterministic diagnostic order, independent of Map iteration.
    for i in 0..<right_count {
      let name = @schema.field_at(right, i).unwrap().name
      if right_fields.contains(typed_key(name)) {
        fail(source, MissingField(Left, name))
      }
    }
  }
  let bytes = b.text
  spend(b, source, n=fields.length())
  for (name, _) in fields {
    charge(b, source, @schema.reference_name(name))
  }
  let output = match
    @schema.from_fields(
      fields,
      max_fields=fields.length(),
      max_name_bytes=bytes,
    ) {
    Ok(v) => v
    Err(_) => fail(source, BudgetExceeded)
  }
  preflight(b, source, output)
  (output, alignment)
}

///|
struct AlignedSchemas {
  output : @schema.Schema
  fields : Array[Alignment]
  usage : Usage
}

///|
/// Shared recursive schema alignment for append and complete-row set operators.
/// This establishes no row equality, multiplicity, order or identity evidence.
pub fn align_schemas(
  source : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  limits : Limits,
) -> Result[AlignedSchemas, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      text: limits.max_text_bytes,
      nodes: limits.max_nodes,
    }
    preflight(b, source, left)
    preflight(b, source, right)
    let (output, fields) = align(b, source, left, right)
    Ok({
      output,
      fields,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: limits.max_text_bytes - b.text,
        nodes: 0,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn aligned_schema(value : AlignedSchemas) -> @schema.Schema {
  value.output
}

///|
pub fn aligned_fields(value : AlignedSchemas) -> Array[Alignment] {
  value.fields.copy()
}

///|
pub fn alignment_usage(value : AlignedSchemas) -> Usage {
  value.usage
}

///|
/// The caller resolves `with` to the right schema. No row execution or proof
/// propagation is performed; success always retains both input operands.
pub fn check(
  body : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  limits : Limits,
) -> Result[CheckedAppend, Issue] {
  Ok(check_impl(body, left, right, limits)) catch {
    Stop(issue) => Err(issue)
  }
}
