#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

// Control methods are serialized by NativeEffectVoice's MainActor. The audio
// callback is C-only and receives immutable, preallocated command snapshots.
@interface ORPCMVoice : NSObject
- (instancetype)initWithEngine:(AVAudioEngine *)engine
  buffer:(AVAudioPCMBuffer *)buffer NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly) BOOL playing;
- (void)playAfter:(double)delay looped:(BOOL)looped
  NS_SWIFT_NAME(play(after:looped:));
- (void)stopAfter:(double)delay NS_SWIFT_NAME(stop(after:));
- (void)pause;
- (void)resume;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
