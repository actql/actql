// Static readmission ports from the retained Host bridge. The generated MoonBit
// declarations take precedence when present. A clean TypeScript emit can use the
// same static runtime specifier before the separate MoonBit build.
declare module '*/retained_host_bridge/retained_host_bridge.js' {
  export function retainedReadmissionFactsControlBytes(): bigint;
  export function retainedReadmissionInstall(preparation: unknown, descriptor: unknown,
    accepts: (receipt: unknown) => boolean, permitted: () => boolean): unknown;
  export function retainedReadmissionComplete(installed: unknown, receipt: unknown): unknown;
  export function retainedReadmissionReadable(installed: unknown, input: unknown): boolean;
  export function retainedReadmissionClose(installed: unknown): void;
}
