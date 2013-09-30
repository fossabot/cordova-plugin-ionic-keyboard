/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVKeyboard.h"

@interface CDVKeyboard ()

@property (nonatomic, readwrite, assign) BOOL keyboardIsVisible;
@property (nonatomic, readwrite, assign) BOOL hideFormAccessoryBar;

@end

@implementation CDVKeyboard

@dynamic shrinkView, hideFormAccessoryBar;

- (id)settingForKey:(NSString*)key
{
    return [self.commandDelegate.settings objectForKey:[key lowercaseString]];
}

- (void)pluginInitialize
{
    // SETTINGS ////////////////////////

    NSString* setting = nil;

    setting = @"HideKeyboardFormAccessoryBar";
    if ([self settingForKey:setting]) {
        self.hideFormAccessoryBar = [(NSNumber*)[self settingForKey:setting] boolValue];
    }

    setting = @"KeyboardShrinksView";
    if ([self settingForKey:setting]) {
        self.shrinkView = [(NSNumber*)[self settingForKey:setting] boolValue];
    }

    setting = @"DisableScrollingWhenKeyboardShrinksView";
    if ([self settingForKey:setting]) {
        self.disableScrollingInShrinkView = [(NSNumber*)[self settingForKey:setting] boolValue];
    }

    //////////////////////////

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    __weak CDVKeyboard* weakSelf = self;

    _keyboardShowObserver = [nc addObserverForName:UIKeyboardDidShowNotification
                                            object:nil
                                             queue:[NSOperationQueue mainQueue]
                                        usingBlock:^(NSNotification* notification) {
            // TODO: set Keyboard.isVisible in JavaScript
            weakSelf.keyboardIsVisible = YES;
        }];
    _keyboardHideObserver = [nc addObserverForName:UIKeyboardDidHideNotification
                                            object:nil
                                             queue:[NSOperationQueue mainQueue]
                                        usingBlock:^(NSNotification* notification) {
            // TODO: set Keyboard.isVisible in JavaScript
            weakSelf.keyboardIsVisible = NO;
        }];
}

// //////////////////////////////////////////////////

- (BOOL)hideFormAccessoryBar
{
    return _hideFormAccessoryBar;
}

- (void)setHideFormAccessoryBar:(BOOL)ahideFormAccessoryBar
{
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    __weak CDVKeyboard* weakSelf = self;

    if (ahideFormAccessoryBar == _hideFormAccessoryBar) {
        return;
    }

    if (ahideFormAccessoryBar) {
        [nc removeObserver:_hideFormAccessoryBarKeyboardShowObserver];
        _hideFormAccessoryBarKeyboardShowObserver = [nc addObserverForName:UIKeyboardWillShowNotification
                                                                    object:nil
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification* notification) {
                // we can't hide it here because the accessory bar hasn't been created yet, so we delay on the queue
                [weakSelf performSelector:@selector(formAccessoryBarKeyboardWillShow:) withObject:notification afterDelay:0];
            }];

        [nc removeObserver:_hideFormAccessoryBarKeyboardHideObserver];
        _hideFormAccessoryBarKeyboardHideObserver = [nc addObserverForName:UIKeyboardWillHideNotification
                                                                    object:nil
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification* notification) {
                [weakSelf formAccessoryBarKeyboardWillHide:notification];
            }];
    } else {
        [nc removeObserver:_hideFormAccessoryBarKeyboardShowObserver];
        [nc removeObserver:_hideFormAccessoryBarKeyboardHideObserver];

        // if a keyboard is already visible (and the accessorybar was hidden), hide observer will NOT be called, so we observe it once
        if (self.keyboardIsVisible && _hideFormAccessoryBar) {
            _hideFormAccessoryBarKeyboardHideObserver = [nc addObserverForName:UIKeyboardWillHideNotification
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification* notification) {
                    [weakSelf formAccessoryBarKeyboardWillHide:notification];
                    [[NSNotificationCenter defaultCenter] removeObserver:_hideFormAccessoryBarKeyboardHideObserver];
                }];
        }
    }

    _hideFormAccessoryBar = ahideFormAccessoryBar;
}

// //////////////////////////////////////////////////

- (BOOL)shrinkView
{
    return _shrinkView;
}

- (void)setShrinkView:(BOOL)ashrinkView
{
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    __weak CDVKeyboard* weakSelf = self;

    if (ashrinkView == _shrinkView) {
        return;
    }

    if (ashrinkView) {
        [nc removeObserver:_shrinkViewKeyboardShowObserver];
        _shrinkViewKeyboardShowObserver = [nc addObserverForName:UIKeyboardWillShowNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification* notification) {
                [weakSelf performSelector:@selector(shrinkViewKeyboardWillShow:) withObject:notification afterDelay:0];
            }];

        [nc removeObserver:_shrinkViewKeyboardHideObserver];
        _shrinkViewKeyboardHideObserver = [nc addObserverForName:UIKeyboardWillHideNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification* notification) {
                [weakSelf performSelector:@selector(shrinkViewKeyboardWillHide:) withObject:notification afterDelay:0];
            }];
    } else {
        [nc removeObserver:_shrinkViewKeyboardShowObserver];
        [nc removeObserver:_shrinkViewKeyboardHideObserver];

        // if a keyboard is already visible (and keyboard was shrunk), hide observer will NOT be called, so we observe it once
        if (self.keyboardIsVisible && _shrinkView) {
            _shrinkViewKeyboardHideObserver = [nc addObserverForName:UIKeyboardWillHideNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification* notification) {
                    [weakSelf shrinkViewKeyboardWillHideHelper:notification];
                    [[NSNotificationCenter defaultCenter] removeObserver:_shrinkViewKeyboardHideObserver];
                }];
        }
    }

    _shrinkView = ashrinkView;
}

// //////////////////////////////////////////////////

CGFloat gAccessoryBarHeight = 0.0;
- (void)formAccessoryBarKeyboardWillShow:(NSNotification*)notif
{
    if (!_hideFormAccessoryBar) {
        return;
    }

    NSArray* windows = [[UIApplication sharedApplication] windows];

    for (UIWindow* window in windows) {
        for (UIView* view in window.subviews) {
            if ([[view description] hasPrefix:@"<UIPeripheralHostView"]) {
                for (UIView* peripheralView in view.subviews) {
                    // hides the backdrop (iOS 7)
                    if ([[peripheralView description] hasPrefix:@"<UIKBInputBackdropView"]) {
                        [[peripheralView layer] setOpacity:0.0];
                    }

                    // hides the accessory bar
                    if ([[peripheralView description] hasPrefix:@"<UIWebFormAccessory"]) {
                        // remove the extra scroll space for the form accessory bar
                        CGRect newFrame = self.webView.scrollView.frame;
                        newFrame.size.height += peripheralView.frame.size.height;
                        self.webView.scrollView.frame = newFrame;

                        gAccessoryBarHeight = peripheralView.frame.size.height;

                        // remove the form accessory bar
                        [peripheralView removeFromSuperview];
                    }
                    // hides the thin grey line used to adorn the bar (iOS 6)
                    if ([[peripheralView description] hasPrefix:@"<UIImageView"]) {
                        [[peripheralView layer] setOpacity:0.0];
                    }
                }
            }
        }
    }
}

- (void)formAccessoryBarKeyboardWillHide:(NSNotification*)notif
{
    // TODO: incomplete - we can't restore the accessory bar currently, this is why the public interface for the setting is readonly.
    // Not entirely sure we can restore this properly in the same hierarchy, even if we save the references

    // restore the scrollview frame
    self.webView.scrollView.frame = self.webView.frame;
}

// //////////////////////////////////////////////////

- (void)shrinkViewKeyboardWillShow:(NSNotification*)notif
{
    if (!_shrinkView) {
        return;
    }

    CGRect keyboardFrame = [notif.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboardFrame = [self.viewController.view convertRect:keyboardFrame fromView:nil];

    CGRect newFrame = self.viewController.view.bounds;
    CGFloat accessoryHeight = gAccessoryBarHeight;
    CGFloat actualKeyboardHeight = (keyboardFrame.size.height - accessoryHeight);
    newFrame.size.height -= actualKeyboardHeight;

    self.webView.frame = newFrame;
    self.webView.scrollView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0);

    if (self.disableScrollingInShrinkView) {
        self.webView.scrollView.scrollEnabled = NO;
    }
}

- (void)shrinkViewKeyboardWillHideHelper:(NSNotification*)notif
{
    self.webView.scrollView.scrollEnabled = YES;

    CGRect keyboardFrame = [notif.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboardFrame = [self.viewController.view convertRect:keyboardFrame fromView:nil];

    CGRect newFrame = self.viewController.view.bounds;
    self.webView.scrollView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0);
    self.webView.frame = newFrame;
}

- (void)shrinkViewKeyboardWillHide:(NSNotification*)notif
{
    if (_shrinkView) {
        [self shrinkViewKeyboardWillHideHelper:notif];
    }
}

// //////////////////////////////////////////////////

- (void)dealloc
{
    // since this is ARC, remove observers only

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];

    [nc removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [nc removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

@end
