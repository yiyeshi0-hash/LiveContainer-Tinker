#import "TinkerLogOverlay.h"
#import <UIKit/UIKit.h>

@interface TinkerLiveLogViewController : UIViewController
@end

@implementation TinkerLiveLogViewController {
    UITextView *_textView;
    NSTimer *_timer;
    UInt64 _offset;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"实时日志";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.editable = NO;
    _textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.frame = self.view.bounds;
    [self.view addSubview:_textView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [self refresh];
}

- (void)refresh {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Logs/live.log"];
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToFileOffset:_offset];
        NSData *data = [handle readDataToEndOfFile];
        _offset += data.length;
        if (data.length > 0) {
            NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (s.length > 0) {
                _textView.text = [_textView.text stringByAppendingString:s];
                if (_textView.text.length > 200000) {
                    _textView.text = [_textView.text substringFromIndex:_textView.text.length - 200000];
                }
                [_textView scrollRangeToVisible:NSMakeRange(_textView.text.length, 0)];
            }
        }
    } @catch (NSException *e) {
    } @finally {
        [handle closeFile];
    }
}

- (void)close {
    [_timer invalidate];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface TinkerLogOverlayRootVC : UIViewController
@end

@implementation TinkerLogOverlayRootVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"日志" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.9];
    button.layer.cornerRadius = 18;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    button.frame = CGRectMake(UIScreen.mainScreen.bounds.size.width - 76, 64, 60, 36);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [button addTarget:self action:@selector(openLog) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
}

- (void)openLog {
    TinkerLiveLogViewController *vc = [[TinkerLiveLogViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

@end

static UIWindow *gLogWindow;
static BOOL gLogOverlayInstalled;

void TinkerSetupLiveLogOverlay(void) {
    if (gLogOverlayInstalled) return;
    gLogOverlayInstalled = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindowScene *scene = nil;
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if ([candidate isKindOfClass:UIWindowScene.class]) {
                scene = (UIWindowScene *)candidate;
                if (candidate.activationState == UISceneActivationStateForegroundActive) break;
            }
        }
        if (!scene) return;

        gLogWindow = [[UIWindow alloc] initWithWindowScene:scene];
        gLogWindow.windowLevel = UIWindowLevelStatusBar + 100;
        gLogWindow.frame = UIScreen.mainScreen.bounds;
        gLogWindow.backgroundColor = UIColor.clearColor;
        gLogWindow.rootViewController = [[TinkerLogOverlayRootVC alloc] init];
        gLogWindow.hidden = NO;
    });
}
