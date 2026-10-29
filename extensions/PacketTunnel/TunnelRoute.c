// iOS keeps a packet tunnel provider's own traffic out of its tunnel unless the
// socket is bound to the tunnel interface (`virtualInterface` in
// NEPacketTunnelProvider.h). StikJIT's idevice opens its sockets in Rust, so
// this extension defines connect(2): the linker resolves idevice's calls here,
// and sockets to the tunnel address are bound to the tunnel before the real
// connect. Without it, JIT times out connecting to 10.7.0.1.
#include "TunnelRoute.h"
#include <arpa/inet.h>
#include <dlfcn.h>
#include <netinet/in.h>
#include <stdatomic.h>
#include <sys/socket.h>

static _Atomic unsigned int boundIndex;
static _Atomic in_addr_t boundAddress;

void CofreRouteThroughTunnel(const char *address, unsigned int interfaceIndex) {
  struct in_addr a;
  if (inet_pton(AF_INET, address, &a) != 1)
    return;
  atomic_store(&boundAddress, a.s_addr);
  atomic_store(&boundIndex, interfaceIndex);
}

int connect(int fd, const struct sockaddr *addr, socklen_t len) {
  static int (*systemConnect)(int, const struct sockaddr *, socklen_t);
  if (!systemConnect)
    systemConnect = dlsym(RTLD_NEXT, "connect");
  unsigned int index = atomic_load(&boundIndex);
  if (index && addr && addr->sa_family == AF_INET &&
      len >= sizeof(struct sockaddr_in) &&
      ((const struct sockaddr_in *)addr)->sin_addr.s_addr ==
          atomic_load(&boundAddress))
    setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, sizeof index);
  return systemConnect(fd, addr, len);
}
