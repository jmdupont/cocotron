/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSComboBoxWindow.h>
#import <AppKit/NSComboBoxView.h>

@implementation NSComboBoxWindow

-initWithFrame:(NSRect)frame {
   NSRect rect=NSZeroRect;

   [self initWithContentRect:frame styleMask:NSBorderlessWindowMask
          backing:NSBackingStoreRetained defer:NO];
   _releaseWhenClosed=YES;

   rect.size=frame.size;
   _scrollView=[[NSScrollView alloc] initWithFrame:rect];
   [_scrollView setHasVerticalScroller:NO];
   [_scrollView setHasHorizontalScroller:NO];
   [_scrollView setBorderType: NSLineBorder];

   [[self contentView] addSubview:_scrollView];

   rect.size=[_scrollView contentSize];
   _view=[[NSComboBoxView alloc] initWithFrame:rect];
   [_scrollView setDocumentView:_view];

   return self;
}

-(void)dealloc {
   [_view release];
   [_scrollView release];
   [super dealloc];
}

-(void)setObjectArray:(NSArray *)objects {
   [_view setObjectArray:objects];
}

-(void)setFont:(NSFont *)font {
   [_view setFont:font];
}

-(int)runTrackingWithEvent:(NSEvent *)event {
   NSSize  size=[_view sizeForContents];
   NSSize  scrollViewSize=[NSScrollView frameSizeForContentSize:size hasHorizontalScroller:[_scrollView hasHorizontalScroller] hasVerticalScroller:[_scrollView hasVerticalScroller] borderType:NSLineBorder];
   NSRect  frame;

   [self orderFront:nil];
// FIX, for some reason setContentSize: doesn't work before show, investigate
   frame=[self frame];
   frame.size=scrollViewSize;
   frame.origin.y-=size.height;
   [self setFrame:frame display:NO];

   [_scrollView setFrameSize:scrollViewSize];
   [_scrollView setFrameOrigin:NSMakePoint(0,0)];

   [_view setFrameSize:size];
   [_view setFrameOrigin:NSMakePoint(0,0)];

   return [_view runTrackingWithEvent:event];
}

@end
