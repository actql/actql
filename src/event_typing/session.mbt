///|
struct SessionSpec {
  keys : Array[@row.FieldName]
  identity : @row.FieldName
  time : @row.FieldName
  timestamp : Bool
  gap : @temporal.Milliseconds
}

///|
pub fn session_keys(s : SessionSpec) -> Array[@row.FieldName] {
  s.keys.copy()
}

///|
pub fn session_identity(s : SessionSpec) -> @row.FieldName {
  s.identity
}

///|
pub fn session_time(s : SessionSpec) -> @row.FieldName {
  s.time
}

///|
pub fn session_timestamp(s : SessionSpec) -> Bool {
  s.timestamp
}

///|
pub fn session_gap(s : SessionSpec) -> @temporal.Milliseconds {
  s.gap
}

///|
pub fn check_session(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedEvent, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let relation = input is @carrier.Relation(_)
    let records = match input {
      @carrier.Relation(k) => k
      @carrier.EventValue(e) => e.records
      _ => fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let object = decoded(
      @decode.closed_object(
        source,
        if relation {
          ["id", "time", "by", "gap"]
        } else {
          ["by", "gap"]
        },
      ),
    )
    let (identity, time, timestamp) = match input {
      @carrier.EventValue(e) =>
        (
          e.identity.name,
          e.time.name,
          e.clock_encoding == @carrier.UtcTimestamp,
        )
      _ => {
        let id_source = decoded(@decode.required(object, "id"))
        let time_source = decoded(@decode.required(object, "time"))
        let id = role_name(id_source)
        let time = role_name(time_source)
        let events = match @carrier.events(records, id~, time~) {
          Ok(@carrier.EventValue(e)) => e
          Err(e) => {
            let at = match e {
              UnknownRole(name) | InvalidRole(name) =>
                if name == time {
                  time_source
                } else {
                  id_source
                }
              _ => source
            }
            fail(at, InvalidRole(e))
          }
          _ => fail(source, InvalidBody)
        }
        (id, time, events.clock_encoding == @carrier.UtcTimestamp)
      }
    }
    let by = decoded(@decode.elements(decoded(@decode.required(object, "by"))))
    spend(b, source, by.length() + 2)
    let keys = []
    for c in by {
      let key = role_name(c)
      let ty = field_contract(records, key, c)
      if !@contract.key_comparable(ty, ty) {
        fail(c, NotKeyComparable(@row.reference_name(key)))
      }
      keys.push(key)
    }
    let gap = match
      @temporal.read_milliseconds(
        decoded(@decode.required(object, "gap")),
        PositiveMilliseconds,
        parameters,
        {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
        },
      ) {
      Ok(v) => v
      Err(e) =>
        raise Stop({
          kind: Temporal(e.kind),
          path: e.path.copy(),
          span: e.span,
        })
    }
    let used = @temporal.milliseconds_usage(gap)
    b.work -= used.work
    b.nodes -= used.nodes
    b.text -= used.text_bytes
    let generated = [
      ("session_start_ms", @contract.NumberType),
      ("session_end_ms", @contract.NumberType),
      ("session_id", @contract.StringType),
    ]
    for (name, _) in generated {
      spend(b, source, 1)
      match @carrier.lookup(records, Unqualified(name)) {
        Absent => ()
        Present(_) => fail(source, OutputCollision(name))
        Unknown => fail(source, UnknownOutputFields)
      }
    }
    let fields = []
    let n = @carrier.field_count(records)
    spend(b, source, n)
    for i in 0..<n {
      let f = @carrier.field_at(records, i).unwrap()
      charge(b, source, @row.reference_name(f.name))
      fields.push((f.name, f.contract))
    }
    for (name, kind) in generated {
      charge(b, source, name)
      fields.push(
        (Unqualified(name), Some(@contract.primitive(kind, nullable=false))),
      )
    }
    let rows = match
      @carrier.rows(
        fields,
        field_set=@carrier.field_set(records),
        max_fields=fields.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(r) => r
      Err(_) => fail(source, BudgetExceeded)
    }
    let output = if relation {
      @carrier.relation(rows)
    } else {
      match @carrier.events(rows, id=identity, time~) {
        Ok(c) => c
        Err(_) => fail(source, InvalidBody)
      }
    }
    Ok({
      source,
      input,
      output,
      options: Session({
        keys,
        identity,
        time,
        timestamp,
        gap: @temporal.milliseconds_value(gap),
      }),
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}
