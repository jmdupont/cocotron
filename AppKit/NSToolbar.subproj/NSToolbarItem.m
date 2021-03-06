/* Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/NSToolbarItem.h>
#import <AppKit/NSToolbar.h>
#import <AppKit/NSToolbarItemView.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSRaise.h>

NSString *NSToolbarCustomizeToolbarItemIdentifier=@"NSToolbarCustomizeToolbarItem";
NSString *NSToolbarFlexibleSpaceItemIdentifier=@"NSToolbarFlexibleSpaceItem";
NSString *NSToolbarPrintItemIdentifier=@"NSToolbarPrintItem";
NSString *NSToolbarSeparatorItemIdentifier=@"NSToolbarSeparatorItem";
NSString *NSToolbarShowColorsItemIdentifier=@"NSToolbarShowColorsItem";
NSString *NSToolbarShowFontsItemIdentifier=@"NSToolbarShowFontsItem";
NSString *NSToolbarSpaceItemIdentifier=@"NSToolbarSpaceItem";

extern NSSize _NSToolbarSizeRegular;
extern NSSize _NSToolbarSizeSmall;
extern NSSize _NSToolbarIconSizeRegular;
extern NSSize _NSToolbarIconSizeSmall;

@interface NSToolbar(private)
-(NSView *)_view;
-(void)itemSizeDidChange;
-(NSDictionary *)_labelAttributes;
-(NSDictionary *)_labelAttributesForSizeMode:(NSToolbarSizeMode)sizeMode;
@end

@implementation NSToolbarItem

extern NSSize _NSToolbarIconSizeRegular;
extern NSSize _NSToolbarIconSizeSmall;

-(void)_configureAsStandardItemIfNeeded {
   if ([_itemIdentifier isEqualToString:NSToolbarSeparatorItemIdentifier]){
    NSSize size;
    
    [self setLabel:@""];
    [self setPaletteLabel:@"Separator"];
    [self setEnabled:NO];
    
    size = [self minSize];
    size.width = floor(size.width/2);
    [self setMinSize:size];
    size = [self maxSize];
    size.width = floor(size.width/2);
    [self setMaxSize:size];
    
   }
   else if ([_itemIdentifier isEqualToString:NSToolbarSpaceItemIdentifier]){
    NSSize size;
    
    [self setLabel:@""];
    [self setPaletteLabel:@"Space"];
    [self setEnabled:NO];

    size = [self minSize];
    size.width /= 2;
    [self setMinSize:size];
    size = [self maxSize];
    size.width /= 2;
    [self setMaxSize:size];
    
   }
   else if ([_itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]){
    NSSize size;
    
    [self setLabel:@""];
    [self setPaletteLabel:@"Flexible Space"];
    [self setEnabled:NO];
    
    size = [self minSize];
    size.width /= 2;
    [self setMinSize:size];
    [self setMaxSize:NSMakeSize(-1, [self maxSize].height)];
    
   
   }
   else if ([_itemIdentifier isEqualToString:NSToolbarShowColorsItemIdentifier]){
    [self setLabel:@"Colors"];
    [self setPaletteLabel:@"Show Colors"];
    [self setTarget:[NSApplication sharedApplication]];
    [self setAction:@selector(orderFrontColorPanel:)];
    [self setImage:[NSImage imageNamed:NSToolbarShowColorsItemIdentifier]];
    [self setToolTip:@"Show the Colors panel."];
   }
   else if ([_itemIdentifier isEqualToString:NSToolbarShowFontsItemIdentifier]){
    [self setLabel:@"Fonts"];
    [self setPaletteLabel:@"Show Fonts"];
    [self setTarget:[NSFontManager sharedFontManager]];
    [self setAction:@selector(orderFrontFontPanel:)];
    [self setImage:[NSImage imageNamed:NSToolbarShowFontsItemIdentifier]];
    [self setToolTip:@"Show the Fonts panel."];
   }
   else if ([_itemIdentifier isEqualToString:NSToolbarCustomizeToolbarItemIdentifier]){
    [self setLabel:@"Customize"];
    [self setPaletteLabel:@"Customize"];
    [self setTarget:nil];
    [self setAction:@selector(runToolbarCustomizationPalette:)];
    [self setImage:[NSImage imageNamed:NSToolbarCustomizeToolbarItemIdentifier]];
    [self setToolTip:@"Customize this toolbar."];
   }
   else if ([_itemIdentifier isEqualToString:NSToolbarPrintItemIdentifier]){
    [self setLabel:@"Print"];
    [self setPaletteLabel:@"Print Document"];
    [self setTarget:nil];
    [self setAction:@selector(printDocument:)];
    [self setImage:[NSImage imageNamed:NSToolbarPrintItemIdentifier]];
    [self setToolTip:@"Print this document."];
   }
}

-initWithItemIdentifier:(NSString *)identifier {
   _itemIdentifier=[identifier retain];
   _toolbar=nil;
   _enclosingView=[[NSToolbarItemView alloc] init];
   [_enclosingView setToolbarItem:self];
   _image=nil;
   _label=@"";
   _paletteLabel=@"";
   _target=nil;
   _action=NULL;
   _menuFormRepresentation=nil;
   _view=nil;
   _minSize=NSZeroSize;
   _maxSize=NSZeroSize;
   _visibilityPriority=NSToolbarItemVisibilityPriorityStandard;
   _autovalidates=NO;
   _isEnabled=YES;
   [self _configureAsStandardItemIfNeeded];
   
   return self;
}

-(void)dealloc {
   [_itemIdentifier release];
   _toolbar=nil;   
   [_image release];
   [_label release];
   [_paletteLabel release];
   [_menuFormRepresentation release];    
   [_view release];
   [super dealloc];
}

-copyWithZone:(NSZone *)zone {
// FIXME: copying views, ugh
   NSToolbarItem *copy=NSCopyObject(self, 0, zone);

   copy->_itemIdentifier=[_itemIdentifier copy];
   copy->_toolbar=nil;
   copy->_image=[_image copy];
   copy->_label=[_label copy];
   copy->_paletteLabel=[_paletteLabel copy];
   copy->_menuFormRepresentation=[_menuFormRepresentation copy];
   copy->_view=[_view copy]; 
    
   return copy;
}

-(NSView *)_enclosingView {
   return _enclosingView;
}

-(void)_setToolbar:(NSToolbar *)toolbar {
   _toolbar = toolbar;
}

-(NSString *)itemIdentifier {
   return _itemIdentifier;
}

-(NSToolbar *)toolbar {
   return _toolbar;
}

-(NSString *)label {
   return _label;
}

-(NSString *)paletteLabel {
   return _paletteLabel;
}

// By default, this method returns a singleton menu item with item label as the title.  For standard items, the target, action is set.
- (NSMenuItem *)menuFormRepresentation
{
    // FIX should update standard item for action/target/label changes?
    if (_menuFormRepresentation == nil && [self label] != nil) {
        _menuFormRepresentation = [[NSMenuItem alloc] initWithTitle:[self label] action:[self action] keyEquivalent:@""];
        [_menuFormRepresentation setImage:[self image]];
        [_menuFormRepresentation setTarget:[self target]];
        [_menuFormRepresentation setRepresentedObject:self];
    }
    
    return _menuFormRepresentation;
}

-(NSView *)view {
   return _view;
}

-(NSSize)minSize {
   return _minSize;
}

-(NSSize)maxSize {
   return _maxSize;
}

-(NSInteger)visibilityPriority {
   return _visibilityPriority;
}

-(BOOL)autovalidates {
   return _autovalidates;
}

-(BOOL)allowsDuplicatesInToolbar {
   return NO;
}

-(void)_didChange {
   [_toolbar itemSizeDidChange];
   [_enclosingView setNeedsDisplay:YES];
}

-(void)setLabel:(NSString *)label {
// does not forward to view
   label=[label copy];
   [_label release];
   _label=label;
   [self _didChange];
}

-(void)setPaletteLabel:(NSString *)label {
// does not forward to view
    [_paletteLabel release];
    _paletteLabel = [label retain];
   [self _didChange];
}

-(void)setMenuFormRepresentation:(NSMenuItem *)menuItem {
// does not forward to view
   menuItem=[menuItem retain];
   [_menuFormRepresentation release];
   _menuFormRepresentation=menuItem;
}

-(void)setView:(NSView *)view {
   view=[view retain];
   [_view release];
   _view=view;
   
   if(view!=nil){
    _minSize=[_view frame].size;
    _maxSize=[_view frame].size;
   }
   [_enclosingView setSubview:_view];
   [self _didChange];
}

-(void)setMinSize:(NSSize)size {
   _minSize = size;
   [self _didChange];
}

-(void)setMaxSize:(NSSize)size {
   _maxSize = size;
   [self _didChange];
}

-(void)setVisibilityPriority:(NSInteger)value {
    _visibilityPriority=value;
   [self _didChange];
}

-(void)setAutovalidates:(BOOL)value {
   _autovalidates=value;
}


/* The understanding is that NSToolbarItem only forwards enabled/tag/action/target/image setters and getters to the publicly settable view. The rest are managed internally.
 */

-(NSImage *)image {
   if([_view respondsToSelector:@selector(image)])
    return [(id)_view image];

   return _image;
}

-target {
   if ([_view respondsToSelector:@selector(target)])
    return [(id)_view target];
    
   return _target;
}

-(SEL)action {
   if ([_view respondsToSelector:@selector(action)])
    return [(id)_view action];
    
   return _action;
}

-(NSInteger)tag {
   if ([_view respondsToSelector:@selector(tag)])
    return [(id)_view tag];

   return _tag;
}

-(BOOL)isEnabled {
   if([_view respondsToSelector:@selector(isEnabled)])
    return [(id)_view isEnabled];
    
   return _isEnabled;
}

-(NSString *)toolTip  {
   return _toolTip;
}

-(void)setImage:(NSImage *)image {
   image=[image retain];
   [_image release];
   _image=image;
    
   if([_view respondsToSelector:@selector(setImage:)])
    [(id)_view setImage:image];
}

-(void)setTarget:target {
   _target=target;

   if([_view respondsToSelector:@selector(setTarget:)])
    [(id)_view setTarget:target];
}

-(void)setAction:(SEL)action {
   _action=action;

   if([_view respondsToSelector:@selector(setAction:)])
    [(id)_view setAction:action];
}

-(void)setTag:(NSInteger)tag {
   _tag=tag;
   if ([_view respondsToSelector:@selector(setTag:)])
    [(id)_view setTag:tag];
}

-(void)setEnabled:(BOOL)enabled {
   _isEnabled=YES;
   if([_view respondsToSelector:@selector(setEnabled:)])
    [(id)_view setEnabled:enabled];
}

-(void)setToolTip:(NSString *)tip {
   tip=[tip copy];
   [_toolTip release];
   _toolTip=tip;
}

-(void)validate {
   if ([[self target] respondsToSelector:[self action]])
    [self setEnabled:YES];
   else
    [self setEnabled:NO];
}

-(NSSize)sizeForSizeMode:(NSToolbarSizeMode)sizeMode displayMode:(NSToolbarDisplayMode)displayMode minSize:(NSSize)minSize maxSize:(NSSize)maxSize {
   NSSize result;
   
   switch (sizeMode) {
    case NSToolbarSizeModeSmall:
     result = _NSToolbarSizeSmall;
     break;
            
    case NSToolbarSizeModeRegular:
    case NSToolbarSizeModeDefault:
    default:
     result = _NSToolbarSizeRegular;
     break;
   }        

   if (minSize.width > 0 && result.width < minSize.width)
    result.width = minSize.width;
   if (minSize.height > 0 && result.height < minSize.height)
    result.height = minSize.height;
   if (maxSize.width > 0 && result.width > maxSize.width)
    result.width = maxSize.width;
   if (maxSize.height > 0 && result.height > maxSize.height)
    result.height = maxSize.height;

   NSSize labelSize=[_label sizeWithAttributes:[_toolbar _labelAttributesForSizeMode:sizeMode]];
   labelSize.width+=8; // label margins
   
   switch (displayMode) {
    case NSToolbarDisplayModeIconOnly:
     break;
            
    case NSToolbarDisplayModeLabelOnly:
     result.height=labelSize.height;
     if(result.width<labelSize.width)
      result.width=labelSize.width;
     break;

    case NSToolbarDisplayModeIconAndLabel: 
    case NSToolbarDisplayModeDefault:
    default:
     result.height+=labelSize.height;
     if(result.width<labelSize.width)
      result.width=labelSize.width;
     break;
   }

   return result;
}

-(NSSize)sizeForSizeMode:(NSToolbarSizeMode)sizeMode displayMode:(NSToolbarDisplayMode)displayMode  {
   return [self sizeForSizeMode:sizeMode displayMode:displayMode minSize:_minSize maxSize:_maxSize];
}

-(NSSize)constrainedSize {
   return [self sizeForSizeMode:[_toolbar sizeMode] displayMode:[_toolbar displayMode] minSize:_minSize maxSize:_maxSize];
}

-(CGFloat)_expandWidth:(CGFloat)width {
   if([self view]!=nil){
    return MIN(width,_maxSize.width);
   }
    
   if([_itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier])
    return width;
   
   return [self constrainedSize].width;
}

-(void)drawInRect:(NSRect)bounds highlighted:(BOOL)highlighted {
      
   if([_itemIdentifier isEqualToString:NSToolbarSeparatorItemIdentifier]){
    bounds.origin.x = floor(bounds.origin.x + (bounds.size.width/2));
    bounds.size.width = 1;
    [[NSColor blackColor] set];
    NSDottedFrameRect(bounds);
    
    return;
   }
   CGFloat labelHeight=0;
   CGFloat padding=4;
   

   if([_toolbar displayMode]!=NSToolbarDisplayModeIconOnly){  
    NSMutableDictionary *attributes=[NSMutableDictionary dictionaryWithDictionary:[_toolbar _labelAttributes]];
    NSColor             *color=[self isEnabled]?[NSColor controlTextColor]:[NSColor disabledControlTextColor];
   
    [attributes setObject:color forKey:NSForegroundColorAttributeName];
   
    NSRect labelRect;
    labelRect.size=[_label sizeWithAttributes:attributes];
    labelRect.origin.x=floor((bounds.size.width-labelRect.size.width)/2);
    labelRect.origin.y=bounds.origin.y;

    if(!highlighted){
     NSMutableDictionary *shadowAttributes=[[attributes mutableCopy] autorelease];
     NSRect shadowRect=labelRect;
     
     [shadowAttributes setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
     
     shadowRect.origin.y--;
     
     [_label _clipAndDrawInRect:shadowRect withAttributes:shadowAttributes];
    }
    
    [_label _clipAndDrawInRect:labelRect withAttributes:attributes];
    labelHeight=labelRect.size.height;
    labelHeight+=padding;
   }

   if([_toolbar displayMode]!=NSToolbarDisplayModeLabelOnly){
    if([self view]==nil){
     NSImage *image=[self image];
     NSRect   imageRect;

     if([_toolbar sizeMode]==NSToolbarSizeModeSmall)
      imageRect.size=_NSToolbarIconSizeSmall;
     else
      imageRect.size=_NSToolbarIconSizeRegular;
          
     imageRect.origin.y=bounds.origin.y+labelHeight;
     imageRect.origin.x=bounds.origin.x+floor((bounds.size.width-imageRect.size.width)/2);
     [image drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:highlighted?0.5:1.0];
    }        
   }
    
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<%@[0x%lx] %@ label: \"%@\" image: %@ view: %@>",
        [self class], self, _itemIdentifier, _label, [self image], _view];
}

-initWithCoder:(NSCoder *)coder {
   if(![coder allowsKeyedCoding])
    NSUnimplementedMethod();
   else {
    _itemIdentifier=[[coder decodeObjectForKey:@"NSToolbarItemIdentifier"] retain];
      
    _enclosingView=[[NSToolbarItemView alloc] init];
    [_enclosingView setToolbarItem:self];
    [self setView:[coder decodeObjectForKey:@"NSToolbarItemView"]];      
    [self setTarget:[coder decodeObjectForKey:@"NSToolbarItemTarget"]];
    [self setAction:NSSelectorFromString([coder decodeObjectForKey:@"NSToolbarItemAction"])];

    [self setImage:[coder decodeObjectForKey:@"NSToolbarItemImage"]];
    [self setLabel:[coder decodeObjectForKey:@"NSToolbarItemLabel"]];
    [self setPaletteLabel:[coder decodeObjectForKey:@"NSToolbarItemPaletteLabel"]];

    _maxSize=[coder decodeSizeForKey:@"NSToolbarItemMaxSize"];
    _minSize=[coder decodeSizeForKey:@"NSToolbarItemMinSize"];
    [self setEnabled:[coder decodeBoolForKey:@"NSToolbarItemEnabled"]];
    [self setTag:[coder decodeIntForKey:@"NSToolbarItemTag"]];
      
    [self setAutovalidates:[coder decodeBoolForKey:@"NSToolbarItemAutovalidates"]];
    [self setToolTip:[coder decodeObjectForKey:@"NSToolbarItemToolTip"]];
    [self setVisibilityPriority:[coder decodeIntForKey:@"NSToolbarItemVisibilityPriority"]];
      
      /*
       NSToolbarIsUserRemovable = 1;
       */      
    [self _configureAsStandardItemIfNeeded];
   }

   return self;
}
@end

@interface NSToolbarSpaceItem : NSToolbarItem
@end

@implementation NSToolbarSpaceItem
@end


@interface NSToolbarFlexibleSpaceItem : NSToolbarItem
@end

@implementation NSToolbarFlexibleSpaceItem
@end

@interface NSToolbarSeparatorItem : NSToolbarItem
@end

@implementation NSToolbarSeparatorItem
@end

