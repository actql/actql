///|
// Source admission has already normalized and owned this JSON-model tree.
fn source_preflight(b : Budget, root : @decode.Cursor) -> Unit raise Stop {
  let work = [(root, 0)]
  while work.pop() is Some((source, depth)) {
    spend(b, source, 1)
    if b.nodes == 0 {
      fail(source, BudgetExceeded)
    }
    b.nodes -= 1
    match @decode.view(source) {
      TextValue(text) => charge(b, source, text)
      ArrayValue(items) => {
        if depth >= b.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        spend(b, source, items.length())
        for item in items {
          work.push((item, depth + 1))
        }
      }
      ObjectValue(object) => {
        if depth >= b.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        let keys = @decode.object_field_names(source).unwrap()
        spend(b, source, keys.length())
        for key in keys {
          charge(b, source, key)
          work.push((@decode.lookup(object, key).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn contract_preflight(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
  depth? : Int = 0,
) -> Unit raise Stop {
  let work = [(root, depth)]
  while work.pop() is Some((c, depth)) {
    spend(b, source, 1)
    if depth > b.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    match c.shape {
      @contract.Array(item, ..) => work.push((item, depth + 1))
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        spend(b, source, count)
        for i in 0..<count {
          let f = @contract.field_at(fields, i).unwrap()
          charge(b, source, f.name)
          work.push((f.contract, depth + 1))
        }
      }
      @contract.ResourceRef(resource_kind~) => charge(b, source, resource_kind)
      @contract.ArtifactRef(media_type=Some(media)) => charge(b, source, media)
      _ => ()
    }
  }
}

///|
fn order_key(
  b : Budget,
  source : @decode.Cursor,
  fields : Map[String, @schema.Field],
) -> OrderKey raise Stop {
  let key = match @order.read(source) {
    Ok(k) => k
    Err(e) => {
      if e.diagnostic is Some(d) {
        raise Stop({
          source: e.source,
          kind: Decode(d.kind),
          path: d.path.copy(),
          span: d.span,
        })
      }
      fail(
        e.source,
        match e.kind {
          @order.InvalidOrder => InvalidOrder
          @order.Decode(kind) => Decode(kind)
        },
      )
    }
  }
  spend(b, source, key.work)
  let field = key.field
  let field_source = key.field_source
  let contract = match fields.get(field) {
    Some(v) => v
    None => fail(field_source, UnknownField(field))
  }
  if !@order.author_orderable(contract.contract) {
    fail(field_source, NotAuthorOrderable(field))
  }
  {
    field,
    direction: key.direction,
    nulls: key.nulls,
    explicit_nulls: key.explicit_nulls,
    source,
  }
}

///|
fn check_impl(
  pipeline : @pipeline.CheckedPipeline,
  root : @decode.Cursor,
  limits : Limits,
) -> CheckedResults raise Stop {
  if limits.max_results < 0 ||
    limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    fail(root, InvalidLimits)
  }
  let b : Budget = {
    limits,
    work: limits.max_work,
    nodes: limits.max_nodes,
    text: limits.max_text_bytes,
  }
  let object = decoded(@decode.open_object(root), root)
  let names = @decode.object_field_names(root).unwrap()
  if names.is_empty() {
    fail(root, InvalidBody)
  }
  if names.length() > limits.max_results {
    fail(root, BudgetExceeded)
  }
  source_preflight(b, root)
  // One schema index per referenced input/step, shared across all Results.
  let inputs : Map[Int, Map[String, @schema.Field]] = Map([])
  let steps : Map[Int, Map[String, @schema.Field]] = Map([])
  let definitions : Array[ResultDefinition] = []
  let index : Map[String, Int] = Map([])
  for name in names {
    let source = @decode.lookup(object, name).unwrap()
    spend(b, source, 1)
    valid_name(source, name)
    let obj = decoded(
      @decode.closed_object(source, ["from", "fields", "order_by", "meta"]),
      source,
    )
    let from = decoded(@decode.required(obj, "from"), source)
    let from_name = decoded(@decode.text(from), from)
    valid_name(from, from_name)
    let target = match @pipeline.lookup(pipeline, from_name) {
      Some(v) => v
      None => fail(from, UnknownSource(from_name))
    }
    let (cache, id) = match target {
      Input(i) => (inputs, i)
      Step(i) => (steps, i)
    }
    let fields = match cache.get(id) {
      Some(v) => v
      None => {
        let carrier = @pipeline.carrier_at(pipeline, target).unwrap()
        let c = match carrier {
          @carrier.Relation(rows) =>
            match @carrier.complete_schema(rows) {
              Some(c) => c
              None => fail(from, IncompleteSchema)
            }
          _ => fail(from, WrongCarrier(@carrier.kind(carrier)))
        }
        // The schema root has depth zero, as with an ordinary object contract.
        spend(b, from, 1)
        let fields : Map[String, @schema.Field] = Map([])
        let n = @schema.field_count(c)
        spend(b, from, n)
        for i in 0..<n {
          let f = @schema.field_at(c, i).unwrap()
          let name = @schema.reference_name(f.name)
          charge(b, from, name)
          contract_preflight(b, from, f.contract, depth=1)
          fields[name] = f
        }
        spend(b, from, n)
        cache[id] = fields
        fields
      }
    }
    let selected = decoded(@decode.required(obj, "fields"), source)
    let entries = decoded(@decode.elements(selected), selected)
    if entries.is_empty() {
      fail(selected, InvalidBody)
    }
    spend(b, selected, entries.length())
    let projection : Array[(@schema.FieldName, @contract.Contract)] = []
    let seen : Map[String, Bool] = Map([])
    let output_names : Array[String] = []
    let name_budget = b.text
    for entry in entries {
      let key = decoded(@decode.text(entry), entry)
      if seen.contains(key) {
        fail(entry, DuplicateField(key))
      }
      let contract = match fields.get(key) {
        Some(v) => v
        None => fail(entry, UnknownField(key))
      }
      seen[key] = true
      charge(b, entry, key)
      projection.push((contract.name, contract.contract))
      output_names.push(key)
    }
    let output = match
      @schema.from_fields(
        projection,
        max_fields=projection.length(),
        max_name_bytes=name_budget,
      ) {
      Ok(v) => v
      Err(_) => fail(selected, InvalidBody)
    }
    let order = match @decode.lookup(obj, "order_by") {
      None => None
      Some(source) => {
        let entries = decoded(@decode.elements(source), source)
        if entries.is_empty() {
          fail(source, InvalidOrder)
        }
        spend(b, source, entries.length())
        let keys : Array[OrderKey] = []
        for entry in entries {
          keys.push(order_key(b, entry, fields))
        }
        Some(keys)
      }
    }
    let meta = @decode.lookup(obj, "meta")
    if meta is Some(source) {
      let obj = match @decode.open_object(source) {
        Ok(v) => v
        Err(_) => fail(source, InvalidMetadata)
      }
      let keys = @decode.object_field_names(source).unwrap()
      if keys.is_empty() {
        fail(source, InvalidMetadata)
      }
      spend(b, source, keys.length())
      for key in keys {
        if key.has_prefix("actql_") {
          fail(@decode.lookup(obj, key).unwrap(), ReservedMetadataKey(key))
        }
      }
    }
    index[name] = definitions.length()
    definitions.push({
      name,
      source,
      target,
      schema: output,
      fields: output_names,
      order,
      metadata: meta,
    })
  }
  {
    pipeline,
    source: root,
    definitions,
    names: index,
    usage: {
      work: limits.max_work - b.work,
      nodes: limits.max_nodes - b.nodes,
      text_bytes: limits.max_text_bytes - b.text,
    },
  }
}

///|
/// Checks stage-local Result definitions, not deterministic publication order,
/// root exports, policy, delivery or execution admission.
pub fn check(
  pipeline : @pipeline.CheckedPipeline,
  source : @decode.Cursor,
  limits : Limits,
) -> Result[CheckedResults, Issue] {
  Ok(check_impl(pipeline, source, limits)) catch {
    Stop(issue) => Err(issue)
  }
}
