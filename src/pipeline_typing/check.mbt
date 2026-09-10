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
    if names.contains(key) {
      fail(source, DuplicateName(key))
    }
    carrier_preflight(b, source, schema)
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
  for body in bodies {
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
      | "degree"
      | "components"
      | "graph_bounds"
      | "vectors"
      | "window_events" => None
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
        @join.check_asof(
          operation_body,
          carrier(input, inputs, steps),
          carrier(right, inputs, steps),
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
    if key == "normalize_graph" ||
      key == "degree" ||
      key == "components" ||
      key == "graph_bounds" {
      let operation = match key {
        "degree" => @graph.Degree
        "components" => @graph.Components
        "graph_bounds" => @graph.GraphBounds
        _ => @graph.NormalizeGraph
      }
      let checked = match
        @graph.check(
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
            kind: Graph(e.kind),
            source: operation_body,
            path: e.path.copy(),
            span: e.span,
            range: None,
          })
      }
      let used = @graph.usage(checked)
      b.work -= used.work
      b.nodes -= used.nodes
      b.text -= used.text_bytes
      let target = Step(steps.length())
      steps.push({
        source: body,
        input: Some(input),
        binding_name,
        metadata: meta,
        operation: Graph(checked),
        output: @graph.output(checked),
        connections: { entries: [{ role: Primary, target: input, }], },
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
      let window = transfer_window(b, operation_body, input, steps, operation)
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
    if key == "events" || key == "vectors" {
      let projection = if key == "events" {
        @projection.Events
      } else {
        @projection.Vectors
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
      let window = transfer_window(b, operation_body, input, steps, operation)
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
        let input_schema = schema(operation_body, input, inputs, steps)
        let operation_limits : @relation.Limits = {
          max_work: b.work,
          max_text_bytes: b.text,
          max_nodes: b.nodes,
          max_tokens: b.tokens,
          max_depth: limits.max_depth,
        }
        let result = if key == "window_group" {
          let evidence = match input {
            Step(i) => steps[i].window
            Input(_) => None
          }
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
        Values(_) | TimeSeries(_) => []
        Unary(_)
        | Window(_)
        | WindowGroup(_)
        | Projection(_)
        | Graph(_)
        | Event(_)
        | Vector(_) => [{ role: Primary, target: input, }]
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
      window: transfer_window(b, operation_body, input, steps, checked),
    })
    if binding_name is Some(key) {
      names[key] = target
    }
    current = Some(target)
  }
  {
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
) -> Result[CheckedPipeline, Issue] {
  check_carriers(
    source,
    inputs.map(pair => (pair.0, @carrier.relation(@carrier.typed_rows(pair.1)))),
    parameters,
    from,
    limits,
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
) -> Result[CheckedPipeline, Issue] {
  Ok(check_impl(source, inputs, parameters, from, limits)) catch {
    Stop(issue) => Err(issue)
  }
}
