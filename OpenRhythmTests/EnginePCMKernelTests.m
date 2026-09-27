#import <XCTest/XCTest.h>
#import "../OpenRhythm/Core/EnginePCMRender.h"

@interface EnginePCMKernelTests : XCTestCase
@end

@implementation EnginePCMKernelTests
- (void)testHostTimeGatesUseTickToSampleConversion {
  int failures = 0;
  mach_timebase_info_data_t info;
  mach_timebase_info(&info);
  double ticksPerSecond = 1e9 * (double)info.denom / info.numer;
  const double rates[] = {44100, 48000, 96000};
  for (unsigned rateIndex = 0; rateIndex < 3; rateIndex++) {
    float source[2][512], rendered[2][512];
    for (unsigned i = 0; i < 512; i++) {
      source[0][i] = 0.25f;
      source[1][i] = -0.25f;
    }
    ORPCMRenderState state = {0};
    atomic_init(&state.middle, 2);
    atomic_init(&state.completedGeneration, 0);
    state.length = 512;
    state.channels = 2;
    state.rate = rates[rateIndex];
    state.hostTicksPerFrame = ticksPerSecond / state.rate;
    state.samples[0] = source[0];
    state.samples[1] = source[1];
    // Large nonzero uptime plus half-sample boundaries checks host subtraction
    // and [start,end) rounding without assuming a host tick equals one sample.
    const uint64_t origin = UINT64_C(1) << 54;
    state.commands[0] = (ORPCMCommand){
      .generation = 1, .playing = true, .looped = true,
      .start = origin + 17.5 * state.hostTicksPerFrame,
      .end = origin + 137.5 * state.hostTicksPerFrame
    };
    AudioTimeStamp time = { .mHostTime = origin,
      .mFlags = kAudioTimeStampHostTimeValid };
    struct { UInt32 count; AudioBuffer buffers[2]; } output = {
      2, {{1, sizeof(rendered[0]), rendered[0]},
          {1, sizeof(rendered[1]), rendered[1]}}
    };
    BOOL silent = YES;
    if (ORRenderPCM(&state, &silent, &time, 512,
      (AudioBufferList *)&output) != noErr || silent) failures++;
    for (unsigned i = 0; i < 512; i++) {
      float expected = i >= 18 && i < 138 ? 0.25f : 0;
      if (rendered[0][i] != expected || rendered[1][i] != -expected) failures++;
    }
    // Do not accidentally interpret missing host timestamps as uptime zero.
    time.mFlags = kAudioTimeStampSampleTimeValid;
    if (ORRenderPCM(&state, &silent, &time, 512,
      (AudioBufferList *)&output) != kAudio_ParamError || !silent) failures++;
    for (unsigned i = 0; i < 512; i++) {
      if (rendered[0][i] != 0 || rendered[1][i] != 0) failures++;
    }
  }
  XCTAssertEqual(failures, 0);
}
@end
