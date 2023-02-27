#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct IOSTun IOSTun;

typedef struct IOSTunParams {
  uint8_t private_key[32];
  uint8_t peer_key[32];
  uint32_t peer_addr_v4;
  uint32_t peer_port;
} IOSTunParams;

typedef int (*UdpV4Callback)(const void *ctx, uint32_t addr, uint16_t port, const uint8_t *buffer, uintptr_t buf_size);

typedef int (*UdpV6Callback)(const void *ctx, uint8_t addr[16], uint16_t port, const uint8_t *buffer, uintptr_t buf_size);

typedef void (*TunCallbackV4)(const void *ctx, const uint8_t *buffer, uintptr_t buf_size);

typedef void (*TunCallbackV6)(const void *ctx, const uint8_t *buffer, uintptr_t buf_size);

typedef struct IOSContext {
  const void *udp_ctx;
  UdpV4Callback udp_v4_callback;
  UdpV6Callback udp_v6_callback;
  const void *tun_ctx;
  TunCallbackV4 tun_v4_callback;
  TunCallbackV6 tun_v6_callback;
} IOSContext;

uintptr_t abstract_tun_size(void);

struct IOSTun *abstract_tun_init_instance(const struct IOSTunParams *params);

void abstract_tun_handle_tunnel_traffic(struct IOSTun *tun,
                                        const uint8_t *packet,
                                        uintptr_t packet_size,
                                        struct IOSContext ctx);

void abstract_tun_handle_udp_packet(struct IOSTun *tun,
                                    const uint8_t *packet,
                                    uintptr_t packet_size,
                                    struct IOSContext ctx);

void abstract_tun_handle_timer_event(struct IOSTun *tun, struct IOSContext ctx);

void abstract_tun_drop(struct IOSTun *tun);

int32_t abstract_test_fp2(int32_t (*fp)(int32_t), int32_t num);
