///|
priv struct Budget {
  limits : Limits
  mut work : Int
  mut nodes : Int
  mut text : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(c : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    kind,
    path: @decode.cursor_path(c),
    span: @decode.cursor_span(c),
  })
}

///|
fn[T] decoded(result : Result[T, @decode.Issue]) -> T raise Stop {
  match result {
    Ok(v) => v
    Err(e) =>
      raise Stop({ kind: Decode(e.kind), path: e.path.copy(), span: e.span, })
  }
}

///|
fn spend(b : Budget, c : @decode.Cursor, n : Int) -> Unit raise Stop {
  if n > b.work {
    fail(c, BudgetExceeded)
  }
  b.work -= n
}

///|
fn charge(b : Budget, c : @decode.Cursor, text : String) -> Unit raise Stop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(n) => b.text -= n
    Err(_) => fail(c, BudgetExceeded)
  }
}

///|
fn scan(b : Budget, source : @decode.Cursor) -> Unit raise Stop {
  let stack = [(source, 0)]
  while stack.pop() is Some((c, depth)) {
    if b.nodes == 0 {
      fail(c, BudgetExceeded)
    }
    b.nodes -= 1
    spend(b, c, 1)
    match @decode.view(c) {
      TextValue(text) => charge(b, c, text)
      ArrayValue(xs) => {
        if depth >= b.limits.max_depth || xs.length() > b.nodes {
          fail(c, BudgetExceeded)
        }
        for x in xs.rev_iter() {
          stack.push((x, depth + 1))
        }
      }
      ObjectValue(obj) => {
        let keys = decoded(@decode.object_field_names(c))
        if depth >= b.limits.max_depth || keys.length() > b.nodes {
          fail(c, BudgetExceeded)
        }
        for key in keys.rev_iter() {
          charge(b, c, key)
          stack.push((@decode.lookup(obj, key).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
}
