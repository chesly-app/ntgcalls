//
// Created by Lauren on 04/11/24.
//

#pragma once

#if !defined(IS_ANDROID) && !defined(IS_IOS) // iOS port: no OpenH264 on iOS
#include <wrtc/video_factory/video_decoder_config.hpp>
#include <wrtc/video_factory/video_encoder_config.hpp>

namespace openh264 {

    void add_encoders(std::vector<wrtc::video_factory::VideoEncoderConfig>& encoders);

    void add_decoders(std::vector<wrtc::video_factory::VideoDecoderConfig>& decoders);

} // openh264

#endif
