///|
/// One bounded kernel response. Work is the actual physical work consumed by
/// this resume and may not exceed the admitted quantum. Progress is monotonic
/// diagnostic progress, not a semantic row count or budget credit.
pub(all) enum KernelStep[T, E] {
  Continue(Int, Int)
  Complete(T, Int, Int)
  Failed(E, Int, Int)
  Stopped(StopReason, Int, Int)
}

///|
struct Token {
  owner : Ref[Unit]
  ordinal : Int64
}

///|
pub enum Observation[T, E] {
  ContinueWith(Token, progress~ : Int64, work~ : Int64)
  Completed(T, progress~ : Int64, work~ : Int64)
  FailedWith(E, progress~ : Int64, work~ : Int64)
  StoppedWith(StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum Issue {
  InvalidQuantum
  ForeignToken
  ConcurrentResume
  Terminal
  InvalidKernelReport
  CounterOverflow
  NotStopped
} derive(Eq, Debug)

///|
/// Private non-serializable kernel state. A terminal session is stopped before
/// cleanup begins; cleanup may remain pending and be retried independently.
struct Session[S, T, E] {
  identity : Ref[Unit]
  reader : Reader
  state : S
  advance : (S, Int, Reader) -> KernelStep[T, E]
  cleanup : (S) -> Bool
  mut ordinal : Int64
  mut progress : Int64
  mut work : Int64
  mut running : Bool
  mut terminal : Bool
  mut stopped : Bool
  mut reclaimed : Bool
}

///|
/// Start is constant common work. Kernel-specific initial state supplied here
/// must itself be small; large initialization belongs in bounded resume steps.
pub fn[S, T, E] start(
  control : Control,
  state : S,
  advance : (S, Int, Reader) -> KernelStep[T, E],
  cleanup : (S) -> Bool,
) -> (Session[S, T, E], Token) {
  let identity = Ref(())
  let session = {
    identity,
    reader: { control, },
    state,
    advance,
    cleanup,
    ordinal: 0L,
    progress: 0L,
    work: 0L,
    running: false,
    terminal: false,
    stopped: false,
    reclaimed: false,
  }
  (session, { owner: identity, ordinal: 0L, })
}

///|
fn[S, T, E] matching_token(session : Session[S, T, E], token : Token) -> Bool {
  physical_equal(session.identity, token.owner) &&
  session.ordinal == token.ordinal
}

///|
fn add_counter(current : Int64, delta : Int) -> Int64? {
  if delta < 0 || delta.to_int64() > 9223372036854775807L - current {
    None
  } else {
    Some(current + delta.to_int64())
  }
}

///|
fn[S, T, E] stop_observation(
  session : Session[S, T, E],
  reason : StopReason,
) -> Observation[T, E] {
  session.terminal = true
  session.stopped = true
  StoppedWith(reason, progress=session.progress, work=session.work)
}

///|
pub fn[S, T, E] advance(
  session : Session[S, T, E],
  token : Token,
  work_quanta : Int,
) -> Result[Observation[T, E], Issue] {
  if work_quanta <= 0 {
    return Err(InvalidQuantum)
  }
  if session.running {
    return Err(ConcurrentResume)
  }
  if session.terminal {
    return Err(Terminal)
  }
  if !matching_token(session, token) {
    return Err(ForeignToken)
  }
  if session.ordinal == 9223372036854775807L {
    session.terminal = true
    session.stopped = true
    return Err(CounterOverflow)
  }
  session.ordinal += 1L
  if stop_requested(session.reader) is Some(reason) {
    return Ok(stop_observation(session, reason))
  }
  session.running = true
  let result = (session.advance)(session.state, work_quanta, session.reader)
  session.running = false
  let (progress, work) = match result {
    Continue(progress, work)
    | Complete(_, progress, work)
    | Failed(_, progress, work)
    | Stopped(_, progress, work) => (progress, work)
  }
  if work < 0 || work > work_quanta || progress < 0 || result is Continue(0, 0) {
    session.terminal = true
    session.stopped = true
    return Err(InvalidKernelReport)
  }
  guard add_counter(session.progress, progress) is Some(total_progress) &&
    add_counter(session.work, work) is Some(total_work) else {
    session.terminal = true
    session.stopped = true
    return Err(CounterOverflow)
  }
  session.progress = total_progress
  session.work = total_work
  if stop_requested(session.reader) is Some(reason) {
    return Ok(stop_observation(session, reason))
  }
  match result {
    Continue(_, _) =>
      Ok(
        ContinueWith(
          { owner: session.identity, ordinal: session.ordinal, },
          progress=session.progress,
          work=session.work,
        ),
      )
    Complete(value, _, _) => {
      session.terminal = true
      session.stopped = true
      Ok(Completed(value, progress=session.progress, work=session.work))
    }
    Failed(issue, _, _) => {
      session.terminal = true
      session.stopped = true
      Ok(FailedWith(issue, progress=session.progress, work=session.work))
    }
    Stopped(reason, _, _) => Ok(stop_observation(session, reason))
  }
}

///|
pub fn[S, T, E] session_stopped(session : Session[S, T, E]) -> Bool {
  session.stopped && !session.running
}

///|
pub fn[S, T, E] cleanup_pending(session : Session[S, T, E]) -> Bool {
  session.stopped && !session.reclaimed
}

///|
/// Cleanup can fail or remain pending after stop confirmation. A successful
/// retry closes reclamation exactly once without changing terminal outcome.
pub fn[S, T, E] cleanup(session : Session[S, T, E]) -> Result[Bool, Issue] {
  if !session_stopped(session) {
    return Err(NotStopped)
  }
  if session.reclaimed {
    return Ok(false)
  }
  if (session.cleanup)(session.state) {
    session.reclaimed = true
    Ok(true)
  } else {
    Ok(false)
  }
}
