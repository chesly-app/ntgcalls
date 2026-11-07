//
// Created by Lauren on 04/11/24.
//

#if !defined(IS_ANDROID) && !defined(IS_IOS) // iOS port: no OpenH264 on iOS
#include <wrtc/video_factory/software/openh264/layer_config.hpp>

namespace openh264 {
    void LayerConfig::set_stream_state(const bool send_stream) {
        if (send_stream && !sending) {
            key_frame_request = true;
        }
        sending = send_stream;
    }
} // openh264
#endif
