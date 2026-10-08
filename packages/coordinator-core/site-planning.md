# Common Site planning

`sitePlanning.plan` exposes the existing `execution_site` feasibility and time
composition rules. `sitePlanning.select` uses that owner's minimum-duration
choice and stable Site-key tie break. Durations are nonnegative Int64 values;
each input list is bounded to 64 entries at this JavaScript boundary.

The Host supplies current trusted observations. A successful plan is neither
authentication nor a resource reservation, Transfer grant, dispatch or execution
permission. Missing estimates and unsupported capacity or movement remain
excluded by the common planner. The caller must persist the chosen original
Run/Site/generation binding and recheck current admission before sending input.

These rules compare the supplied duration scope. A first-task estimate does not
prove that the entire Run is fastest, and selecting a Site does not permit
changing an unresolved attempt's Site during recovery.
