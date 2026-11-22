// Test-only signatures of the generated conformance fixture and standard Host call.
import type {runInstalledStrategy} from '../../../../host-common/strategy.mjs';
import type {prepareDuckDBStrategyConfiguration} from '../configuration.mjs';

export type ContractWires = readonly [string, string, string];
export type JoinFixtureRuntime = Readonly<{
  strategyFixtureJoinCreate(environment: string, environmentCid: string, registry: string, values: string,
    fragment: string, query: string, processEvidence: string, twoReceipt: string, program: string): unknown;
  strategyFixtureAcquisition(fixture: unknown): unknown;
  strategyFixtureOpen(fixture: unknown, source: unknown): boolean;
  strategyFixtureResidentDispatch(fixture: unknown): unknown;
  strategyFixtureCostedDispatch(fixture: unknown, nativeMilliseconds: bigint): unknown;
  strategyFixtureDispatch(fixture: unknown): unknown;
  strategyFixtureReplan(fixture: unknown, transferMilliseconds: bigint): boolean;
  strategyFixtureCid(fixture: unknown, task: number): string;
  strategyFixtureCloseOutput(fixture: unknown, task: number): void;
  strategyFixtureConsume(fixture: unknown, task: number, steps: string): string;
}>;
export type CapturedUsage = Readonly<{
  heldBytes: bigint;
  reservedExecutionBytes: bigint;
  transferredBytes: bigint;
}>;
export type RunCapturedStrategy = (setup: unknown, configuration: Readonly<{
  duckdb: ReturnType<typeof prepareDuckDBStrategyConfiguration>;
}>) => ReturnType<typeof runInstalledStrategy>;
