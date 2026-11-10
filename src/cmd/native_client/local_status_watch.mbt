///|
// Observation-only command options. These durations issue no resource budget,
// execution permission, cancellation, progress or cleanup acknowledgement.
priv struct LocalStatusWatchOptions {
  watch : Bool
  final_only : Bool
  timeout_ms : Int64
}

///|
fn local_status_duration(text : String) -> Int64 raise ClientStop {
  let (body, factor) = if text.has_suffix("ms") {
    (text[:text.length() - 2].to_owned(), 1L)
  } else if text.has_suffix("s") {
    (text[:text.length() - 1].to_owned(), 1000L)
  } else if text.has_suffix("m") {
    (text[:text.length() - 1].to_owned(), 60000L)
  } else if text.has_suffix("h") {
    (text[:text.length() - 1].to_owned(), 3600000L)
  } else {
    (text, 1000L)
  }
  let mut whole = 0L
  let mut fraction = 0L
  let mut scale = 1L
  let mut decimal = false
  let mut whole_digits = 0
  let mut fraction_digits = 0
  for ch in body {
    if ch == '.' && !decimal {
      decimal = true
    } else if ch >= '0' && ch <= '9' {
      let digit = (ch.to_int() - '0'.to_int()).to_int64()
      if decimal {
        if fraction_digits >= 9 {
          stop("InvalidLocalStatusTimeout")
        }
        fraction = fraction * 10L + digit
        scale *= 10L
        fraction_digits += 1
      } else {
        if whole > (9223372036854775807L - digit) / 10L {
          stop("InvalidLocalStatusTimeout")
        }
        whole = whole * 10L + digit
        whole_digits += 1
      }
    } else {
      stop("InvalidLocalStatusTimeout")
    }
  }
  if whole_digits == 0 ||
    (decimal && fraction_digits == 0) ||
    whole > 9223372036854775807L / factor {
    stop("InvalidLocalStatusTimeout")
  }
  let scaled_fraction = fraction * factor
  if scaled_fraction % scale != 0L {
    stop("InvalidLocalStatusTimeout")
  }
  let tail = scaled_fraction / scale
  let head = whole * factor
  if head > 9223372036854775807L - tail || head + tail <= 0L {
    stop("InvalidLocalStatusTimeout")
  }
  head + tail
}

///|
fn local_status_watch_options(
  child : @argparse.Matches,
) -> LocalStatusWatchOptions? raise ClientStop {
  let watch = child.flags.get("watch").unwrap_or(false)
  let until = optional(child, "until")
  let timeout = optional(child, "timeout")
  if !watch && until is None && timeout is None {
    return None
  }
  if until is Some(_) && !watch {
    stop("LocalStatusUntilRequiresWatch")
  }
  if until is Some(value) && value != "final" {
    stop("InvalidLocalStatusUntil")
  }
  if optional(child, "run") is None && optional(child, "run-id") is None {
    stop("LocalStatusWatchRequiresRunId")
  }
  Some({
    watch,
    final_only: until is Some(_),
    timeout_ms: local_status_duration(timeout.unwrap_or("30s")),
  })
}

///|
// The existing Host supplies actual saved originals/current. Private test
// callbacks exercise polling/output failures; no callback issues a Run state.
priv struct LocalStatusWatchOperations {
  read_original : () -> String raise ClientStop
  current : () -> Bool
  now_ms : () -> Int64
  pause_ms : (Int) -> Bool
  interrupted : () -> Bool
  progress : (String) -> Bool raise ClientStop
}

///|
fn local_status_watch_deadline(
  operations : LocalStatusWatchOperations,
  start : Int64,
  last : Int64,
  timeout : Int64,
) -> Int64 raise ClientStop {
  if (operations.interrupted)() {
    stop("WaitAborted")
  }
  let now = (operations.now_ms)()
  if now < 0L || now < last || now < start {
    stop("LocalStatusClockUnavailable")
  }
  if now - start >= timeout {
    stop("WaitTimeout")
  }
  now
}

///|
fn local_status_watch_loop(
  options : LocalStatusWatchOptions,
  operations : LocalStatusWatchOperations,
) -> String raise ClientStop {
  let start = (operations.now_ms)()
  if start < 0L {
    stop("LocalStatusClockUnavailable")
  }
  let mut last = start
  let mut prior_revision : Int64? = None
  let mut original_id : String? = None
  while true {
    last = local_status_watch_deadline(
      operations,
      start,
      last,
      options.timeout_ms,
    )
    if !(operations.current)() {
      stop("LocalRunStateReadAuthorizationDenied")
    }
    let wire = (operations.read_original)()
    last = local_status_watch_deadline(
      operations,
      start,
      last,
      options.timeout_ms,
    )
    if !(operations.current)() {
      stop("LocalRunStateReadAuthorizationDenied")
    }
    // Reuse the full public-state validator and original stable-state rule.
    // Missing legacy state/revision never becomes a fresh counter or progress.
    let ready = @publication.run_wait_ready_until(
      wire,
      None,
      if options.final_only {
        @publication.Final
      } else {
        @publication.Stable
      },
      65536,
      8192,
      64,
    ).unwrap_or_else(() => stop("LocalOriginalRunStateUnavailable"))
    let object = local_run_display_object(local_input_cursor(wire))
    let id = local_run_display_text(local_run_display_field(object, "run_id"))
    let revision = @decode.safe_integer(
      local_run_display_field(object, "revision"),
    ).unwrap_or_else(() => stop("LocalOriginalRunStateUnavailable"))
    if original_id is Some(expected) && id != expected {
      stop("LocalOriginalRunReferenceMismatch")
    }
    if prior_revision is Some(prior) && revision < prior {
      stop("LocalRunStateRevisionRegressed")
    }
    original_id = Some(id)
    if !options.watch || ready {
      if !(operations.current)() {
        stop("LocalRunStateReadAuthorizationDenied")
      }
      return wire
    }
    if prior_revision is None || prior_revision != Some(revision) {
      if !(operations.progress)(wire) {
        stop("LocalStatusProgressWriteFailed")
      }
      if !(operations.current)() {
        stop("LocalRunStateReadAuthorizationDenied")
      }
    }
    prior_revision = Some(revision)
    last = local_status_watch_deadline(
      operations,
      start,
      last,
      options.timeout_ms,
    )
    let remaining = options.timeout_ms - (last - start)
    let quantum = if remaining < 100L { remaining.to_int() } else { 100 }
    if !(operations.pause_ms)(quantum) {
      stop("LocalStatusWaitUnavailable")
    }
  }
  abort("unreachable status watch loop")
}

///|
extern "C" fn local_status_watch_begin_ffi() -> Bool = "actql_native_client_status_watch_begin"

///|
extern "C" fn local_status_watch_end_ffi() -> Bool = "actql_native_client_status_watch_end"

///|
extern "C" fn local_status_watch_interrupted_ffi() -> Bool = "actql_native_client_status_watch_interrupted"

///|
extern "C" fn local_status_watch_now_ffi() -> Int64 = "actql_native_client_status_watch_now"

///|
extern "C" fn local_status_watch_pause_ffi(milliseconds : Int) -> Bool = "actql_native_client_status_watch_pause"

///|
#borrow(bytes)
extern "C" fn local_status_watch_progress_ffi(
  bytes : Bytes,
  length : Int,
) -> Bool = "actql_native_client_status_watch_progress"

///|
fn local_saved_run_status_command(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  input_root : String,
  child : @argparse.Matches,
  capture? : @local_host.NativeLocalJournalCapture? = None,
  human_display? : ((String) -> String raise ClientStop)? = None,
  original_reader? : ((String) -> @local_host.NativeClientSavedRunStateSelection raise ClientStop)? = None,
) -> String raise ClientStop {
  guard local_status_watch_options(child) is Some(options) else {
    return local_saved_run_status(
      host,
      settings,
      crypto,
      input_root,
      child,
      capture~,
      human_display~,
      original_reader~,
    )
  }
  let scope = local_host_result(
    match capture {
      None =>
        host.authority_scope_cid(
          settings.principal,
          settings.connection,
          crypto,
        )
      Some(original) =>
        original.authority_scope_cid_in_original_read(
          settings.principal,
          settings.connection,
        )
    },
  )
  if !local_status_watch_begin_ffi() {
    if !local_status_watch_end_ffi() {
      stop("LocalStatusWatchCleanupPending original=LocalStatusWaitUnavailable")
    }
    stop("LocalStatusWaitUnavailable")
  }
  let wire = local_status_watch_loop(options, {
    read_original: () => {
      local_saved_run_status(
        host,
        settings,
        crypto,
        input_root,
        child,
        state_only=true,
        capture~,
        original_reader~,
      )
    },
    current: () => {
      local_run_operation_allowed(
        host,
        settings,
        crypto,
        scope,
        "read",
        capture~,
      )
    },
    now_ms: local_status_watch_now_ffi,
    pause_ms: local_status_watch_pause_ffi,
    interrupted: local_status_watch_interrupted_ffi,
    progress: wire => {
      let text = if child.flags.get("json").unwrap_or(false) {
        wire
      } else {
        match human_display {
          Some(display) => display(wire)
          None =>
            local_run_state_display(wire).unwrap_or_else(() => {
              stop("LocalRunStateDisplayUnavailable")
            })
        }
      }
      let bytes = @utf8.encode(text + "\n")
      local_status_watch_progress_ffi(bytes, bytes.length())
    },
  }) catch {
    ClientStop(original) => {
      if !local_status_watch_end_ffi() {
        stop("LocalStatusWatchCleanupPending original=" + original)
      }
      stop(original)
    }
  }
  if !local_status_watch_end_ffi() {
    stop("LocalStatusWatchCleanupPending")
  }
  if child.flags.get("json").unwrap_or(false) {
    wire
  } else {
    match human_display {
      Some(display) => display(wire)
      None =>
        local_run_state_display(wire).unwrap_or_else(() => {
          stop("LocalRunStateDisplayUnavailable")
        })
    }
  }
}
