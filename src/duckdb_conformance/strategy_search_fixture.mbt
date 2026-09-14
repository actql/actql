///|
// Fixed cost inputs for conformance, not inferred from product output or timing.
#export_name("strategyFixtureReplan")
pub fn strategy_fixture_replan(
  f : StrategyFixture,
  transfer_ms : Int64,
) -> Bool {
  guard f.run is Some(run) else { return false }
  if !f.search_configured {
    guard @strategy.configure_strategy_search(run, {
        max_offers: 6,
        max_strategies: 8,
        max_work: 1000,
        max_revisions: 4,
      })
      is Ok(_) else {
      return false
    }
    f.search_configured = true
  }
  let offers = []
  for task in 1..<4 {
    if @strategy.captured_task_output(run, task, Step(1)) is Some(_) {
      continue
    }
    for index in 0..<2 {
      let native = index == 1
      let offer = @strategy.prepare_task_offer(
        run,
        task,
        @planning.capability_registration_at(f.registry, index).unwrap(),
        if native {
          8
        } else {
          5
        },
        if native {
          [
            { work_slots: [0, 2, 3, 5, 6, 7], milliseconds: Some(1L), },
            { work_slots: [1, 4], milliseconds: Some(transfer_ms), },
          ]
        } else {
          [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(10L), }]
        },
        {
          transfer_bytes: if native {
            100000L
          } else {
            0L
          },
          retained_bytes: 10000L,
          execution_bytes: if native {
            268435456L
          } else {
            10000L
          },
        },
        100,
      )
      guard offer is Ok(offer) else { return false }
      offers.push(offer)
    }
  }
  match @strategy.revise_strategy(run, offers, f.registry, None) {
    Ok(Selected(revision)) => {
      f.selected = Some(revision)
      true
    }
    _ => false
  }
}

///|
#export_name("strategyFixturePlacement")
pub fn strategy_fixture_placement(f : StrategyFixture, task : Int) -> String {
  guard f.selected is Some(revision) &&
    @strategy.strategy_registration(revision, task) is Some(registration) else {
    return "unselected"
  }
  @planning.capability_description(registration).name
}

///|
#export_name("strategyFixtureEstimate")
pub fn strategy_fixture_estimate(f : StrategyFixture) -> Int64 {
  guard f.selected is Some(revision) &&
    @strategy.strategy_assessment(revision).duration is Complete(value) else {
    return -1L
  }
  value
}
