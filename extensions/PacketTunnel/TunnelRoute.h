#ifndef COFRE_TUNNEL_ROUTE_H
#define COFRE_TUNNEL_ROUTE_H

/// Sends this extension's own connections to `address` (IPv4) through the
/// tunnel interface `interfaceIndex`.
void CofreRouteThroughTunnel(const char *address, unsigned int interfaceIndex);

#endif
