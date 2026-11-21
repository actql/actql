///|
pub(all) struct SearchOptions {
  from : Int
  multiline : Bool
  dot_all : Bool
  max_entries : Int
} derive(Eq, Debug)

///|
pub(all) enum SearchIssue {
  InvalidSearchOptions
  MalformedInput(Int)
  SearchWorkspaceLimit
} derive(Eq, Debug)

///|
/// Bounds index the original admitted UTF-16 String.
pub(all) struct Span {
  start : Int
  end : Int
} derive(Eq, Debug)

///|
struct Match {
  span : Span
  captures : Array[Span?]
}

///|
pub fn match_span(value : Match) -> Span {
  value.span
}

///|
pub fn capture_span(value : Match, capture : Int) -> Span? {
  if capture == 0 {
    return Some(value.span)
  }
  if capture <= 0 {
    return None
  }
  value.captures.get(capture - 1).bind(span => span)
}

///|
priv enum Task {
  Apply(Int)
  SequenceAt(Int, Int)
  BranchAt(Int, Int)
  RepeatAt(Int, Int64)
  EndCapture(Int, Int)
  ClassAt(Int, Int, Int, Int)
}

///|
priv struct Continuation {
  task : Task
  next : Int
}

///|
priv struct Choice {
  position : Int
  continuation : Int
  mark : Int
}

///|
priv struct Mark {
  index : Int
  span : Span
  previous : Int
}

///|
priv enum SearchPhase {
  Start
  Execute
  AllocateCaptures
  ResolveCaptures
  Done
}

///|
struct Search {
  pattern : Pattern
  text : String
  options : SearchOptions
  mut continuations : Array[Continuation]
  mut choices : Array[Choice]
  mut marks : Array[Mark]
  mut captures : Array[Span?]
  mut continuation_count : Int
  mut choice_count : Int
  mut mark_count : Int
  mut start : Int
  mut position : Int
  mut continuation : Int
  mut mark : Int
  mut phase : SearchPhase
}

///|
pub enum SearchPoll {
  SearchContinue
  SearchComplete(Match?)
  SearchFailed(SearchIssue)
  SearchTerminal
}

///|
/// The caller supplies the admitted input and owns the work charge for every
/// advance. The entry ceiling covers all four vectors, including result
/// captures while they overlap the search state.
pub fn start_search(
  pattern : Pattern,
  text : String,
  options : SearchOptions,
) -> Result[Search, SearchIssue] {
  if options.from < 0 || options.from > text.length() || options.max_entries < 0 {
    return Err(InvalidSearchOptions)
  }
  if options.from < text.length() {
    let unit = text[options.from].to_int()
    if unit >= 0xdc00 && unit <= 0xdfff {
      return Err(MalformedInput(options.from))
    }
  }
  Ok({
    pattern,
    text,
    options,
    continuations: [],
    choices: [],
    marks: [],
    captures: [],
    continuation_count: 0,
    choice_count: 0,
    mark_count: 0,
    start: options.from,
    position: options.from,
    continuation: -1,
    mark: -1,
    phase: Start,
  })
}

///|
priv suberror SearchStop {
  SearchStop(SearchIssue)
}

///|
fn reserve_entry(search : Search) -> Unit raise SearchStop {
  let used = search.continuations.length().to_int64() +
    search.choices.length().to_int64() +
    search.marks.length().to_int64() +
    search.captures.length().to_int64()
  if used >= search.options.max_entries.to_int64() {
    raise SearchStop(SearchWorkspaceLimit)
  }
}

///|
fn[T] store_entry(
  search : Search,
  entries : Array[T],
  index : Int,
  entry : T,
) -> Unit raise SearchStop {
  if index == entries.length() {
    reserve_entry(search)
    entries.push(entry)
  } else {
    entries[index] = entry
  }
}

///|
fn push_task(search : Search, task : Task, next : Int) -> Int raise SearchStop {
  let index = search.continuation_count
  store_entry(search, search.continuations, index, { task, next, })
  search.continuation_count += 1
  index
}

///|
fn prepend(search : Search, task : Task) -> Unit raise SearchStop {
  search.continuation = push_task(search, task, search.continuation)
}

///|
fn save_choice(search : Search, continuation : Int) -> Unit raise SearchStop {
  store_entry(search, search.choices, search.choice_count, {
    position: search.position,
    continuation,
    mark: search.mark,
  })
  search.choice_count += 1
}

///|
fn search_scalar(text : String, at : Int) -> (Int, Int) raise SearchStop {
  let unit = text[at].to_int()
  if unit >= 0xd800 && unit <= 0xdbff {
    guard text.get(at + 1) is Some(low) else {
      raise SearchStop(MalformedInput(at))
    }
    let low = low.to_int()
    guard low >= 0xdc00 && low <= 0xdfff else {
      raise SearchStop(MalformedInput(at))
    }
    (0x10000 + ((unit - 0xd800) << 10) + low - 0xdc00, at + 2)
  } else if unit >= 0xdc00 && unit <= 0xdfff {
    raise SearchStop(MalformedInput(at))
  } else {
    (unit, at + 1)
  }
}

///|
fn search_escape(escape : String, point : Int) -> Bool {
  let digit = point >= 48 && point <= 57
  let word = digit ||
    point == 95 ||
    (point >= 65 && point <= 90) ||
    (point >= 97 && point <= 122)
  let space = point == 32 || (point >= 9 && point <= 13)
  match escape {
    "d" => digit
    "D" => !digit
    "w" => word
    "W" => !word
    "s" => space
    "S" => !space
    _ => false
  }
}

///|
fn clear_attempt(search : Search) -> Unit {
  // All entries are scalar records. Keep their bounded storage and let the
  // next start overwrite each cell as it is reached.
  search.continuation_count = 0
  search.choice_count = 0
  search.mark_count = 0
  search.continuation = -1
  search.mark = -1
}

///|
pub fn Search::cancel(search : Search) -> Unit {
  clear_attempt(search)
  search.continuations = []
  search.choices = []
  search.marks = []
  search.captures = []
  search.phase = Done
}

///|
fn miss(search : Search) -> SearchPoll raise SearchStop {
  if search.choice_count > 0 {
    search.choice_count -= 1
    let choice = search.choices[search.choice_count]
    search.position = choice.position
    search.continuation = choice.continuation
    search.mark = choice.mark
    return SearchContinue
  }
  if search.start == search.text.length() {
    search.cancel()
    return SearchComplete(None)
  }
  let (_, next) = search_scalar(search.text, search.start)
  clear_attempt(search)
  search.start = next
  search.phase = Start
  SearchContinue
}

///|
fn choose_branch(
  search : Search,
  node : Int,
  branch : Int,
) -> Unit raise SearchStop {
  guard search.pattern.entries[node].node is Alternation(branches) else {
    abort("Non-alternation in regex branch continuation")
  }
  if branch + 1 < branches.length() {
    let next = push_task(
      search,
      BranchAt(node, branch + 1),
      search.continuation,
    )
    save_choice(search, next)
  }
  prepend(search, Apply(branches[branch]))
}

///|
fn repeat_at(
  search : Search,
  node : Int,
  count : Int64,
) -> SearchPoll raise SearchStop {
  guard search.pattern.entries[node].node is Repeat(minimum, maximum, child) else {
    abort("Non-repeat in regex repeat continuation")
  }
  // Every successful repetition consumes a scalar. A large bound remains
  // exact even when there cannot be enough input to reach it.
  let remaining = (search.text.length() - search.position).to_int64()
  if minimum > (count + remaining).to_double() {
    return miss(search)
  }
  if remaining == 0L || (maximum is Some(end) && count.to_double() == end) {
    return SearchContinue
  }
  if count.to_double() >= minimum {
    save_choice(search, search.continuation)
  }
  prepend(search, RepeatAt(node, count + 1L))
  prepend(search, Apply(child))
  SearchContinue
}

///|
fn class_at(
  search : Search,
  node : Int,
  item : Int,
  point : Int,
  next : Int,
) -> SearchPoll raise SearchStop {
  guard search.pattern.entries[node].node is CharacterClass(negative, items) else {
    abort("Non-class in regex class continuation")
  }
  match items.get(item) {
    None => if negative { search.position = next } else { return miss(search) }
    Some(candidate) => {
      let matched = match candidate {
        Scalar(value) => value == point
        Range(low, high) => low <= point && point <= high
        Escape(escape) => search_escape(escape, point)
      }
      if matched {
        if negative {
          return miss(search)
        }
        search.position = next
      } else {
        prepend(search, ClassAt(node, item + 1, point, next))
      }
    }
  }
  SearchContinue
}

///|
fn apply_node(search : Search, index : Int) -> SearchPoll raise SearchStop {
  let at = search.position
  let node = search.pattern.entries[index].node
  match node {
    Literal(_) | ClassEscape(_) | CharacterClass(_, _) | Dot => {
      if at == search.text.length() {
        return miss(search)
      }
      let (point, next) = search_scalar(search.text, at)
      let accepted = match node {
        Literal(value) => point == value
        ClassEscape(escape) => search_escape(escape, point)
        Dot => search.options.dot_all || point != 10
        CharacterClass(_, _) => {
          prepend(search, ClassAt(index, 0, point, next))
          return SearchContinue
        }
        _ => abort("Non-scalar in regex scalar branch")
      }
      if !accepted {
        return miss(search)
      }
      search.position = next
    }
    Anchor(kind) => {
      let accepted = if kind == "^" {
        at == 0 || (search.options.multiline && search.text[at - 1] == '\n')
      } else {
        at == search.text.length() ||
        (search.options.multiline && search.text[at] == '\n')
      }
      if !accepted {
        return miss(search)
      }
    }
    Sequence(_) => prepend(search, SequenceAt(index, 0))
    Alternation(_) => choose_branch(search, index, 0)
    Repeat(_, _, _) => return repeat_at(search, index, 0L)
    Capture(capture, inner) => {
      prepend(search, EndCapture(capture - 1, at))
      prepend(search, Apply(inner))
    }
  }
  SearchContinue
}

///|
fn run_task(search : Search, task : Task) -> SearchPoll raise SearchStop {
  match task {
    Apply(index) => return apply_node(search, index)
    RepeatAt(index, count) => return repeat_at(search, index, count)
    ClassAt(index, item, point, next) =>
      return class_at(search, index, item, point, next)
    BranchAt(index, branch) => choose_branch(search, index, branch)
    EndCapture(index, start) => {
      store_entry(search, search.marks, search.mark_count, {
        index,
        span: { start, end: search.position, },
        previous: search.mark,
      })
      search.mark = search.mark_count
      search.mark_count += 1
    }
    SequenceAt(index, position) => {
      guard search.pattern.entries[index].node is Sequence(items) else {
        abort("Non-sequence in regex sequence continuation")
      }
      if position + 1 < items.length() {
        prepend(search, SequenceAt(index, position + 1))
      }
      prepend(search, Apply(items[position]))
    }
  }
  SearchContinue
}

///|
fn advance_search(search : Search) -> SearchPoll raise SearchStop {
  match search.phase {
    Done => return SearchTerminal
    Start => {
      prepend(search, Apply(search.pattern.root))
      search.position = search.start
      search.phase = Execute
    }
    Execute =>
      if search.continuation < 0 {
        // A complete preferred path commits the match. Lower-priority
        // branches cannot be observed by capture assembly.
        search.phase = AllocateCaptures
      } else {
        let current = search.continuations[search.continuation]
        search.continuation = current.next
        return run_task(search, current.task)
      }
    AllocateCaptures =>
      if search.captures.length() < search.pattern.captures {
        reserve_entry(search)
        search.captures.push(None)
      } else {
        search.phase = ResolveCaptures
      }
    ResolveCaptures =>
      if search.mark < 0 {
        let result = {
          span: { start: search.start, end: search.position, },
          captures: search.captures,
        }
        search.cancel()
        return SearchComplete(Some(result))
      } else {
        let mark = search.marks[search.mark]
        if search.captures[mark.index] is None {
          search.captures[mark.index] = Some(mark.span)
        }
        search.mark = mark.previous
      }
  }
  SearchContinue
}

///|
/// Advance a single task, class item, source start, or retained capture.
pub fn Search::advance(search : Search) -> SearchPoll {
  advance_search(search) catch {
    SearchStop(issue) => {
      search.cancel()
      SearchFailed(issue)
    }
  }
}
