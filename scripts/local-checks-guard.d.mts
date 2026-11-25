// Selected by the Native observer after TypeScript emit. The local guard also runs in a cold checkout.
export declare function availableVerificationMemory(platform: string, text: string, total: number): number;

type LocalCheckParameters = {
  root: string;
  timeoutSeconds: number;
  graceSeconds?: number;
  heavy: boolean;
  heavyResources?: {memoryBytes: number; diskBytes: number; cpuThreads: number};
  steps: readonly {name: string; command: string; args: readonly string[]; env?: NodeJS.ProcessEnv; scratch?: string}[];
};

export declare function durationSeconds(value: unknown, name?: string): number;
export declare function runLocalCheck(config: LocalCheckParameters, options?: {signal?: AbortSignal}): Promise<number>;
