-- Expected proposition types are checked by Lean, not theorem-name searches.
-- Changes to a theorem's premises cannot silently retain the old claim.
example (b a : BoundedSession.Counters) (q l : Nat)
    (h : BoundedSession.Admissible b a q l) :
    b.progress + (BoundedSession.delta b a).progress = a.progress ∧
    b.work + (BoundedSession.delta b a).work = a.work :=
  BoundedSession.delta_reconstructs b a q l h

example (xs : List Nat) (h : BoundedSession.MonotoneReports 0 xs) :
    BoundedSession.charges 0 xs = BoundedSession.finalWork 0 xs :=
  BoundedSession.provider_accounting_instance xs h

example (b a : BoundedSession.Counters) (q l : Nat)
    (h : BoundedSession.Admissible b a q l) :
    (BoundedSession.delta b a).work ≤ q ∧ a.work ≤ l :=
  BoundedSession.delta_bounded b a q l h

example (s : BoundedSession.Adapter) (done : Bool) :
    (BoundedSession.cleanup s done).counters = s.counters ∧
    (BoundedSession.cleanup s done).terminal = s.terminal :=
  BoundedSession.cleanup_preserves_outcome s done

example (s : BoundedSession.Obligations) (ready : Bool) (h : s.result = true) :
    (BoundedSession.reclaim s false ready).state = s.state :=
  BoundedSession.pending_result_keeps_state s ready h

example (t : BoundedSession.Token) (terminal running : Bool) (q : Nat) :
    ¬ BoundedSession.MayResume (BoundedSession.successor t) t terminal running q :=
  BoundedSession.consumed_token_rejected t terminal running q

example (current supplied : BoundedSession.Token) (running : Bool) (q : Nat) :
    ¬ BoundedSession.MayResume current supplied true running q :=
  BoundedSession.terminal_cannot_resume current supplied running q

example (s : BoundedSession.Adapter) (a : BoundedSession.Counters) (k : BoundedSession.Kind)
    (h : k ≠ .continuing) : (BoundedSession.observed s a k).terminal = true :=
  BoundedSession.terminal_poll_closes s a k h

example (s : BoundedSession.Adapter) (done : Bool) (h : s.terminal = false) :
    (BoundedSession.cleanup s done).reclaimed = s.reclaimed :=
  BoundedSession.running_cannot_reclaim s done h

example (s : BoundedSession.Adapter) (done : Bool) (h : s.reclaimed = true) :
    (BoundedSession.cleanup s done).reclaimed = true :=
  BoundedSession.cleanup_completed_stays_completed s done h
