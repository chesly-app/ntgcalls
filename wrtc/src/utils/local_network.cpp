//
// iOS port (Chesly fork, 2026-11).
//

#ifdef IS_IOS
#include <absl/strings/match.h>
#include <wrtc/utils/local_network.hpp>

namespace wrtc::utils {
    bool is_local_only(const webrtc::IPAddress& ip) {
        return webrtc::IPIsPrivate(ip) || webrtc::IPIsULA(ip);
    }

    bool in_local_subnet(const webrtc::IPAddress& ip, const webrtc::NetworkManager* network_manager) {
        if (!network_manager) {
            return false;
        }
        for (const webrtc::Network* network : network_manager->GetNetworks()) {
            if (network->family() != ip.family()) {
                continue;
            }
            if (webrtc::TruncateIP(ip, network->prefix_length()) == network->prefix()) {
                return true;
            }
        }
        return false;
    }

    bool is_local_remote_candidate(const webrtc::Candidate& candidate, const webrtc::NetworkManager* network_manager) {
        const webrtc::SocketAddress& address = candidate.address();
        if (address.IsUnresolvedIP()) {
            return absl::EndsWith(address.hostname(), ".local");
        }
        return is_local_only(address.ipaddr()) || in_local_subnet(address.ipaddr(), network_manager);
    }

    bool is_local_gathered_candidate(const webrtc::Candidate& candidate) {
        return candidate.is_local() && !candidate.address().IsUnresolvedIP() && is_local_only(candidate.address().ipaddr());
    }
} // wrtc::utils
#endif
