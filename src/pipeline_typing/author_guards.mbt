///|
pub(all) enum GuardScope {
  JoinOutputRows
  CrossJoinOutputRows
  IntervalJoinOutputRows
  NestedArrayItems
  AggregateArrayItems(Int)
  AggregateStringBytes(Int)
  SequenceMatchesPerKey
  SequenceOutputRows
  ComponentOutputRows
  TraverseOutputRows
  ShortestOutputRows
} derive(Eq, Debug)

///|
/// An authored occurrence, not a bound value or a runnable capacity witness.
struct AuthorGuard {
  pipeline : CheckedPipeline
  step : Int
  scope : GuardScope
  value : @relation.CountValue
  source : @decode.Cursor
}

///|
struct AuthorGuards {
  pipeline : CheckedPipeline
  entries : Array[AuthorGuard]
  work : Int
  text : Int
}

///|
pub fn author_guard_pipeline(v : AuthorGuard) -> CheckedPipeline {
  v.pipeline
}

///|
pub fn author_guard_step(v : AuthorGuard) -> Int {
  v.step
}

///|
pub fn author_guard_scope(v : AuthorGuard) -> GuardScope {
  v.scope
}

///|
pub fn author_guard_value(v : AuthorGuard) -> @relation.CountValue {
  v.value
}

///|
pub fn author_guard_source(v : AuthorGuard) -> @decode.Cursor {
  v.source
}

///|
pub fn author_guards_pipeline(v : AuthorGuards) -> CheckedPipeline {
  v.pipeline
}

///|
pub fn author_guard_count(v : AuthorGuards) -> Int {
  v.entries.length()
}

///|
pub fn author_guard_at(v : AuthorGuards, index : Int) -> AuthorGuard? {
  v.entries.get(index)
}

///|
pub fn author_guards_usage(v : AuthorGuards) -> (Int, Int) {
  (v.work, v.text)
}

///|
fn graph_guard(value : @graph.Count?) -> @relation.CountValue? {
  value.map(v => {
    match v {
      Literal(n) => @relation.Literal(n)
      Parameter(s) => @relation.Parameter(s)
    }
  })
}

///|
fn join_guard(value : @join.Guard?) -> @relation.CountValue? {
  value.map(v => {
    match v {
      Literal(n) => @relation.Literal(n)
      Parameter(s) => @relation.Parameter(s)
    }
  })
}

///|
/// Enumerate every local step, including unused branches. Upstream pipelines
/// retain their own occurrences and must be visited by the combined checker.
pub fn collect_author_guards(
  p : CheckedPipeline,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[AuthorGuards, Issue] {
  try {
    if max_work < 0 || max_text_bytes < 0 {
      fail(p.source, InvalidLimits)
    }
    let b : Budget = {
      limits: {
        max_steps: 0,
        max_work,
        max_text_bytes,
        max_nodes: 0,
        max_tokens: 0,
        max_depth: 0,
      },
      work: max_work,
      text: max_text_bytes,
      nodes: 0,
      tokens: 0,
    }
    spend(b, p.source, p.steps.length())
    let entries : Array[AuthorGuard] = []
    for index, step in p.steps {
      let add = fn(
        scope : GuardScope,
        value : @relation.CountValue?,
        source : @decode.Cursor,
        field : String,
      ) raise Stop {
        if value is Some(value) {
          spend(b, source, 1)
          charge(b, source, field)
          if value is Parameter(name) {
            charge(b, source, name)
          }
          let object = match @decode.open_object(source) {
            Ok(o) => o
            Err(_) => fail(source, InvalidBody)
          }
          let cursor = match @decode.lookup(object, field) {
            Some(c) => c
            None => fail(source, InvalidBody)
          }
          entries.push({
            pipeline: p,
            step: index,
            scope,
            value,
            source: cursor,
          })
        }
      }
      match step.operation {
        Join(checked~, ..) =>
          add(
            JoinOutputRows,
            join_guard(@join.output_guard(checked)),
            @join.source(checked),
            "max_output_rows",
          )
        CrossJoin(checked~, ..) =>
          add(
            CrossJoinOutputRows,
            join_guard(@join.cross_output_guard(checked)),
            @join.cross_source(checked),
            "max_output_rows",
          )
        IntervalJoin(checked~, ..) =>
          add(
            IntervalJoinOutputRows,
            join_guard(@join.interval_output_guard(checked)),
            @join.interval_source(checked),
            "max_output_rows",
          )
        Nest(checked~, ..) => {
          let value = @nest.item_guard(checked).map(v => {
            match v {
              Literal(n) => @relation.Literal(n)
              Parameter(s) => @relation.Parameter(s)
            }
          })
          add(NestedArrayItems, value, @nest.source(checked), "max_items")
        }
        Sequence(checked) => {
          add(
            SequenceMatchesPerKey,
            @relation.sequence_per_key_guard(checked),
            @relation.sequence_source(checked),
            "max_matches_per_key",
          )
          add(
            SequenceOutputRows,
            @relation.sequence_output_guard(checked),
            @relation.sequence_source(checked),
            "max_output_rows",
          )
        }
        Graph(checked) =>
          match @graph.options(checked) {
            ComponentOptions(_, max_output_rows~) =>
              add(
                ComponentOutputRows,
                graph_guard(max_output_rows),
                @graph.source(checked),
                "max_output_rows",
              )
            _ => ()
          }
        Traverse(checked~, ..) =>
          add(
            TraverseOutputRows,
            graph_guard(@graph.traverse_output_guard(checked)),
            @graph.traverse_source(checked),
            "max_output_rows",
          )
        Shortest(checked~, ..) =>
          add(
            ShortestOutputRows,
            graph_guard(@graph.shortest_output_guard(checked)),
            @graph.shortest_source(checked),
            "max_output_rows",
          )
        Unary(op) | WindowGroup(op) =>
          if @relation.group(op) is Some(group) {
            spend(b, @relation.source(op), @relation.aggregate_count(group))
            for i in 0..<@relation.aggregate_count(group) {
              let aggregate = @relation.aggregate_at(group, i).unwrap()
              add(
                AggregateArrayItems(i),
                @relation.aggregate_item_limit(aggregate),
                @relation.aggregate_source(aggregate),
                "max_items",
              )
              add(
                AggregateStringBytes(i),
                @relation.aggregate_byte_limit(aggregate),
                @relation.aggregate_source(aggregate),
                "max_bytes",
              )
            }
          }
        _ => ()
      }
    }
    Ok({
      pipeline: p,
      entries,
      work: max_work - b.work,
      text: max_text_bytes - b.text,
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}
