#pragma once
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

UIView* SMSCreateGameCubeControls(CGRect frame, void (*pressObserver)(void));
void SMSGameCubeControlsReleaseAll(UIView* controls);

#ifdef __cplusplus
}
#endif
