///|
priv enum MergeWork {
  Pair(Int, Int, Int)
  SequenceEnd(Bool, Int64?)
  ProductEnd(Bool, Array[String])
}

///|
fn upper(a : Int64?, b : Int64?) -> Int64? {
  match (a, b) {
    (Some(x), Some(y)) => Some(if x > y { x } else { y })
    _ => None
  }
}

///|
// Compute a common partial type without modifying peer evidence. Only after
// the whole group has a common shape does provide fill its unresolved holes.
fn merge(
  t : Types,
  a : Int,
  b : Int,
  source : @decode.Cursor,
) -> Int raise Stop {
  let work = [Pair(a, b, 0)]
  let results : Array[Int] = []
  while work.pop() is Some(task) {
    spend(t.budget, source)
    match task {
      Pair(a, b, depth) => {
        if depth > t.budget.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        let (x, xn) = head(t, a, source)
        let (y, yn) = head(t, b, source)
        let nullable = xn || yn
        match (t.entries[x].kind, t.entries[y].kind) {
          (Hole, Hole) => results.push(put(t, Hole, nullable, source))
          (Hole, kind) | (kind, Hole) =>
            results.push(put(t, kind, nullable, source))
          (Sequence(xi, xb), Sequence(yi, yb)) => {
            work.push(SequenceEnd(nullable, upper(xb, yb)))
            work.push(Pair(xi, yi, depth + 1))
          }
          (Product(xs), Product(ys)) => {
            if xs.length() != ys.length() {
              fail(source, TypeMismatch("object field sets"))
            }
            spend(t.budget, source, amount=xs.length())
            let names : Array[String] = []
            for i in 0..<xs.length() {
              if xs[i].0 != ys[i].0 {
                fail(source, TypeMismatch("object field sets"))
              }
              names.push(xs[i].0)
            }
            work.push(ProductEnd(nullable, names))
            for i = xs.length() - 1; i >= 0; i = i - 1 {
              work.push(Pair(xs[i].1, ys[i].1, depth + 1))
            }
          }
          (Leaf(xc), Leaf(yc)) => {
            let common = @contract.join_nullability(xc, yc, 1) catch {
              _ => fail(source, BudgetExceeded)
            }
            match common {
              Some(value) =>
                results.push(
                  put(
                    t,
                    Leaf(@contract.with_nullability(value, nullable)),
                    nullable,
                    source,
                  ),
                )
              None => fail(source, TypeMismatch("compatible peer types"))
            }
          }
          _ => fail(source, TypeMismatch("compatible peer types"))
        }
      }
      SequenceEnd(nullable, bound) =>
        results.push(
          put(t, Sequence(results.pop().unwrap(), bound), nullable, source),
        )
      ProductEnd(nullable, names) => {
        let fields : Array[(String, Int)] = []
        for i = names.length() - 1; i >= 0; i = i - 1 {
          fields.push((names[i], results.pop().unwrap()))
        }
        reverse_fields(fields)
        results.push(put(t, Product(fields), nullable, source))
      }
    }
  }
  results[0]
}

///|
fn provide(
  t : Types,
  value : Int,
  hint : Int,
  source : @decode.Cursor,
) -> Unit raise Stop {
  let work = [(value, hint, 0)]
  while work.pop() is Some((value, hint, depth)) {
    spend(t.budget, source)
    if depth > t.budget.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    let (v, _) = head(t, value, source)
    let (h, _) = head(t, hint, source)
    if v == h {
      continue
    }
    match (t.entries[v].kind, t.entries[h].kind) {
      (Hole, _) => t.entries[v].kind = Link(hint)
      (Sequence(vi, _), Sequence(hi, _)) => work.push((vi, hi, depth + 1))
      (Product(vs), Product(hs)) => {
        spend(t.budget, source, amount=vs.length())
        if vs.length() != hs.length() {
          fail(source, TypeMismatch("peer evidence shape"))
        }
        for i in 0..<vs.length() {
          if vs[i].0 != hs[i].0 {
            fail(source, TypeMismatch("peer evidence fields"))
          }
          work.push((vs[i].1, hs[i].1, depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn peers(
  t : Types,
  values : Array[Int],
  source : @decode.Cursor,
) -> Int raise Stop {
  if values.is_empty() {
    return put(t, Hole, false, source)
  }
  let mut common = values[0]
  for i in 1..<values.length() {
    common = merge(t, common, values[i], source)
  }
  for value in values {
    provide(t, value, common, source)
  }
  common
}

///|
priv enum ResolveWork {
  Enter(Int, Int)
  Exit(Int)
}

///|
// Only fully resolved types are cached. An unresolved type is never silently
// replaced by Json or a broad expected type from a downstream consumer.
fn resolve_type(
  t : Types,
  root : Int,
  source : @decode.Cursor,
) -> @contract.Contract raise Stop {
  let work = [Enter(root, 0)]
  while work.pop() is Some(task) {
    spend(t.budget, source)
    match task {
      Enter(id, depth) => {
        if depth > t.budget.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        let d = t.entries[id]
        if d.complete is Some(_) {
          if d.height > t.budget.limits.max_depth - depth {
            fail(source, BudgetExceeded)
          }
          continue
        }
        match d.kind {
          Hole => fail(source, NullTypeUnresolved)
          Leaf(c) =>
            d.complete = Some(@contract.with_nullability(c, d.nullable))
          Link(next) => {
            work.push(Exit(id))
            work.push(Enter(next, depth))
          }
          Sequence(item, _) => {
            work.push(Exit(id))
            work.push(Enter(item, depth + 1))
          }
          Product(fields) => {
            spend(t.budget, source, amount=fields.length())
            work.push(Exit(id))
            for i = fields.length() - 1; i >= 0; i = i - 1 {
              work.push(Enter(fields[i].1, depth + 1))
            }
          }
        }
      }
      Exit(id) => {
        let d = t.entries[id]
        let height = match d.kind {
          Link(next) => t.entries[next].height
          Sequence(item, _) => t.entries[item].height + 1
          Product(fields) => {
            let mut height = 0
            for (_, child) in fields {
              let child_height = t.entries[child].height + 1
              if child_height > height {
                height = child_height
              }
            }
            height
          }
          _ => 0
        }
        if height > t.budget.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        d.height = height
        let value = match d.kind {
          Link(next) => {
            let c = t.entries[next].complete.unwrap()
            @contract.with_nullability(c, d.nullable || c.nullable)
          }
          Sequence(item, bound) =>
            @contract.array_contract(
              t.entries[item].complete.unwrap(),
              nullable=d.nullable,
              max_items=bound,
            ).unwrap()
          Product(fields) => {
            let entries : Array[(String, @contract.Contract)] = []
            let mut bytes = 0
            for (name, child) in fields {
              spend(t.budget, source)
              let size = match @scalar.admit_utf8_length(name, t.budget.text) {
                Ok(n) => n
                Err(_) => fail(source, BudgetExceeded)
              }
              t.budget.text -= size
              if size > 2147483647 - bytes {
                fail(source, BudgetExceeded)
              }
              bytes += size
              entries.push((name, t.entries[child].complete.unwrap()))
            }
            match
              @contract.object_contract(
                entries,
                nullable=d.nullable,
                max_fields=entries.length(),
                max_name_bytes=bytes,
              ) {
              Ok(c) => c
              Err(_) => fail(source, TypeMismatch("canonical object contract"))
            }
          }
          _ => fail(source, TypeMismatch("type completion"))
        }
        d.complete = Some(value)
      }
    }
  }
  t.entries[root].complete.unwrap()
}

///|
fn constructor_safe(
  t : Types,
  root : Int,
  cache : Map[Int, Bool],
  source : @decode.Cursor,
) -> Bool raise Stop {
  let work = [Enter(root, 0)]
  while work.pop() is Some(task) {
    spend(t.budget, source)
    match task {
      Enter(id, depth) => {
        if cache.contains(id) {
          continue
        }
        if depth > t.budget.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        match t.entries[id].kind {
          Leaf(c) =>
            cache[id] = match c.shape {
              @contract.Json
              | @contract.ResourceRef(..)
              | @contract.ArtifactRef(..) => false
              _ => true
            }
          Hole => fail(source, NullTypeUnresolved)
          Link(next) => {
            work.push(Exit(id))
            work.push(Enter(next, depth))
          }
          Sequence(item, _) => {
            work.push(Exit(id))
            work.push(Enter(item, depth + 1))
          }
          Product(fields) => {
            spend(t.budget, source, amount=fields.length())
            work.push(Exit(id))
            for (_, item) in fields {
              work.push(Enter(item, depth + 1))
            }
          }
        }
      }
      Exit(id) =>
        cache[id] = match t.entries[id].kind {
          Link(next) | Sequence(next, _) => cache[next]
          Product(fields) => fields.all(f => cache[f.1])
          _ => false
        }
    }
  }
  cache[root]
}
