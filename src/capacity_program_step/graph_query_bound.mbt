///|
priv enum QueryCount {
  LiteralCount(Int64)
  InputCount(Int)
}

///|
priv struct QueryBound {
  inputs : Array[(@arithmetic.BoundUnit, Int)]
  left : QueryCount
  right : QueryCount
  selection : @graph.PathSelection
  clamp_left_to_right : Bool
}

///|
// At most three capacity operands are retained. Repeated selector edges remain
// distinct even when they point to the same relation or witness.
fn query_selector(
  selector : @graph.CheckedSelector,
  edge : Int,
  inputs : Array[(@arithmetic.BoundUnit, Int)],
) -> QueryCount {
  match @graph.selector_form(selector) {
    @graph.ExplicitIds =>
      LiteralCount(@graph.selector_id_count(selector).to_int64())
    @graph.RelationIds(..) => {
      let index = inputs.length()
      inputs.push((@arithmetic.Rows, edge))
      InputCount(index)
    }
    @graph.PredicateNodes => {
      for i, entry in inputs {
        if entry == (@arithmetic.Nodes, 0) {
          return InputCount(i)
        }
      }
      let index = inputs.length()
      inputs.push((@arithmetic.Nodes, 0))
      InputCount(index)
    }
  }
}

///|
fn query_endpoint(
  endpoint : @graph.PathEndpoint,
  edge : Int,
  inputs : Array[(@arithmetic.BoundUnit, Int)],
) -> QueryCount {
  match endpoint {
    @graph.Single(_) => LiteralCount(1L)
    @graph.Selected(selector) => query_selector(selector, edge, inputs)
  }
}

///|
fn traversal_bound(op : @graph.CheckedTraverse) -> QueryBound {
  let inputs = [(@arithmetic.Nodes, 0)]
  let left = query_selector(@graph.traverse_start(op), 1, inputs)
  {
    inputs,
    left,
    right: InputCount(0),
    selection: @graph.EachPair,
    clamp_left_to_right: true,
  }
}

///|
fn shortest_bound(
  op : @graph.CheckedShortest,
  source_relation : Bool,
) -> QueryBound {
  let selection = @graph.shortest_selection(op)
  let inputs = []
  // Nearest-pair returns at most one row independently of endpoint extent.
  if selection == @graph.NearestPair {
    return {
      inputs,
      left: LiteralCount(1L),
      right: LiteralCount(1L),
      selection,
      clamp_left_to_right: false,
    }
  }
  let left = query_endpoint(@graph.shortest_endpoint(op, Left), 1, inputs)
  // Nearest-per-source does not need a target count to prove this upper bound.
  let right = if selection == @graph.NearestPerSource {
    LiteralCount(1L)
  } else {
    query_endpoint(
      @graph.shortest_endpoint(op, Right),
      if source_relation {
        2
      } else {
        1
      },
      inputs,
    )
  }
  { inputs, left, right, selection, clamp_left_to_right: false, }
}

///|
fn query_bound_value(
  query : QueryBound,
  input : (Int) -> Int64,
) -> Result[Int64, Issue] {
  let read = fn(count) {
    match count {
      LiteralCount(n) => n
      InputCount(i) => input(i)
    }
  }
  let right = read(query.right)
  let raw_left = read(query.left)
  let left = if query.clamp_left_to_right && raw_left > right {
    right
  } else {
    raw_left
  }
  match query.selection {
    @graph.NearestPair => Ok(1L)
    @graph.NearestPerSource => Ok(left)
    @graph.EachPair =>
      match
        @numeric.multiply(
          @numeric.read(left).unwrap(),
          @numeric.read(right).unwrap(),
        ) {
        Ok(n) => Ok(@numeric.value(n))
        Err(_) => Err(BoundOverflow)
      }
  }
}
