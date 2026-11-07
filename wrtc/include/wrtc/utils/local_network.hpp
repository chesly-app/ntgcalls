//
// iOS port (Chesly fork, 2026-11).
//

#pragma once

#ifdef IS_IOS
#include <api/candidate.h>
#include <rtc_base/ip_address.h>
#include <rtc_base/network.h>

namespace wrtc::utils {
    // iOS asks the user for Local Network access the first time an app sends to an address on
    // the local network. A 1:1 call reaches the peer through a public address or Telegram's
    // reflectors as well, so the iPhone build keeps local addresses out of both directions:
    // remote candidates on a local address are dropped, and LAN-only host candidates are never
    // offered. What this cannot stop, without changing libwebrtc: a peer on the same IPv6 /64
    // that sends a check to this device's global IPv6 address gets an answer on the local
    // network (a peer-reflexive pair), so an app still needs NSLocalNetworkUsageDescription.
    // The custom parameter "network_allow_local_addresses": true turns the filter off for a
    // call, for a test on one machine.

    // Loopback, link-local, RFC 1918, RFC 6598 shared and unique-local IPv6 addresses.
    bool is_local_only(const webrtc::IPAddress& ip);

    // An address inside the prefix of one of this device's own networks. Must be called on the
    // network thread, as NetworkManager::GetNetworks requires.
    bool in_local_subnet(const webrtc::IPAddress& ip, const webrtc::NetworkManager* network_manager);

    // A remote candidate this device should never send to: a local address, an address on one
    // of its own subnets, or any name still unresolved here (an mDNS name's lookup is itself
    // local-network traffic, and any other name may resolve to a LAN address).
    bool is_local_remote_candidate(const webrtc::Candidate& candidate, const webrtc::NetworkManager* network_manager);

    // A gathered host candidate that only this network can reach. Signalling it would invite a
    // peer on the same LAN to send to it, and the answer would go to the local network.
    bool is_local_gathered_candidate(const webrtc::Candidate& candidate);
} // wrtc::utils
#endif
