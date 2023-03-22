#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct IOSTun IOSTun;

typedef void (*UdpV4Callback)(const void *ctx, uint32_t addr, uint16_t port, const uint8_t *buffer, uintptr_t buf_size);

typedef void (*UdpV6Callback)(const void *ctx, const uint8_t (*addr)[16], uint16_t port, const uint8_t *buffer, uintptr_t buf_size);

typedef void (*TunCallbackV4)(const void *ctx, const uint8_t *buffer, uintptr_t buf_size);

typedef void (*TunCallbackV6)(const void *ctx, const uint8_t *buffer, uintptr_t buf_size);

typedef struct IOSContext {
  const void *ctx;
  UdpV4Callback send_udp_ipv4;
  UdpV6Callback send_udp_ipv6;
  TunCallbackV4 tun_v4_callback;
  TunCallbackV6 tun_v6_callback;
} IOSContext;

typedef struct IOSTunParams {
  uint8_t private_key[32];
  uint8_t peer_key[32];
  uint8_t peer_addr_version;
  uint8_t peer_addr_bytes[16];
  uint16_t peer_port;
  struct IOSContext ctx;
} IOSTunParams;

uintptr_t abstract_tun_size(void);

struct IOSTun *abstract_tun_init_instance(const struct IOSTunParams *params);

void abstract_tun_handle_host_traffic(struct IOSTun *tun,
                                      const uint8_t *packet,
                                      uintptr_t packet_size);

void abstract_tun_handle_tunnel_traffic(struct IOSTun *tun,
                                        const uint8_t *packet,
                                        uintptr_t packet_size);

void abstract_tun_handle_timer_event(struct IOSTun *tun);

void abstract_tun_drop(struct IOSTun *tun);
