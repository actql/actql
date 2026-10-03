///|
fn metadata(b : Budget, root : @decode.Cursor) -> Unit raise Stop {
  let object = match @decode.open_object(root) {
    Ok(v) => v
    Err(_) => fail(root, InvalidMetadata)
  }
  let keys = @decode.object_field_names(root).unwrap()
  if keys.is_empty() {
    fail(root, InvalidMetadata)
  }
  spend(b, root, keys.length())
  for key in keys {
    if key.has_prefix("actql_") {
      fail(@decode.lookup(object, key).unwrap(), ReservedMetadataKey(key))
    }
  }
  let work = [(root, 0)]
  while work.pop() is Some((cursor, depth)) {
    spend(b, cursor, 1)
    if b.nodes == 0 {
      fail(cursor, BudgetExceeded)
    }
    b.nodes -= 1
    match @decode.view(cursor) {
      TextValue(v) => charge(b, cursor, v)
      ArrayValue(items) => {
        if depth >= b.limits.max_depth {
          fail(cursor, BudgetExceeded)
        }
        spend(b, cursor, items.length())
        for item in items {
          work.push((item, depth + 1))
        }
      }
      ObjectValue(obj) => {
        if depth >= b.limits.max_depth {
          fail(cursor, BudgetExceeded)
        }
        let names = @decode.object_field_names(cursor).unwrap()
        spend(b, cursor, names.length())
        for key in names {
          charge(b, cursor, key)
          work.push((@decode.lookup(obj, key).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn check_impl(
  source : @decode.Cursor,
  supplied_inputs : Array[(String, @carrier.Carrier)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile : @calendar_profile.Profile?,
  text_rank_profile : @text_rank_profile.Profile?,
  delta_contracts : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ],
  keyed_inputs : Array[@evidence.KeySet?],
  ranked_inputs : Array[@vector.RankingInput?],
  produced_inputs : Array[ProducedInput?],
  input_contracts : Array[InputContract],
  model_tasks : @model_environment.ModelTasks?,
) -> CheckedPipeline raise Stop {
  if limits.max_steps < 0 ||
    limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_tokens < 0 ||
    limits.max_depth < 0 {
    fail(source, InvalidLimits)
  }
  let b : Budget = {
    limits,
    work: limits.max_work,
    text: limits.max_text_bytes,
    nodes: limits.max_nodes,
    tokens: limits.max_tokens,
  }
  let bodies = match @decode.elements(source) {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
  if bodies.length() > limits.max_steps {
    fail(source, BudgetExceeded)
  }
  spend(b, source, supplied_inputs.length())
  let inputs = supplied_inputs.copy()
  let names : Map[String, Target] = Map([])
  for i in 0..<inputs.length() {
    let (key, schema) = inputs[i]
    name(b, source, key)
    if input_contracts[i] is SourceViewInput(stage, declared, retained, _) {
      let body = @decode.open_object(@stage.stage_body(stage)).unwrap()
      let steps = @decode.required(body, "steps").unwrap()
      let declarations = @decode.required(body, "inputs").unwrap()
      // Opening a declaration table is part of the same bounded check. A
      // retained syntax owner is not a license to scan uncharged source.
      let count = @decode.object_length(declarations).unwrap()
      spend(b, source, count)
      for index in 0..<count {
        charge(b, source, @decode.field_at(declarations, index).unwrap().0)
      }
      let original = @decode.open_object(declarations).bind(object => {
        @decode.required(object, declared)
      })
      if declared != key ||
        @decode.tree_index(steps, source) != @decode.tree_index(steps, steps) ||
        !(original is Ok(value) &&
        @decode.tree_index(value, retained) == @decode.tree_index(value, value)) {
        fail(source, KeyEvidence(InputContractMismatch))
      }
    }
    if names.contains(key) {
      fail(source, DuplicateName(key))
    }
    carrier_preflight(b, source, schema)
    if keyed_inputs[i] is Some(collection) {
      spend(b, source, @evidence.key_witness_count(collection))
      for k in 0..<@evidence.key_witness_count(collection) {
        let declaration = @evidence.key_witness_at(collection, k).unwrap()
        spend(b, source, @evidence.key_field_count(declaration))
        for j in 0..<@evidence.key_field_count(declaration) {
          spend(b, source, @evidence.key_alias_count(declaration, j))
          for n in 0..<@evidence.key_alias_count(declaration, j) {
            let field = @evidence.key_alias_at(declaration, j, n).unwrap()
            charge(b, source, @schema.reference_name(field.name))
          }
        }
      }
    }
    names[key] = Input(i)
  }
  if parameters is Some(p) {
    let count = @parameter.declaration_count(p)
    spend(b, source, count)
    for i in 0..<count {
      let d = @parameter.declaration_at(p, i).unwrap()
      charge(b, source, d.name)
      preflight(b, source, d.parameter_type.contract)
    }
  }
  let mut current : Target? = match from {
    Some(cursor) => {
      let key = read_name(b, cursor)
      match names.get(key) {
        Some(v) => Some(v)
        None => fail(cursor, UnknownName(key))
      }
    }
    None => if inputs.length() == 1 { Some(Input(0)) } else { None }
  }
  let steps : Array[CheckedStep] = []
  let ranked_steps : Array[@vector.RankingInput] = []
  let keyed_steps : Array[@evidence.KeySet?] = []
  spend(b, source, produced_inputs.length())
  let literal_inputs = produced_inputs.map(input => input.bind(v => v.literals))
  for domains in literal_inputs {
    if domains is Some(domains) {
      let _ = literal_result(
        b,
        source,
        @evidence.admit_literal_domains(source, domains, {
          max_work: b.work,
          max_name_bytes: b.text,
        }),
      )
    }
  }
  let literal_steps : Array[@evidence.LiteralDomains?] = []
  let delta_inputs = imported_delta(b, source, produced_inputs)
  let delta_steps : Array[DeltaEvidence] = []
  spend(b, source, delta_contracts.length())
  for (input_name, field, contract) in delta_contracts {
    name(b, source, input_name)
    let index = match names.get(input_name) {
      Some(Input(i)) => i
      _ => fail(source, InvalidDeltaContractBinding)
    }
    let rows = match inputs[index].1 {
      @carrier.Relation(r) => r
      _ => fail(source, InvalidDeltaContractBinding)
    }
    guard @carrier.lookup(rows, field) is Present({ contract: Some(_), .. }) else {
      fail(source, InvalidDeltaContractBinding)
    }
    let key = @schema.reference_name(field)
    charge(b, source, key)
    if delta_inputs[index].fields.contains(key) {
      fail(source, InvalidDeltaContractBinding)
    }
    carrier_preflight(
      b,
      source,
      @carrier.graph_carrier(@graph_contract.graph(contract)),
    )
    delta_inputs[index].fields[key] = contract
  }
  for body in bodies {
    sync_delta(b, body, delta_inputs, steps, delta_steps)
    sync_keys(
      b, keyed_inputs, steps, keyed_steps, literal_inputs, literal_steps,
    )
    sync_rankings(b, inputs, ranked_inputs, steps, ranked_steps)
    spend(b, body, 1)
    if b.nodes == 0 {
      fail(body, BudgetExceeded)
    }
    b.nodes -= 1
    let object = match @decode.open_object(body) {
      Ok(v) => v
      Err(_) => fail(body, InvalidBody)
    }
    let keys = @decode.object_field_names(body).unwrap()
    spend(b, body, keys.length())
    let mut operation_name : String? = None
    for key in keys {
      charge(b, body, key)
      if key != "from" && key != "as" && key != "meta" {
        if operation_name is Some(_) {
          fail(body, InvalidBody)
        }
        operation_name = Some(key)
      }
    }
    let key = match operation_name {
      Some(v) => v
      None => fail(body, InvalidBody)
    }
    if key == "property_graph" {
      let step = check_property_graph_step(
        body,
        @decode.lookup(object, key).unwrap(),
        object,
        names,
        inputs,
        input_contracts,
        produced_inputs,
        steps,
        b,
      )
      let target = Step(steps.length())
      names[step.binding_name.unwrap()] = target
      steps.push(step)
      current = Some(target)
      continue
    }
    if key == "graph" {
      // The retired constructor is rejected at the public checked boundary.
      // Do not resolve its operands or construct a compatibility operation.
      let at = @decode.lookup(object, key).unwrap()
      fail(at, Graph(@graph.UnsupportedGraphOperation))
    }
    if key == "values" {
      if @decode.lookup(object, "from") is Some(s) {
        fail(s, GeneratorFrom)
      }
      let alias_source = match @decode.lookup(object, "as") {
        Some(s) => s
        None => fail(body, GeneratorRequiresAlias)
      }
      let binding = read_name(b, alias_source)
      if names.contains(binding) {
        fail(alias_source, DuplicateName(binding))
      }
      let meta = @decode.lookup(object, "meta")
      if meta is Some(s) {
        metadata(b, s)
      }
      let checked = match
        @values.check(@decode.lookup(object, key).unwrap(), parameters, {
          max_rows: b.nodes,
          max_work: b.work,
          max_nodes: b.nodes,
          max_text_bytes: b.text,
          max_depth: limits.max_depth,
        }) {
        Ok(v) => v
        Err(issue) =>
          raise Stop({
            kind: Values(issue.kind),
            source: issue.source,
            path: issue.path.copy(),
            span: issue.span,
            range: None,
          })
      }
      let used = @values.usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: None,
        binding_name: Some(binding),
        metadata: meta,
        operation: Values(checked),
        output: @carrier.relation(
          @carrier.typed_rows(@values.output_schema(checked)),
        ),
        connections: { entries: [], },
        window: None,
      })
      names[binding] = target
      current = Some(target)
      continue
    }
    if key == "calendar_bucket" || key == "calendar_series" {
      let generator = key == "calendar_series"
      let main = if generator {
        if @decode.lookup(object, "from") is Some(s) {
          fail(s, GeneratorFrom)
        }
        None
      } else {
        Some(
          match @decode.lookup(object, "from") {
            Some(s) => resolve_target(b, s, names)
            None =>
              match current {
                Some(t) => t
                None => fail(body, MissingCurrent)
              }
          },
        )
      }
      let binding_name = match @decode.lookup(object, "as") {
        Some(s) => {
          let name = read_name(b, s)
          if names.contains(name) {
            fail(s, DuplicateName(name))
          }
          Some(name)
        }
        None =>
          if generator {
            fail(body, GeneratorRequiresAlias)
          } else {
            None
          }
      }
      let meta = @decode.lookup(object, "meta")
      if meta is Some(s) {
        metadata(b, s)
      }
      let operation_body = @decode.lookup(object, key).unwrap()
      let checked = match
        @calendar.check(
          if generator {
            Series
          } else {
            Bucket
          },
          operation_body,
          main.map(t => carrier(t, inputs, steps)),
          parameters,
          calendar_profile,
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_text_bytes: b.text,
            max_depth: limits.max_depth,
          },
        ) {
        Ok(v) => v
        Err(e) =>
          raise Stop({
            kind: Calendar(e.kind),
            source: operation_body,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
      let u = @calendar.usage(checked)
      b.work -= u.work
      b.nodes -= u.nodes
      b.text -= u.text_bytes
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: main,
        binding_name,
        metadata: meta,
        operation: Calendar(checked),
        output: @calendar.output(checked),
        connections: {
          entries: match main {
            None => []
            Some(t) => [{ role: Primary, target: t, }]
          },
        },
        window: match main {
          None => None
          Some(Step(i)) => steps[i].window
          Some(Input(_)) => None
        },
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "mean_graphs" {
      if @decode.lookup(object, "from") is Some(s) {
        fail(s, GeneratorFrom)
      }
      let alias_source = match @decode.lookup(object, "as") {
        Some(s) => s
        None => fail(body, GeneratorRequiresAlias)
      }
      let binding = read_name(b, alias_source)
      if names.contains(binding) {
        fail(alias_source, DuplicateName(binding))
      }
      if @decode.lookup(object, "meta") is Some(s) {
        metadata(b, s)
      }
      let at = @decode.lookup(object, key).unwrap()
      // Validate authored options, but never issue an executable old Graph mean.
      match
        @graph.check_mean_options(at, {
          max_work: b.work,
          max_nodes: b.nodes,
          max_text_bytes: b.text,
          max_depth: limits.max_depth,
        }) {
        Ok(_) => fail(at, Graph(@graph.UnsupportedGraphOperation))
        Err(e) =>
          raise Stop({
            kind: Graph(e.kind),
            source: at,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
    }
    if key == "time_series" {
      if @decode.lookup(object, "from") is Some(s) {
        fail(s, GeneratorFrom)
      }
      let alias_source = match @decode.lookup(object, "as") {
        Some(s) => s
        None => fail(body, GeneratorRequiresAlias)
      }
      let binding = read_name(b, alias_source)
      if names.contains(binding) {
        fail(alias_source, DuplicateName(binding))
      }
      let meta = @decode.lookup(object, "meta")
      if meta is Some(s) {
        metadata(b, s)
      }
      let checked = match
        @series.check(@decode.lookup(object, key).unwrap(), parameters, {
          max_work: b.work,
          max_nodes: b.nodes,
          max_text_bytes: b.text,
          max_depth: limits.max_depth,
        }) {
        Ok(v) => v
        Err(issue) =>
          raise Stop({
            kind: TimeSeries(issue.kind),
            source: @decode.lookup(object, key).unwrap(),
            path: issue.path.copy(),
            span: issue.span,
            range: None,
          })
      }
      let used = @series.usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: None,
        binding_name: Some(binding),
        metadata: meta,
        operation: TimeSeries(checked),
        output: @series.output(checked),
        connections: { entries: [], },
        window: None,
      })
      names[binding] = target
      current = Some(target)
      continue
    }
    let op : @relation.Operation? = match key {
      "derive" => Some(Derive)
      "filter" => Some(Filter)
      "select" => Some(Select)
      "rename" => Some(Rename)
      "drop" => Some(Drop)
      "sort" => Some(Sort)
      "take" => Some(Take)
      "distinct" => Some(Distinct)
      "dedupe_rows" => Some(DedupeRows)
      "json_pick" => Some(JsonPick)
      "unnest" => Some(Unnest)
      "assert_rows" => Some(AssertRows)
      "unpivot" => Some(Unpivot)
      "group" => Some(Group)
      "window_group" => Some(Group)
      "pivot" => Some(Pivot)
      "analytic" => Some(Analytic)
      "top_k" => Some(TopK)
      "top_k_by" => Some(TopKBy)
      "lag" => Some(Lag)
      "watermark_rows" => Some(WatermarkRows)
      "join"
      | "append"
      | "nest"
      | "except"
      | "intersect"
      | "cross_join"
      | "interval_join"
      | "asof_join"
      | "sequence"
      | "row_window"
      | "events"
      | "watermark_events"
      | "to_events"
      | "dedupe_events"
      | "session"
      | "normalize_graph"
      | "normalize_vectors"
      | "to_vectors"
      | "score_vectors"
      | "nearest"
      | "pool_vectors"
      | "merge_rankings"
      | "text_rank"
      | "degree"
      | "components"
      | "graph_bounds"
      | "graphs_equal"
      | "graph_diff"
      | "match_nodes"
      | "match_edges"
      | "reach"
      | "subgraph"
      | "traverse"
      | "shortest_path"
      | "graft_graph"
      | "union_graphs"
      | "subtract_graphs"
      | "apply_graph_delta"
      | "vectors"
      | "node_rows"
      | "edge_rows"
      | "window_events" => None
      "infer" => None
      _ => fail(@decode.lookup(object, key).unwrap(), UnsupportedOperation(key))
    }
    let selected = match @decode.lookup(object, "from") {
      Some(cursor) => {
        let key = read_name(b, cursor)
        match names.get(key) {
          Some(v) => Some(v)
          None => fail(cursor, UnknownName(key))
        }
      }
      None => current
    }
    let operation_body = @decode.lookup(object, key).unwrap()
    let join_object = if key == "join" {
      match @decode.open_object(operation_body) {
        Ok(v) => Some(v)
        Err(_) => fail(operation_body, InvalidBody)
      }
    } else {
      None
    }
    let input = match join_object {
      Some(obj) =>
        match @decode.lookup(obj, "left") {
          Some(s) => resolve_target(b, s, names)
          None =>
            match selected {
              Some(v) => v
              None => fail(body, MissingCurrent)
            }
        }
      None =>
        match selected {
          Some(v) => v
          None => fail(body, MissingCurrent)
        }
    }
    let binding_name = match @decode.lookup(object, "as") {
      Some(cursor) => {
        let key = read_name(b, cursor)
        if names.contains(key) {
          fail(cursor, DuplicateName(key))
        }
        Some(key)
      }
      None => None
    }
    let meta = @decode.lookup(object, "meta")
    if meta is Some(cursor) {
      metadata(b, cursor)
    }
    // Only guaranteed-column projection currently consumes conditional rows.
    // This checked boundary also covers consumers using Knowledge directly,
    // rather than letting them infer dense rows from known field types.
    if key != "select" {
      if carrier(input, inputs, steps) is @carrier.Relation(rows) {
        if !@carrier.all_fields_required(rows) {
          fail(
            operation_body,
            Operation(@relation.ConditionalInputNotImplemented),
          )
        }
      }
    }
    if key == "infer" {
      if binding_name is None {
        fail(body, InferRequiresAlias)
      }
      let tasks = match model_tasks {
        Some(tasks) => tasks
        None => fail(operation_body, MissingModelTasks)
      }
      let checked = match
        @evidence.check_infer(
          operation_body,
          carrier(input, inputs, steps),
          key_at(input, keyed_inputs, keyed_steps),
          tasks,
          parameters,
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: b.text,
            max_tokens: b.tokens,
            max_key_fields: b.nodes.min(b.work),
            max_input_roles: b.nodes.min(b.work),
          },
        ) {
        Ok(checked) => checked
        Err(issue) => fail(issue.source, Infer(issue.kind))
      }
      let used = @evidence.infer_usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      b.tokens -= used.tokens
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: Infer(checked),
        output: @carrier.relation(
          @carrier.typed_rows(@evidence.infer_output_schema(checked)),
        ),
        connections: { entries: [{ role: Primary, target: input, }], },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "sequence" {
      let checked = match
        @relation.check_sequence(
          operation_body,
          carrier(input, inputs, steps),
          parameters,
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_text_bytes: b.text,
            max_tokens: b.tokens,
            max_depth: limits.max_depth,
          },
        ) {
        Ok(v) => v
        Err(e) =>
          raise Stop({
            kind: Operation(e.kind),
            source: e.source,
            path: e.path.copy(),
            span: e.span,
            range: e.range,
          })
      }
      let used = @relation.sequence_usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      b.tokens -= used.tokens
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: Sequence(checked),
        output: @carrier.relation(
          @carrier.typed_rows(@relation.sequence_output(checked)),
        ),
        connections: { entries: [{ role: Primary, target: input, }], },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "asof_join" {
      let obj = match @decode.open_object(operation_body) {
        Ok(v) => v
        Err(_) => fail(operation_body, InvalidBody)
      }
      let right_source = match @decode.required(obj, "with") {
        Ok(v) => v
        Err(_) => fail(operation_body, InvalidBody)
      }
      let right = resolve_target(b, right_source, names)
      let checked = match
        @join.check_asof_sources(
          operation_body,
          asof_input_source(input, inputs, steps, keyed_inputs, keyed_steps),
          asof_input_source(right, inputs, steps, keyed_inputs, keyed_steps),
          parameters,
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_text_bytes: b.text,
            max_depth: limits.max_depth,
          },
        ) {
        Ok(v) => v
        Err(e) =>
          raise Stop({
            kind: Join(e.kind),
            source: e.source,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
      let used = @join.asof_usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: AsOfJoin(right~, checked~),
        output: @carrier.relation(
          @carrier.typed_rows(@join.asof_output_schema(checked)),
        ),
        connections: {
          entries: [
            { role: Left, target: input, },
            { role: Right, target: right, },
          ],
        },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "graphs_equal" ||
      key == "graph_diff" ||
      key == "graft_graph" ||
      key == "union_graphs" ||
      key == "subtract_graphs" ||
      key == "apply_graph_delta" {
      let object = match
        @decode.closed_object(
          operation_body,
          if key == "apply_graph_delta" {
            ["with", "field"]
          } else if key == "union_graphs" || key == "subtract_graphs" {
            ["with", "merge"]
          } else {
            ["with"]
          },
        ) {
        Ok(object) => object
        Err(_) => fail(operation_body, InvalidBody)
      }
      let at = match @decode.required(object, "with") {
        Ok(at) => at
        Err(_) => fail(operation_body, InvalidBody)
      }
      if key == "union_graphs" && @decode.array_length(at) is Some(count) {
        if count == 0 {
          fail(at, InvalidBody)
        }
        spend(b, at, count)
        for index in 0..<count {
          ignore(
            resolve_target(b, @decode.element_at(at, index).unwrap(), names),
          )
        }
      } else {
        ignore(resolve_target(b, at, names))
      }
      if key == "apply_graph_delta" {
        let field = match @decode.required(object, "field") {
          Ok(field) => field
          Err(_) => fail(operation_body, InvalidBody)
        }
        ignore(read_name(b, field))
      }
      // The sole Graph is keyed. These consumers have no current implementation,
      // and cannot issue an old tuple output, comparison or Delta permission.
      match carrier(input, inputs, steps) {
        @carrier.GraphValue(_) =>
          fail(operation_body, Graph(@graph.UnsupportedGraphOperation))
        @carrier.Opaque(GraphKind) =>
          fail(operation_body, Graph(@graph.IncompleteGraph))
        other =>
          fail(operation_body, Graph(@graph.WrongCarrier(@carrier.kind(other))))
      }
    }
    if key == "shortest_path" {
      let root = match
        @decode.closed_object(operation_body, [
          "source", "target", "selection", "direction", "max_hops", "weight", "edge_types",
          "max_output_rows",
        ]) {
        Ok(o) => o
        Err(_) => fail(operation_body, InvalidBody)
      }
      for name in ["source", "target"] {
        let at = match @decode.required(root, name) {
          Ok(c) => c
          Err(_) => fail(operation_body, InvalidBody)
        }
        let _ = if @decode.view(at) is ObjectValue(_) {
          let o = match
            @decode.closed_object(at, ["ids", "from", "id", "where"]) {
            Ok(o) => o
            Err(_) => fail(at, InvalidBody)
          }
          @decode.lookup(o, "from").map(c => resolve_target(b, c, names))
        } else {
          None
        }
      }
      match carrier(input, inputs, steps) {
        @carrier.GraphValue(_) =>
          fail(operation_body, Graph(@graph.UnsupportedGraphOperation))
        @carrier.Opaque(GraphKind) =>
          fail(operation_body, Graph(@graph.IncompleteGraph))
        other =>
          fail(operation_body, Graph(@graph.WrongCarrier(@carrier.kind(other))))
      }
    }
    if key == "reach" {
      let root = match
        @decode.closed_object(operation_body, [
          "start", "direction", "max_depth",
        ]) {
        Ok(o) => o
        Err(_) => fail(operation_body, InvalidBody)
      }
      let start = match @decode.required(root, "start") {
        Ok(c) => c
        Err(_) => fail(operation_body, InvalidBody)
      }
      let selector = match @decode.view(start) {
        ObjectValue(_) => {
          let body = match
            @decode.closed_object(start, ["ids", "from", "id", "where"]) {
            Ok(o) => o
            Err(_) => fail(start, InvalidBody)
          }
          @decode.lookup(body, "from").map(at => resolve_target(b, at, names))
        }
        _ => None
      }
      // A bounded authored reference is checked above, but reach has no
      // implementation under the sole keyed Property Graph contract.
      ignore(selector)
      match carrier(input, inputs, steps) {
        @carrier.GraphValue(_) =>
          fail(operation_body, Graph(@graph.UnsupportedGraphOperation))
        @carrier.Opaque(GraphKind) =>
          fail(operation_body, Graph(@graph.IncompleteGraph))
        other =>
          fail(operation_body, Graph(@graph.WrongCarrier(@carrier.kind(other))))
      }
    }
    if key == "subgraph" {
      let root = match
        @decode.closed_object(operation_body, ["nodes", "edges"]) {
        Ok(value) => value
        Err(_) => fail(operation_body, InvalidBody)
      }
      let at = match @decode.required(root, "nodes") {
        Ok(value) => value
        Err(_) => fail(operation_body, InvalidBody)
      }
      let selector = match
        @decode.closed_object(at, ["ids", "from", "id", "where"]) {
        Ok(value) => value
        Err(_) => fail(at, InvalidBody)
      }
      if @decode.lookup(selector, "from") is Some(reference) {
        ignore(resolve_target(b, reference, names))
      }
      // No induced-subgraph implementation is connected to the current contract.
      match carrier(input, inputs, steps) {
        @carrier.GraphValue(_) =>
          fail(operation_body, Graph(@graph.UnsupportedGraphOperation))
        @carrier.Opaque(GraphKind) =>
          fail(operation_body, Graph(@graph.IncompleteGraph))
        other =>
          fail(operation_body, Graph(@graph.WrongCarrier(@carrier.kind(other))))
      }
    }
    if key == "traverse" {
      let root = match
        @decode.closed_object(operation_body, [
          "start", "hops", "direction", "edge_types", "min_hops", "max_hops", "emit",
          "max_output_rows", "path_mode",
        ]) {
        Ok(o) => o
        Err(_) => fail(operation_body, InvalidBody)
      }
      let at = match @decode.required(root, "start") {
        Ok(c) => c
        Err(_) => fail(operation_body, InvalidBody)
      }
      let selector_body = match
        @decode.closed_object(at, ["ids", "from", "id", "where"]) {
        Ok(o) => o
        Err(_) => fail(at, InvalidBody)
      }
      let selector = @decode.lookup(selector_body, "from").map(at => {
        resolve_target(b, at, names)
      })
      let caps : @graph.PredicateLimits = {
        max_work: b.work,
        max_nodes: b.nodes,
        max_depth: limits.max_depth,
        max_text_bytes: b.text,
        max_tokens: b.tokens,
      }
      let checked = @graph.check_traverse(
        operation_body,
        carrier(input, inputs, steps),
        selector.map(t => carrier(t, inputs, steps)),
        parameters,
        caps,
      ).map(c => {
        (
          Traverse(selector~, checked=c),
          @graph.traverse_output(c),
          @graph.traverse_usage(c),
        )
      })
      let (operation, output, used) = match checked {
        Ok(c) => c
        Err(e) => {
          let d = @graph.match_diagnostic(e, operation_body)
          raise Stop({
            kind: GraphMatch(d.kind),
            source: operation_body,
            path: d.path.copy(),
            span: d.span,
            range: d.range,
          })
        }
      }
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      b.tokens -= used.tokens
      let entries = [{ role: Primary, target: input, }]
      if selector is Some(t) {
        entries.push({ role: Right, target: t, })
      }
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation,
        output,
        connections: { entries, },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "match_nodes" || key == "match_edges" {
      let checked = match
        @graph.check_match(
          if key == "match_nodes" {
            @graph.Nodes
          } else {
            @graph.Edges
          },
          operation_body,
          carrier(input, inputs, steps),
          parameters,
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: b.text,
            max_tokens: b.tokens,
          },
        ) {
        Ok(c) => c
        Err(e) => {
          let d = @graph.match_diagnostic(e, operation_body)
          raise Stop({
            kind: GraphMatch(d.kind),
            source: operation_body,
            path: d.path.copy(),
            span: d.span,
            range: d.range,
          })
        }
      }
      let used = @graph.match_usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      b.tokens -= used.tokens
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: GraphMatch(checked),
        output: @graph.match_output(checked),
        connections: { entries: [{ role: Primary, target: input, }], },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "normalize_graph" ||
      key == "degree" ||
      key == "components" ||
      key == "graph_bounds" {
      match carrier(input, inputs, steps) {
        @carrier.GraphValue(_) =>
          fail(operation_body, Graph(@graph.UnsupportedGraphOperation))
        @carrier.Opaque(GraphKind) =>
          fail(operation_body, Graph(@graph.IncompleteGraph))
        other =>
          fail(operation_body, Graph(@graph.WrongCarrier(@carrier.kind(other))))
      }
    }
    if key == "text_rank" {
      let options = vector_result(
        operation_body,
        @vector.read_text_rank_options(operation_body, {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
        }),
      )
      let u = @vector.text_rank_options_usage(options)
      b.work -= u.work
      b.nodes -= u.nodes
      b.text -= u.text_bytes
      let root = @decode.open_object(operation_body).unwrap()
      let queries = resolve_target(
        b,
        @decode.required(root, "queries").unwrap(),
        names,
      )
      let checked = vector_result(
        operation_body,
        @vector.check_text_rank_inputs(
          options,
          carrier(input, inputs, steps),
          carrier(queries, inputs, steps),
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: b.text,
          },
          profile=text_rank_profile,
        ),
      )
      let u = @vector.text_rank_usage(checked)
      b.work -= u.work
      b.nodes -= u.nodes
      b.text -= u.text_bytes
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: TextRank(queries~, checked~),
        output: @vector.text_rank_output(checked),
        connections: {
          entries: [
            { role: Left, target: input, },
            { role: Right, target: queries, },
          ],
        },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "merge_rankings" {
      let options = vector_result(
        operation_body,
        @vector.read_ranking_options(operation_body, {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
        }),
      )
      let u = @vector.ranking_options_usage(options)
      b.work -= u.work
      b.nodes -= u.nodes
      b.text -= u.text_bytes
      let root = @decode.open_object(operation_body).unwrap()
      let at = @decode.required(root, "with").unwrap()
      let targets = [input]
      match @decode.view(at) {
        ArrayValue(items) => {
          spend(b, at, items.length())
          for item in items {
            targets.push(resolve_target(b, item, names))
          }
        }
        _ => targets.push(resolve_target(b, at, names))
      }
      spend(b, operation_body, targets.length())
      let ranking_inputs = targets.map(t => {
        ranking_at(t, inputs, ranked_inputs, ranked_steps)
      })
      let checked = vector_result(
        operation_body,
        @vector.check_ranking_fusion(options, ranking_inputs, {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
        }),
      )
      let u = @vector.merged_ranking_usage(checked)
      b.work -= u.work
      b.nodes -= u.nodes
      b.text -= u.text_bytes
      let edges : Array[InputOccurrence] = []
      for i in 0..<targets.length() {
        edges.push({ role: Sample(i), target: targets[i], })
      }
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: Ranking(checked),
        output: @vector.merged_ranking_output(checked),
        connections: { entries: edges, },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "pool_vectors" {
      let caps : @vector.Limits = {
        max_work: b.work,
        max_nodes: b.nodes,
        max_depth: limits.max_depth,
        max_text_bytes: b.text,
      }
      let result = match carrier(input, inputs, steps) {
        @carrier.Relation(_) => {
          let declaration = key_at(input, keyed_inputs, keyed_steps)
          guard declaration is Some(declaration) else {
            fail(operation_body, MissingKeyEvidence)
          }
          @vector.check_pool_keys(operation_body, declaration, caps)
        }
        other => @vector.check_pool_vectors(operation_body, other, caps)
      }
      let checked = match result {
        Ok(c) => c
        Err(e) =>
          raise Stop({
            kind: Vector(e.kind),
            source: operation_body,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
      let u = @vector.pooled_usage(checked)
      b.work -= u.work
      b.nodes -= u.nodes
      b.text -= u.text_bytes
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: Pool(checked),
        output: @vector.pooled_output(checked),
        connections: { entries: [{ role: Primary, target: input, }], },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "nearest" {
      let root = match
        @decode.closed_object(operation_body, [
          "queries", "candidate_id", "candidate_vector", "query_id", "query_vector",
          "metric", "k",
        ]) {
        Ok(o) => o
        Err(_) => fail(operation_body, InvalidBody)
      }
      let query_source = match @decode.required(root, "queries") {
        Ok(s) => s
        Err(_) => fail(operation_body, InvalidBody)
      }
      let queries = resolve_target(b, query_source, names)
      let checked = match
        @vector.check_nearest_sources(
          operation_body,
          nearest_input_source(input, inputs, steps, keyed_inputs, keyed_steps),
          nearest_input_source(
            queries, inputs, steps, keyed_inputs, keyed_steps,
          ),
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: b.text,
          },
        ) {
        Ok(c) => c
        Err(e) =>
          raise Stop({
            kind: Vector(e.kind),
            source: operation_body,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
      let u = @vector.nearest_usage(checked)
      b.work -= u.work
      b.nodes -= u.nodes
      b.text -= u.text_bytes
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: Nearest(queries~, checked~),
        output: @vector.nearest_output(checked),
        connections: {
          entries: [
            { role: Left, target: input, },
            { role: Right, target: queries, },
          ],
        },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "normalize_vectors" ||
      key == "score_vectors" ||
      key == "to_vectors" {
      let operation = match key {
        "to_vectors" => @vector.ToVectors
        "normalize_vectors" => @vector.NormalizeVectors
        _ => @vector.ScoreVectors
      }
      let checked = match
        @vector.check(
          operation,
          operation_body,
          carrier(input, inputs, steps),
          parameters,
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: b.text,
          },
        ) {
        Ok(value) => value
        Err(e) =>
          raise Stop({
            kind: Vector(e.kind),
            source: operation_body,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
      let used = @vector.usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: Vector(checked),
        output: @vector.output(checked),
        connections: { entries: [{ role: Primary, target: input, }], },
        window: None,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "watermark_events" ||
      key == "to_events" ||
      key == "dedupe_events" ||
      key == "session" {
      let check_event = match key {
        "session" =>
          fn(source, input, caps) {
            @event.check_session(source, input, parameters, caps)
          }
        "to_events" => @event.check_bridge
        "dedupe_events" => @event.check_dedupe
        _ => @event.check_watermark
      }
      let checked = match
        check_event(operation_body, carrier(input, inputs, steps), {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
        }) {
        Ok(value) => value
        Err(e) =>
          raise Stop({
            kind: Event(e.kind),
            source: operation_body,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
      let used = @event.usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      let target = Step(steps.length())
      let operation : CheckedOperation = Event(checked)
      let window = transfer_window(
        b, operation_body, input, steps, operation, produced_inputs,
      )
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation,
        output: @event.output(checked),
        connections: { entries: [{ role: Primary, target: input, }], },
        window,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "edge_rows" {
      if @decode.boolean(operation_body) != Ok(true) {
        fail(operation_body, Projection(@projection.InvalidBody))
      }
      match carrier(input, inputs, steps) {
        @carrier.GraphValue(_) =>
          fail(
            operation_body,
            Projection(@projection.UnsupportedGraphOperation),
          )
        @carrier.Opaque(GraphKind) =>
          fail(operation_body, Projection(@projection.IncompleteGraph))
        other =>
          fail(
            operation_body,
            Projection(@projection.WrongCarrier(@carrier.kind(other))),
          )
      }
    }
    if key == "node_rows" || key == "events" || key == "vectors" {
      let projection = match key {
        "node_rows" => @projection.NodeRows
        "events" => @projection.Events
        _ => @projection.Vectors
      }
      let checked = match
        @projection.check(
          projection,
          operation_body,
          carrier(input, inputs, steps),
          {
            max_work: b.work,
            max_nodes: b.nodes,
            max_text_bytes: b.text,
            max_depth: limits.max_depth,
          },
        ) {
        Ok(value) => value
        Err(e) =>
          raise Stop({
            kind: Projection(e.kind),
            source: operation_body,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
      let used = @projection.usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      let operation : CheckedOperation = Projection(checked)
      let window = transfer_window(
        b, operation_body, input, steps, operation, produced_inputs,
      )
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation,
        output: @projection.output(checked),
        connections: { entries: [{ role: Primary, target: input, }], },
        window,
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    if key == "row_window" || key == "window_events" {
      let input_carrier = carrier(input, inputs, steps)
      let expected = if key == "row_window" {
        @carrier.RelationKind
      } else {
        @carrier.EventsKind
      }
      if @carrier.kind(input_carrier) != expected {
        fail(operation_body, WrongCarrier(@carrier.kind(input_carrier)))
      }
      let checked = match
        @window.check(operation_body, input_carrier, parameters, {
          max_work: b.work,
          max_nodes: b.nodes,
          max_text_bytes: b.text,
          max_depth: limits.max_depth,
        }) {
        Ok(v) => v
        Err(e) =>
          raise Stop({
            kind: Window(e.kind),
            source: operation_body,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
      let used = @window.check_usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      let (start, end) = @window.boundary_fields(@window.window_roles(checked))
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: Window(checked),
        output: @window.output(checked),
        connections: { entries: [{ role: Primary, target: input, }], },
        window: Some({ starts: [start], ends: [end], }),
      })
      if binding_name is Some(name) {
        names[name] = target
      }
      current = Some(target)
      continue
    }
    let (checked, output) = match op {
      Some(op) => {
        let input_schema = schema(
          operation_body,
          input,
          inputs,
          steps,
          allow_conditional=key == "select",
        )
        let operation_limits : @relation.Limits = {
          max_work: b.work,
          max_text_bytes: b.text,
          max_nodes: b.nodes,
          max_tokens: b.tokens,
          max_depth: limits.max_depth,
        }
        let result = if key == "window_group" {
          let evidence = window_at(input, steps, produced_inputs)
          let roles = match evidence {
            Some(v) => v
            None => fail(operation_body, MissingWindowEvidence)
          }
          @relation.check_group_with_prefix(
            operation_body,
            input_schema,
            [roles.starts[0], roles.ends[0]],
            parameters,
            operation_limits,
          )
        } else {
          @relation.check(
            op, operation_body, input_schema, parameters, operation_limits,
          )
        }
        let checked = match result {
          Ok(v) => v
          Err(issue) =>
            raise Stop({
              kind: Operation(issue.kind),
              source: issue.source,
              path: issue.path.copy(),
              span: issue.span,
              range: issue.range,
            })
        }
        b.work -= @relation.work_used(checked)
        b.text -= @relation.text_bytes_used(checked)
        b.nodes -= @relation.nodes_used(checked)
        b.tokens -= @relation.tokens_used(checked)
        (
          if key == "window_group" {
            WindowGroup(checked)
          } else {
            Unary(checked)
          },
          @relation.output_schema(checked),
        )
      }
      None =>
        if key == "interval_join" {
          let obj = match @decode.open_object(operation_body) {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right_source = match @decode.required(obj, "with") {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, right_source, names)
          let checked = match
            @join.check_interval(
              operation_body,
              schema(operation_body, input, inputs, steps),
              schema(right_source, right, inputs, steps),
              parameters,
              {
                max_work: b.work,
                max_text_bytes: b.text,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(v) => v
            Err(issue) =>
              raise Stop({
                kind: Join(issue.kind),
                source: issue.source,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @join.interval_usage(checked)
          b.work -= used.work
          b.text -= used.text_bytes
          b.nodes -= used.nodes
          (
            IntervalJoin(right~, checked~),
            @join.interval_output_schema(checked),
          )
        } else if key == "cross_join" {
          let obj = match @decode.open_object(operation_body) {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right_source = match @decode.required(obj, "with") {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, right_source, names)
          let checked = match
            @join.check_cross(
              operation_body,
              schema(operation_body, input, inputs, steps),
              schema(right_source, right, inputs, steps),
              parameters,
              {
                max_work: b.work,
                max_text_bytes: b.text,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(v) => v
            Err(issue) =>
              raise Stop({
                kind: Join(issue.kind),
                source: issue.source,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @join.cross_usage(checked)
          b.work -= used.work
          b.text -= used.text_bytes
          b.nodes -= used.nodes
          (CrossJoin(right~, checked~), @join.cross_output_schema(checked))
        } else if key == "except" || key == "intersect" {
          let obj = match @decode.open_object(operation_body) {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right_source = match @decode.required(obj, "with") {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, right_source, names)
          let checked = match
            @set.check(
              if key == "except" {
                Except
              } else {
                Intersect
              },
              operation_body,
              schema(operation_body, input, inputs, steps),
              schema(right_source, right, inputs, steps),
              {
                max_work: b.work,
                max_text_bytes: b.text,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(v) => v
            Err(issue) =>
              raise Stop({
                kind: Set(issue.kind),
                source: issue.source,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @set.usage(checked)
          b.work -= used.work
          b.text -= used.text_bytes
          b.nodes -= used.nodes
          (Set(right~, checked~), @set.output_schema(checked))
        } else if key == "nest" {
          let obj = match @decode.open_object(operation_body) {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right_source = match @decode.required(obj, "with") {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, right_source, names)
          let checked = match
            @nest.check(
              operation_body,
              schema(operation_body, input, inputs, steps),
              schema(right_source, right, inputs, steps),
              parameters,
              {
                max_work: b.work,
                max_text_bytes: b.text,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(v) => v
            Err(issue) =>
              raise Stop({
                kind: Nest(issue.kind),
                source: issue.source,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let usage = @nest.usage(checked)
          b.work -= usage.work
          b.text -= usage.text_bytes
          b.nodes -= usage.nodes
          (Nest(right~, checked~), @nest.output_schema(checked))
        } else if key == "append" {
          let obj = match @decode.open_object(operation_body) {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right_source = match @decode.required(obj, "with") {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, right_source, names)
          let checked = match
            @append.check(
              operation_body,
              schema(operation_body, input, inputs, steps),
              schema(right_source, right, inputs, steps),
              {
                max_work: b.work,
                max_text_bytes: b.text,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(v) => v
            Err(issue) =>
              raise Stop({
                kind: Append(issue.kind),
                source: issue.source,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let usage = @append.usage(checked)
          b.work -= usage.work
          b.text -= usage.text_bytes
          b.nodes -= usage.nodes
          (Append(right~, checked~), @append.output_schema(checked))
        } else {
          let obj = join_object.unwrap()
          let right_source = match @decode.required(obj, "with") {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, right_source, names)
          let checked = match
            @join.check(
              operation_body,
              schema(operation_body, input, inputs, steps),
              schema(right_source, right, inputs, steps),
              parameters,
              {
                max_work: b.work,
                max_text_bytes: b.text,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(v) => v
            Err(issue) =>
              raise Stop({
                kind: Join(issue.kind),
                source: issue.source,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let usage = @join.usage(checked)
          b.work -= usage.work
          b.text -= usage.text_bytes
          b.nodes -= usage.nodes
          (Join(right~, checked~), @join.output_schema(checked))
        }
    }
    let target = Step(steps.length())
    let connections : Connections = {
      entries: match checked {
        PropertyGraphConstruction(inputs~, ..) =>
          inputs.mapi((index, target) => { role: Sample(index), target, })
        Values(_) | TimeSeries(_) => []
        Calendar(_) | Pool(_) | Ranking(_) =>
          [{ role: Primary, target: input, }]
        Traverse(selector~, ..) => {
          let entries = [{ role: Primary, target: input, }]
          if selector is Some(t) {
            entries.push({ role: Right, target: t, })
          }
          entries
        }
        Unary(_)
        | Infer(_)
        | Window(_)
        | WindowGroup(_)
        | Projection(_)
        | GraphMatch(_)
        | Event(_)
        | Sequence(_)
        | Vector(_) => [{ role: Primary, target: input, }]
        Nearest(queries~, ..) | TextRank(queries~, ..) =>
          [{ role: Left, target: input, }, { role: Right, target: queries, }]
        Join(right~, ..)
        | Append(right~, ..)
        | Nest(right~, ..)
        | Set(right~, ..)
        | CrossJoin(right~, ..)
        | IntervalJoin(right~, ..)
        | AsOfJoin(right~, ..) =>
          [{ role: Left, target: input, }, { role: Right, target: right, }]
      },
    }
    steps.push({
      source: body,
      input: Some(input),
      binding_name,
      metadata: meta,
      operation: checked,
      output: @carrier.relation(@carrier.typed_rows(output)),
      connections,
      window: transfer_window(
        b, operation_body, input, steps, checked, produced_inputs,
      ),
    })
    if binding_name is Some(key) {
      names[key] = target
    }
    current = Some(target)
  }
  sync_delta(b, source, delta_inputs, steps, delta_steps)
  sync_keys(b, keyed_inputs, steps, keyed_steps, literal_inputs, literal_steps)
  sync_rankings(b, inputs, ranked_inputs, steps, ranked_steps)
  let join_evidence = derive_join_evidence(b, steps, keyed_inputs, keyed_steps)
  spend(b, source, produced_inputs.length())
  spend(b, source, produced_inputs.length())
  let (row_counts, graph_counts) = derive_row_counts(
    b, steps, join_evidence, produced_inputs,
  )
  spend(b, source, produced_inputs.length())
  let input_orders = imported_orders(produced_inputs)
  let (logical_orders, lag_orders, analytic_orders) = derive_logical_orders(
    b, steps, keyed_inputs, keyed_steps, input_orders, join_evidence,
  )
  {
    input_orders,
    input_contracts,
    produced_inputs,
    logical_orders,
    lag_orders,
    analytic_orders,
    graph_counts,
    join_evidence,
    row_counts,
    ranked_inputs,
    ranked_steps,
    keyed_inputs,
    keyed_steps,
    literal_inputs,
    literal_steps,
    delta_inputs,
    delta_steps,
    source,
    inputs,
    steps,
    names,
    current,
    output: current.map(target => carrier(target, inputs, steps)),
    initial_from: from,
    parameters,
    usage: {
      work: limits.max_work - b.work,
      text_bytes: limits.max_text_bytes - b.text,
      nodes: limits.max_nodes - b.nodes,
      tokens: limits.max_tokens - b.tokens,
    },
  }
}

///|
fn resolve_target(
  b : Budget,
  source : @decode.Cursor,
  names : Map[String, Target],
) -> Target raise Stop {
  let name = read_name(b, source)
  match names.get(name) {
    Some(v) => v
    None => fail(source, UnknownName(name))
  }
}

///|
/// Inputs are resolved materialized Relations, never search-template bindings.
/// Source is the normalized steps array; from is the optional stage selector.
pub fn check(
  source : @decode.Cursor,
  inputs : Array[(String, @schema.Schema)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile? : @calendar_profile.Profile? = None,
  text_rank_profile? : @text_rank_profile.Profile? = None,
  delta_contracts? : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ] = [],
  model_tasks? : @model_environment.ModelTasks? = None,
) -> Result[CheckedPipeline, Issue] {
  check_carriers(
    source,
    inputs.map(pair => (pair.0, @carrier.relation(@carrier.typed_rows(pair.1)))),
    parameters,
    from,
    limits,
    calendar_profile~,
    text_rank_profile~,
    delta_contracts~,
    model_tasks~,
  )
}

///|
/// Structural Carrier inputs carry no implicit runtime, ordering or uniqueness
/// proof. Existing Relation operations require complete row type information.
pub fn check_carriers(
  source : @decode.Cursor,
  inputs : Array[(String, @carrier.Carrier)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile? : @calendar_profile.Profile? = None,
  text_rank_profile? : @text_rank_profile.Profile? = None,
  delta_contracts? : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ] = [],
  model_tasks? : @model_environment.ModelTasks? = None,
) -> Result[CheckedPipeline, Issue] {
  Ok(
    check_impl(
      source,
      inputs,
      parameters,
      from,
      limits,
      calendar_profile,
      text_rank_profile,
      delta_contracts,
      inputs.map(_ => None),
      inputs.map(_ => None),
      inputs.map(_ => None),
      inputs.map(pair => CarrierInput(pair.1)),
      model_tasks,
    ),
  ) catch {
    Stop(issue) => Err(issue)
  }
}

///|
/// Keyed inputs retain conditional admission assertions, not runtime proof.
pub fn check_with_evidence(
  source : @decode.Cursor,
  inputs : Array[(String, InputContract)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile? : @calendar_profile.Profile? = None,
  text_rank_profile? : @text_rank_profile.Profile? = None,
  delta_contracts? : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ] = [],
  model_tasks? : @model_environment.ModelTasks? = None,
) -> Result[CheckedPipeline, Issue] {
  let carriers = inputs.map(pair => {
    (
      pair.0,
      match pair.1 {
        ProducedInput(p) => p.carrier
        SourceViewInput(_, _, _, owner) =>
          @model_environment.carrier_schema_value(
            @model_environment.source_view_carrier_schema(owner),
          )
        CarrierInput(c) => c
        KeyedInput(k) => @carrier.relation(@evidence.keyed_records(k))
        CandidateKeysInput(k) => @carrier.relation(@evidence.key_set_records(k))
        RankingInput(r) => @vector.ranking_input_carrier(r)
        RelationEvidenceInput(e) => @vector.ranking_input_carrier(e.ranking)
      },
    )
  })
  let keys = inputs.map(pair => {
    match pair.1 {
      ProducedInput(p) => p.keys
      SourceViewInput(_, _, _, _) | CarrierInput(_) | RankingInput(_) => None
      KeyedInput(k) => Some(@evidence.singleton_key(k))
      CandidateKeysInput(k) => Some(k)
      RelationEvidenceInput(e) => Some(e.keys)
    }
  })
  let rankings = inputs.map(pair => {
    match pair.1 {
      ProducedInput(p) => p.ranking
      RankingInput(r) => Some(r)
      RelationEvidenceInput(e) => Some(e.ranking)
      _ => None
    }
  })
  Ok(
    check_impl(
      source,
      carriers,
      parameters,
      from,
      limits,
      calendar_profile,
      text_rank_profile,
      delta_contracts,
      keys,
      rankings,
      inputs.map(pair => {
        match pair.1 {
          ProducedInput(p) => Some(p)
          _ => None
        }
      }),
      inputs.map(pair => pair.1),
      model_tasks,
    ),
  ) catch {
    Stop(issue) => Err(issue)
  }
}
