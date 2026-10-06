example : ∀ {E A B C X Y Z : Type}
    (input : A → X) (middle : B → Y) (output : C → Z)
    (first : A → Except E B) (second : B → Except E C)
    (firstObserved : X → Except E Y) (secondObserved : Y → Except E Z),
    (∀ value, BridgeComposition.observeResult middle (first value) = firstObserved (input value)) →
    (∀ value, BridgeComposition.observeResult output (second value) = secondObserved (middle value)) →
    ∀ value, BridgeComposition.observeResult output (BridgeComposition.composeResult (first value) second) =
      BridgeComposition.composeResult (firstObserved (input value)) secondObserved :=
  @BridgeComposition.observed_composition
example : ∀ {E A B : Type} (error : E) (next : A → Except E B),
    BridgeComposition.composeResult (.error error) next = .error error :=
  @BridgeComposition.failure_short_circuits
example : ∀ {E A B : Type} (observe : A → B) (error : E),
    BridgeComposition.observeResult observe (.error error) = .error error :=
  @BridgeComposition.observed_failure
example : ∀ {E A : Type} (result : Except E A),
    BridgeComposition.observeResult id result = result := @BridgeComposition.observe_identity
example : ∀ {E A B C : Type} (result : Except E A)
    (second : A → Except E B) (third : B → Except E C),
    BridgeComposition.composeResult (BridgeComposition.composeResult result second) third =
      BridgeComposition.composeResult result (fun value => BridgeComposition.composeResult (second value) third) :=
  @BridgeComposition.sequential_associativity
example : ∀ {E A B C : Type} (first : A → Except E B) (second : B → Except E C)
    (pre : A → Prop) (intermediate : B → Prop) (post : C → Prop),
    (∀ a b, pre a → first a = .ok b → intermediate b) →
    (∀ b c, intermediate b → second b = .ok c → post c) →
    ∀ a c, pre a → BridgeComposition.composeResult (first a) second = .ok c → post c :=
  @BridgeComposition.sequential_preconditions
