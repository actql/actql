// Physical Node ingress only. Neither Host nor forwarded headers attest the
// listener bind or peer address. The application continues to own listen().
import {Server, Socket, isIP} from 'node:net';

// Node supplies these socket fields at the HTTP boundary. Their presence and
// the actual Socket/Server instances remain checked below.
type HttpSocket = Socket & Readonly<{encrypted?: unknown; server?: unknown}>;
type HttpRequestSocket = Readonly<{socket?: HttpSocket}> | null | undefined;

export const isLoopbackSocketAddress = (address: unknown) => typeof address === 'string' &&
  (address === '::1' || isIP(address) === 4 && address.startsWith('127.'));

export function isLoopbackHttpRequest(request: unknown) {
  try {
    const socket = (request as HttpRequestSocket)?.socket;
    if (!(socket instanceof Socket) || socket.encrypted === true ||
        !(socket.server instanceof Server)) return false;
    // Use the actual accepting Server's OS binding, not an application
    // declaration or a replacement address() property on a request wrapper.
    const bound = Server.prototype.address.call(socket.server);
    return bound !== null && typeof bound === 'object' &&
      isLoopbackSocketAddress(bound.address) &&
      Number.isInteger(bound.port) && bound.port > 0 &&
      bound.port === socket.localPort && bound.address === socket.localAddress &&
      isLoopbackSocketAddress(socket.localAddress) &&
      isLoopbackSocketAddress(socket.remoteAddress);
  } catch { return false; }
}
