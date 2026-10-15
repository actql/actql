import type {Client, RunReference} from '@actql/sdk';
export const gatewayLimits: Readonly<{bodyBytes: 65536; replyBytes: 262144;
  bodyDepth: 64; bodyNodes: 10000; inFlight: 4; assets: 32;
  assetBytes: number; sessionMs: 300000; bootstrapMs: 60000; requestMs: 15000}>;
export type ExplorerAsset = Readonly<{body: Uint8Array; contentType:
  'text/html; charset=utf-8' | 'text/javascript; charset=utf-8' |
  'text/css; charset=utf-8' | 'image/svg+xml'}>;
/** Bounded presentation input; neither a submission nor an authority. */
export type ExplorerLaunchInput = Readonly<{
  kind: 'program'; text: string; format: 'sql' | 'aql-text' | 'program';
}> | Readonly<{kind: 'run'; ref: RunReference}>;
export type ExplorerGatewayOptions = Readonly<{
  client: Pick<Client, 'attach'> & Partial<Pick<Client, 'plan'>>;
  assets?: ReadonlyMap<string, ExplorerAsset>; now?: () => number;
  sessionMs?: number; bootstrapMs?: number;
  launchInput?: ExplorerLaunchInput | null;
}>;
export type ExplorerBootstrap = Readonly<{origin: string; bootstrap: string; expiresAt: number}>;
export function createExplorerGateway(options: ExplorerGatewayOptions & {origin: string}): Readonly<{
  fetch(request: Request): Response | Promise<Response>;
  issueBootstrap(): ExplorerBootstrap; invalidateScope(): void; close(): void;
}>;
export function startExplorerGateway(options: ExplorerGatewayOptions & {port?: number}): Promise<Readonly<{
  origin: string; issueBootstrap(): ExplorerBootstrap;
  invalidateScope(): void; close(): Promise<void>;
}>>;
