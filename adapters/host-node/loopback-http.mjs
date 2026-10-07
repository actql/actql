// Physical Node ingress only. Neither Host nor forwarded headers attest the
// listener bind or peer address. The application continues to own listen().
import {Server, Socket, isIP} from 'node:net';

export const isLoopbackSocketAddress = address => typeof address === 'string' &&
  (address === '::1' || isIP(address) === 4 && address.startsWith('127.'));

export function isLoopbackHttpRequest(request) {
  try {
    const socket = request?.socket;
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
