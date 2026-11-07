//
// Created by Lauren on 06/11/24.
//

#pragma once

#if !defined(IS_ANDROID) && !defined(IS_IOS) // iOS port: no OpenH264 on iOS
#include <api/video/color_space.h>

extern "C" {
#include <libavcodec/avcodec.h>
}

namespace openh264 {

    webrtc::ColorSpace extract_h264_color_space(const AVCodecContext* codec);

} // openh264
#endif
