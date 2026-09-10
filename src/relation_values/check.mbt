///|
fn parameter_name(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  for i in 0..<name.length() {
    let c = name[i].to_int()
    if !(c == 95 ||
      (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (i > 0 && c >= 48 && c <= 57)) {
      return false
    }
  }
  true
}

///|
fn literal(
  b : Budget,
  source : @decode.Cursor,
  target : @contract.Contract,
) -> Cell raise Stop {
  let used = scan(b, source)
  reserve(b, source, used)
  let checked = match
    @value.admit(target, source, {
      max_nodes: used.nodes,
      max_depth: b.limits.max_depth,
      max_text_bytes: used.text_bytes,
    }) {
    Ok(v) => v
    Err(@value.Decode(e)) =>
      raise Stop({
        kind: Decode(e.kind),
        source,
        path: e.path.copy(),
        span: e.span,
      })
    Err(@value.ValueIssue(kind, path~, span~)) =>
      raise Stop({ kind: Value(kind), source, path: path.copy(), span, })
  }
  Literal(checked, source~)
}

///|
fn cell(
  b : Budget,
  source : @decode.Cursor,
  target : @contract.Contract,
  params : Map[String, @contract.Contract],
  pending : Array[Obligation],
) -> Cell raise Stop {
  spend(b, source, 1)
  if @decode.view(source) is ObjectValue(obj) {
    let names = @decode.object_field_names(source).unwrap()
    if names.length() == 1 {
      if names[0] == "literal" {
        return literal(b, @decode.lookup(obj, "literal").unwrap(), target)
      }
      if names[0] == "$param" {
        let s = @decode.lookup(obj, "$param").unwrap()
        let name = decoded(@decode.text(s), s)
        if !parameter_name(name) {
          fail(s, InvalidParameterName(name))
        }
        let c = match params.get(name) {
          Some(c) => c
          None => fail(s, UnknownParameter(name))
        }
        let a = contract_walk(b, s, c, false)
        let t = contract_walk(b, s, target, false)
        spend(b, s, a + t)
        let compatible = @contract.assignable(c, target, a + t) catch {
          _ => fail(s, BudgetExceeded)
        }
        if !compatible {
          fail(s, IncompatibleParameter(name))
        }
        pending.push(BindCell(name))
        return Parameter(name, contract=c, source~)
      }
    }
  }
  literal(b, source, target)
}

///|
pub fn check(
  source : @decode.Cursor,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedValues, Issue] {
  try {
    if limits.max_rows < 0 ||
      limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_depth < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    ignore(scan(b, source))
    let obj = decoded(@decode.closed_object(source, ["schema", "rows"]), source)
    let schema_source = decoded(@decode.required(obj, "schema"), source)
    let declarations = decoded(
      @decode.open_object(schema_source),
      schema_source,
    )
    let names = @decode.object_field_names(schema_source).unwrap()
    if names.is_empty() {
      fail(schema_source, EmptySchema)
    }
    names.sort_by(@canonical.compare_utf16)
    spend(b, schema_source, names.length())
    let fields : Array[(String, @contract.Contract)] = []
    for name in names {
      let s = @decode.lookup(declarations, name).unwrap()
      let used = scan(b, s)
      reserve(b, s, used)
      let c = match
        @contract.read_author(s, {
          max_nodes: used.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: used.text_bytes,
        }) {
        Ok(c) => c
        Err(@contract.InvalidLimits) => fail(s, InvalidLimits)
        Err(@contract.Decode(e)) =>
          raise Stop({
            kind: Decode(e.kind),
            source: s,
            path: e.path.copy(),
            span: e.span,
          })
        Err(@contract.ContractIssue(kind, path~, span~)) =>
          raise Stop({
            kind: Contract(kind),
            source: s,
            path: path.copy(),
            span,
          })
      }
      ignore(contract_walk(b, s, c, true))
      fields.push((name, c))
    }
    let name_bytes = b.text
    for name in names {
      charge(b, schema_source, name)
    }
    let row_contract = match
      @contract.object_contract(
        fields,
        nullable=false,
        max_fields=fields.length(),
        max_name_bytes=name_bytes,
      ) {
      Ok(c) => c
      Err(_) => fail(schema_source, InvalidBody)
    }
    let schema = @schema.from_object(row_contract).unwrap()
    let params : Map[String, @contract.Contract] = Map([])
    if parameters is Some(p) {
      let count = @parameter.declaration_count(p)
      spend(b, source, count)
      for i in 0..<count {
        let d = @parameter.declaration_at(p, i).unwrap()
        charge(b, source, d.name)
        ignore(contract_walk(b, source, d.parameter_type.contract, false))
        params[d.name] = d.parameter_type.contract
      }
    }
    let rows_source = decoded(@decode.required(obj, "rows"), source)
    let inputs = decoded(@decode.elements(rows_source), rows_source)
    if inputs.length() > limits.max_rows {
      fail(rows_source, BudgetExceeded)
    }
    spend(b, rows_source, inputs.length())
    let rows : Array[Row] = []
    let pending : Array[Obligation] = [ResolvePublicationResources]
    for row_source in inputs {
      let row = decoded(@decode.closed_object(row_source, names), row_source)
      let cells : Array[Cell] = []
      spend(b, row_source, fields.length())
      for (name, target) in fields {
        let s = match @decode.lookup(row, name) {
          Some(s) => s
          None => decoded(@decode.required(row, name), row_source)
        }
        cells.push(cell(b, s, target, params, pending))
      }
      rows.push({ source: row_source, cells, })
    }
    Ok({
      source,
      schema,
      rows,
      pending,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}
