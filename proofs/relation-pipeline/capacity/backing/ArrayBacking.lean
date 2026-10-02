/- Bounds on fixed-buffer slots. No object layout, heap-byte guarantee or
   implementation-wide refinement is asserted here. -/
namespace ArrayBacking

def ceiling (initial highWater : Nat) : Nat :=
  max initial (if highWater = 0 then 0 else max 8 (2 * highWater))

theorem initial_fits (initial highWater : Nat) :
    initial ≤ ceiling initial highWater := Nat.le_max_left _ _

-- A push at full capacity either initializes eight slots, doubles while
-- representable, or falls back to the exact required length.
theorem push_fits (initial highWater len cap next : Nat)
    (full : cap = len) (admitted : len + 1 ≤ highWater)
    (growth : next = 8 ∨ next = 2 * cap ∨ next = len + 1) :
    next ≤ ceiling initial highWater := by
  have positive : highWater ≠ 0 := by omega
  simp only [ceiling, if_neg positive]
  have eight := Nat.le_max_left 8 (2 * highWater)
  have twice := Nat.le_max_right 8 (2 * highWater)
  have outer := Nat.le_max_right initial (max 8 (2 * highWater))
  rcases growth with h | h | h <;> omega

theorem reuse_fits (initial highWater old : Nat)
    (held : old ≤ ceiling initial highWater) :
    old ≤ ceiling initial highWater := held

-- The old and new buffer coexist during growth; equal payload does not make
-- them the same allocation.
theorem growth_overlap (initial highWater old next : Nat)
    (a : old ≤ ceiling initial highWater)
    (b : next ≤ ceiling initial highWater) :
    old + next ≤ 2 * ceiling initial highWater := by omega

structure ArrayState where
  length : Nat
  capacity : Nat
  backing : Nat

def clear (s : ArrayState) : ArrayState := { s with length := 0 }

theorem clear_keeps_backing (s : ArrayState) :
    (clear s).capacity = s.capacity ∧ (clear s).backing = s.backing := by
  simp [clear]

def wrapDouble (cap : Int) : Int :=
  if 2 * cap ≤ 2147483647 then 2 * cap else 2 * cap - 4294967296

theorem wrapped_doubling_triggers_fallback (cap : Int)
    (nonnegative : 0 ≤ cap) (representable : cap ≤ 2147483647)
    (overflow : 2147483647 < 2 * cap) :
    wrapDouble cap ≤ cap := by
  have h : ¬ 2 * cap ≤ 2147483647 := by omega
  simp only [wrapDouble, if_neg h]
  omega

end ArrayBacking
