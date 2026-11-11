// Narrow declarations for macOS's com.apple.screensaver extension point,
// matching the working ARose host bridge. The runtime provides these classes.
#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>
@interface ScreenSaverExtension : NSObject
@end
@interface ScreenSaverViewController : NSViewController
- (void)startAnimation;
- (void)stopAnimation;
@end
@interface ScreenSaverConfigurationViewController : NSViewController
- (void)configureSheetDidEnd;
- (void)configureSheetWillPresent;
@end
