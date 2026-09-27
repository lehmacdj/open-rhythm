#pragma once
#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>
#import <math.h>
#import <stdatomic.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2 && ATOMIC_LONG_LOCK_FREE == 2
  && ATOMIC_LLONG_LOCK_FREE == 2, "Audio command atomics must be lock-free");

// No lock, allocation, reference counting or callback dispatch on the audio
// thread. SPSC triple buffering: producer owns back, consumer owns front, and
// one atomic exchange transfers the middle slot. Dirty is part of that same
// atomic word so publication cannot be lost between the load and exchange.
enum { ORDirty = 4, ORSlotMask = 3 };
typedef struct {
  uint64_t generation;
  bool playing, paused, looped, manual;
  double start, end;
} ORPCMCommand;

typedef struct {
  ORPCMCommand commands[3];
  _Atomic unsigned middle;
  _Atomic uint64_t completedGeneration;
  unsigned front;
  uint64_t generation;
  AVAudioFrameCount position, length;
  AVAudioChannelCount channels;
  bool started;
  double rate, hostTicksPerFrame;
  const float *samples[2];
} ORPCMRenderState;

// First sample whose timestamp is >= deadline. Remove at most two rounding
// ULPs before ceil so an exactly integral frame expressed as seconds does not
// accidentally move to the following sample. This is not latency calibration.
static AVAudioFrameCount ORFramesUntil(double deadline, double now,
  double unitsPerFrame, AVAudioFrameCount count) {
  double frames = (deadline - now) / unitsPerFrame;
  if (!(frames > 0)) return 0;
  if (frames >= count) return count;
  return (AVAudioFrameCount)ceil(nextafter(nextafter(frames, -INFINITY),
    -INFINITY));
}

static OSStatus ORRenderPCM(ORPCMRenderState *state, BOOL *isSilence,
  const AudioTimeStamp *time, AVAudioFrameCount count, AudioBufferList *output) {
  *isSilence = YES;
  if (output->mNumberBuffers != state->channels) return kAudio_ParamError;
  for (unsigned channel = 0; channel < state->channels; channel++) {
    AudioBuffer *buffer = &output->mBuffers[channel];
    if (!buffer->mData || buffer->mDataByteSize < count * sizeof(float)) {
      return kAudio_ParamError;
    }
    memset(buffer->mData, 0, count * sizeof(float));
  }
  if (atomic_load_explicit(&state->middle, memory_order_acquire) & ORDirty) {
    state->front = atomic_exchange_explicit(&state->middle, state->front,
      memory_order_acq_rel) & ORSlotMask;
  }
  const ORPCMCommand *command = &state->commands[state->front];
  if (state->generation != command->generation) {
    state->generation = command->generation;
    state->position = 0;
    state->started = false;
  }
  if (!command->playing || command->paused) return noErr;

  double now, unitsPerFrame;
  if (command->manual) {
    if (!(time->mFlags & kAudioTimeStampSampleTimeValid)) return kAudio_ParamError;
    now = time->mSampleTime;
    unitsPerFrame = 1;
  } else {
    if (!(time->mFlags & kAudioTimeStampHostTimeValid)) return kAudio_ParamError;
    now = (double)time->mHostTime;
    unitsPerFrame = state->hostTicksPerFrame;
  }
  AVAudioFrameCount begin = state->started ? 0
    : ORFramesUntil(command->start, now, unitsPerFrame, count);
  AVAudioFrameCount end = ORFramesUntil(command->end, now, unitsPerFrame, count);
  if (begin >= end) return noErr;
  state->started = true;
  for (AVAudioFrameCount frame = begin; frame < end;) {
    if (state->position == state->length) {
      if (command->looped) state->position = 0;
      else break;
    }
    AVAudioFrameCount available = state->length - state->position;
    AVAudioFrameCount copied = MIN(available, end - frame);
    for (unsigned channel = 0; channel < state->channels; channel++) {
      float *destination = output->mBuffers[channel].mData;
      memcpy(destination + frame, state->samples[channel] + state->position,
        copied * sizeof(float));
    }
    frame += copied;
    state->position += copied;
    *isSilence = NO;
  }
  if (!command->looped && state->position == state->length) {
    atomic_store_explicit(&state->completedGeneration, command->generation,
      memory_order_release);
  }
  return noErr;
}
