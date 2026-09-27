#import "EnginePCMVoice.h"
#import "EnginePCMRender.h"

#if !__has_feature(objc_arc)
#error EnginePCMVoice requires ARC to retain PCM and release voice storage.
#endif

// Both the control object and node block retain this storage. The block uses
// only its C ivar address, never Objective-C messaging. PCM remains immutable
// and alive even if the control object is released while the node still exists.
@interface ORPCMStorage : NSObject {
@public
  ORPCMRenderState state;
  AVAudioPCMBuffer *pcm;
}
@end
@implementation ORPCMStorage
@end

@implementation ORPCMVoice {
  AVAudioEngine *_engine;
  AVAudioSourceNode *_node;
  ORPCMStorage *_storage;
  ORPCMCommand _command;
  unsigned _back;
  double _hostTicksPerSecond, _remainingStart, _remainingEnd;
}

- (instancetype)initWithEngine:(AVAudioEngine *)engine
  buffer:(AVAudioPCMBuffer *)buffer {
  self = [super init];
  if (!self) return nil;
  NSParameterAssert(buffer.frameLength > 0);
  NSParameterAssert(buffer.format.commonFormat == AVAudioPCMFormatFloat32);
  NSParameterAssert(!buffer.format.interleaved);
  NSParameterAssert(buffer.format.channelCount >= 1
    && buffer.format.channelCount <= 2);
  _engine = engine;
  _storage = [ORPCMStorage new];
  _storage->pcm = buffer;
  ORPCMRenderState *state = &_storage->state;
  atomic_init(&state->middle, 2);
  atomic_init(&state->completedGeneration, 0);
  NSAssert(atomic_is_lock_free(&state->middle)
    && atomic_is_lock_free(&state->completedGeneration),
    @"PCM scheduling requires lock-free native atomics");
  _back = 1;
  state->length = buffer.frameLength;
  state->channels = buffer.format.channelCount;
  state->rate = buffer.format.sampleRate;
  mach_timebase_info_data_t info;
  mach_timebase_info(&info);
  _hostTicksPerSecond = 1e9 * (double)info.denom / info.numer;
  state->hostTicksPerFrame = _hostTicksPerSecond / state->rate;
  for (unsigned channel = 0; channel < state->channels; channel++) {
    state->samples[channel] = buffer.floatChannelData[channel];
  }
  ORPCMStorage *storage = _storage;
  _node = [[AVAudioSourceNode alloc] initWithFormat:buffer.format
    renderBlock:^OSStatus(BOOL *silent, const AudioTimeStamp *time,
      AVAudioFrameCount count, AudioBufferList *output) {
      return ORRenderPCM(&storage->state, silent, time, count, output);
    }];
  [engine attachNode:_node];
  [engine connect:_node to:engine.mainMixerNode format:buffer.format];
  return self;
}

- (void)publish {
  _storage->state.commands[_back] = _command;
  _back = atomic_exchange_explicit(&_storage->state.middle, _back | ORDirty,
    memory_order_acq_rel) & ORSlotMask;
}

- (double)now {
  if (_command.manual) {
    return (double)_engine.manualRenderingSampleTime * _storage->state.rate
      / _engine.manualRenderingFormat.sampleRate;
  }
  return (double)mach_absolute_time();
}

- (double)unitsPerSecond {
  return _command.manual ? _storage->state.rate : _hostTicksPerSecond;
}

- (BOOL)playing {
  return _command.playing && (_command.looped ||
    atomic_load_explicit(&_storage->state.completedGeneration,
      memory_order_acquire) != _command.generation);
}

- (void)playAfter:(double)delay looped:(BOOL)looped {
  _command.generation++;
  _command.playing = true;
  _command.paused = false;
  _command.looped = looped;
  _command.manual = _engine.isInManualRenderingMode;
  _command.start = [self now] + MAX(0, delay) * [self unitsPerSecond];
  _command.end = INFINITY;
  [self publish];
}

- (void)stopAfter:(double)delay {
  if (delay <= 0) { [self stop]; return; }
  if (_command.paused) {
    // The engine may render more silent frames before resume. Anchor this
    // relative deadline only when publishing the unpaused snapshot.
    _remainingEnd = delay * [self unitsPerSecond];
    return;
  }
  _command.end = [self now] + delay * [self unitsPerSecond];
  [self publish];
}

- (void)pause {
  if (!_command.playing || _command.paused) return;
  _remainingStart = MAX(0, _command.start - [self now]);
  _command.paused = true;
  // The chart owner rebases its stop deadline before advancing after buffering.
  _command.end = INFINITY;
  _remainingEnd = INFINITY;
  [self publish];
}

- (void)resume {
  if (!_command.playing || !_command.paused) return;
  _command.paused = false;
  double now = [self now];
  _command.start = now + _remainingStart;
  _command.end = now + _remainingEnd;
  [self publish];
}

- (void)stop {
  _command.generation++;
  _command.playing = false;
  [self publish];
}
@end
