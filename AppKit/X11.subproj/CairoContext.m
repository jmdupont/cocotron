/* Copyright (c) 2008 Johannes Fortmann
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/CairoContext.h>
#import <AppKit/X11Display.h>
#import <CoreGraphics/O2MutablePath.h>
#import <CoreGraphics/O2Color.h>
#import <Foundation/NSException.h>
#import <CoreGraphics/O2GraphicsState.h>
#import <AppKit/TTFFont.h>
#import <CoreGraphics/O2ColorSpace.h>
#import <CoreGraphics/O2Surface.h>
#import <AppKit/CairoCacheImage.h>
#import <Foundation/NSException.h>
#import <cairo/cairo-ft.h>

@implementation TTFFont (CairoFont) 
-(void)releasePlatformFont {
   cairo_font_face_destroy(_platformFont);
}

-(cairo_font_face_t*)cairoFont {
   if(!_platformFont) {
      _platformFont=(void*)cairo_ft_font_face_create_for_ft_face([self face], NULL);
   }
   return (cairo_font_face_t *)_platformFont;
}
@end



@implementation CairoContext

static inline O2GState *currentState(O2Context *self){        
   return [self->_stateStack lastObject];
}


-(id)initWithWindow:(X11Window*)w
{
   NSRect frame=[w frame];

   O2GState  *initialState=[[[O2GState alloc] initWithDeviceTransform:O2AffineTransformIdentity] autorelease];
   
   if(self=[super initWithGraphicsState:initialState])
   {
      Display *dpy=[(X11Display*)[NSDisplay currentDisplay] display];
      _surface = cairo_xlib_surface_create(dpy, [w drawable], [w visual], frame.size.width, frame.size.height);
      [self setSize:NSMakeSize(frame.size.width, frame.size.height)];
   }
   return self;
}

-(id)initWithSize:(NSSize)size
{
   O2GState  *initialState=[[[O2GState alloc] initWithDeviceTransform:O2AffineTransformIdentity] autorelease];
   
   if(self=[super initWithGraphicsState:initialState])
   {
      _surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size.width, size.height);
      _context = cairo_create(_surface);
   }
   return self;
}

-(void)dealloc
{
   cairo_surface_destroy(_surface);
   cairo_destroy(_context);
   [super dealloc];
}

-(void)setSize:(NSSize)size
{
   if(_context)
      cairo_destroy(_context);

   switch(cairo_surface_get_type(_surface))
   {
      case CAIRO_SURFACE_TYPE_XLIB:
         cairo_xlib_surface_set_size(_surface, size.width, size.height);
         break;
      case CAIRO_SURFACE_TYPE_IMAGE:
         cairo_surface_destroy(_surface);
         _surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size.width, size.height);
      default:
         ;
   }
   _dirtyRect=NSMakeRect(0, 0, size.width, size.height);
   _context = cairo_create(_surface);
}


-(void)deviceClipReset {
   cairo_reset_clip(_context);  
}

-(void)setCurrentColor:(O2Color*)color
{
   float *c=[color components];
   int count=[color numberOfComponents];

	switch(count)
   {
      case 1:
         cairo_set_source_rgba(_context,
                            c[0],
                            c[0],
                            c[0],
                            1.0);
         break;
      case 2:
         cairo_set_source_rgba(_context,
                               c[0],
                               c[0],
                               c[0],
                               c[1]);
         break;
         
      case 3:
         cairo_set_source_rgba(_context,
                               c[0],
                               c[1],
                               c[2],
                               1.0);
         break;
      case 4:
         cairo_set_source_rgba(_context,
                               c[0],
                               c[1],
                               c[2],
                               c[3]);
         break;
      default:
         NSLog(@"color with %i components", count);
         cairo_set_source_rgba(_context,
                               1.0,
                               0.0,
                               1.0,
                               1.0);
         break;
	}   
}


-(void)appendCTM
{
	O2AffineTransform ctm=O2ContextGetCTM(self);
	cairo_matrix_t matrix={ctm.a, ctm.b, ctm.c, ctm.d, ctm.tx, ctm.ty};
   

	cairo_transform(_context,&matrix);
}

-(void)synchronizeFontCTM
{
	O2AffineTransform ctm=[currentState(self) textMatrix];
    O2Float size=[currentState(self) pointSize];

	ctm = O2AffineTransformScale(ctm, size, -size);
	
	cairo_matrix_t matrix={ctm.a, ctm.b, ctm.c, ctm.d, ctm.tx, ctm.ty};

	cairo_set_font_matrix(_context, &matrix);
}


-(void)appendFlip
{
   cairo_matrix_t matrix={1, 0, 0, -1, 0, [self size].height};

	cairo_transform(_context,&matrix);
}

-(void)synchronizeLineAttributes
{
   O2GState *gState=currentState(self);
	int i;
   
	cairo_set_line_width(_context, gState->_lineWidth);
	cairo_set_line_cap(_context, gState->_lineCap);
	cairo_set_line_join(_context, gState->_lineJoin);
	cairo_set_miter_limit(_context, gState->_miterLimit);
	
	double dashLengths[gState->_dashLengthsCount];
	double totalLength=0.0;
	for(i=0; i<gState->_dashLengthsCount; i++)
	{
		dashLengths[i]=(double)gState->_dashLengths[i];
		totalLength=(double)gState->_dashLengths[i];
	}
	cairo_set_dash (_context, dashLengths, gState->_dashLengthsCount, gState->_dashPhase/totalLength);
}



-(void)setCurrentPath:(O2Path*)path
{
	unsigned             opCount=[path numberOfElements];
	const unsigned char *operators=[path elements];
	unsigned             pointCount=[path numberOfPoints];
	const NSPoint       *points=[path points];
	unsigned             i,pointIndex;
	cairo_identity_matrix(_context);
	cairo_new_path(_context);
   [self appendFlip];
	
	pointIndex=0;
	for(i=0;i<opCount;i++){
		switch(operators[i]){
            
			case kCGPathElementMoveToPoint:{
				NSPoint point=points[pointIndex++];

				cairo_move_to(_context,point.x,point.y);
			}
				break;
				
			case kCGPathElementAddLineToPoint:{
				NSPoint point=points[pointIndex++];
				
				cairo_line_to(_context,point.x,point.y);
			}
				break;
				
			case kCGPathElementAddCurveToPoint:{
				NSPoint cp1=points[pointIndex++];
				NSPoint cp2=points[pointIndex++];
				NSPoint end=points[pointIndex++];
				
				cairo_curve_to(_context,cp1.x,cp1.y,
                           cp2.x,cp2.y,
                           end.x,end.y);
			}
				break;

			case kCGPathElementAddQuadCurveToPoint:{
				NSPoint cp1=points[pointIndex++];
				NSPoint end=points[pointIndex++];
				
				cairo_curve_to(_context,cp1.x,cp1.y,
                           cp1.x,cp1.y,
                           end.x,end.y);
			}
				break;
				
			case kCGPathElementCloseSubpath:
				cairo_close_path(_context);
				break;
		}
	}
}

-(void)deviceClipToNonZeroPath:(O2Path*)path
{
	[self setCurrentPath:path];
	cairo_set_fill_rule(_context, CAIRO_FILL_RULE_WINDING);
	cairo_clip(_context);
}


-(void)drawPath:(CGPathDrawingMode)mode
{
	[self setCurrentPath:(O2Path*)_path];
   

	switch(mode)
	{
		case kCGPathStroke:
         [self setCurrentColor:[self strokeColor]];
			[self synchronizeLineAttributes];
			cairo_stroke_preserve(_context);
			break;
			
		case kCGPathFill:	
         [self setCurrentColor:[self fillColor]];
			cairo_set_fill_rule(_context, CAIRO_FILL_RULE_WINDING);
			cairo_fill_preserve(_context);
			break;
			
		case kCGPathEOFill:
         [self setCurrentColor:[self fillColor]];
			cairo_set_fill_rule(_context, CAIRO_FILL_RULE_EVEN_ODD);
			cairo_fill_preserve(_context);
			break;
			
			
		case kCGPathFillStroke:
         [self setCurrentColor:[self fillColor]];
			cairo_set_fill_rule(_context, CAIRO_FILL_RULE_WINDING);
			cairo_fill_preserve(_context);
         [self setCurrentColor:[self strokeColor]];
			[self synchronizeLineAttributes];
			cairo_stroke_preserve(_context);
			break;
			
		case kCGPathEOFillStroke:
         [self setCurrentColor:[self fillColor]];
			cairo_set_fill_rule(_context, CAIRO_FILL_RULE_EVEN_ODD);
			cairo_fill_preserve(_context);
         [self setCurrentColor:[self strokeColor]];
			[self synchronizeLineAttributes];
			cairo_stroke_preserve(_context);
			break;
	}
   
   {
      double x,y,x2,y2;
      cairo_stroke_extents(_context, &x, &y, &x2, &y2);
      _dirtyRect=NSUnionRect(_dirtyRect, NSMakeRect(x, y, x2-x, y2-y));
   }
      
   cairo_new_path(_context);
   [_path reset];
}

-(NSSize)size {
   switch(cairo_surface_get_type(_surface))
   {
      case CAIRO_SURFACE_TYPE_XLIB:
         return NSMakeSize(cairo_xlib_surface_get_width(_surface), cairo_xlib_surface_get_height(_surface));
      case CAIRO_SURFACE_TYPE_IMAGE:
         return NSMakeSize(cairo_image_surface_get_width(_surface), cairo_image_surface_get_height(_surface));
      default:
         return NSZeroSize;
   }
}

-(O2Image *)createImage {
   NSSize size=[self size];
   cairo_surface_t* img=cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size.width, size.height);
   
   cairo_t *ctx=cairo_create(img);
   
   cairo_set_source_surface(ctx, _surface, 0, 0);
   cairo_set_operator(ctx, CAIRO_OPERATOR_SOURCE);
   cairo_paint(ctx);
   
   cairo_destroy(ctx);
   
   id ret=[[CairoCacheImage alloc] initWithSurface:img];

   [ret setSize:size];
   
   cairo_surface_destroy(img);
   return ret;
}

-(void)drawShading:(O2Shading *)shading {
   if([shading isAxial]) {
      cairo_pattern_t *pat;
      pat = cairo_pattern_create_linear (0.0, 0.0,  0.0, 256.0);

   
      
      cairo_pattern_destroy(pat);
   }
}

-(void)drawImage:(id)image inRect:(CGRect)rect {
   BOOL shouldFreeImage=NO;
   cairo_surface_t *img=NULL;
   O2argb8u *data=NULL;
   
   if([image respondsToSelector:@selector(_cairoSurface)])
	{
		img=[image _cairoSurface];
	}
	else
	{
      NSAssert([image isKindOfClass:[O2Image class]], nil);
      O2Image *ki=image;
      int w=[ki width], h=[ki height], i, j;
      data=calloc(sizeof(O2argb8u), w*h);
      
      for(i=0; i<h; i++) {
         ki->_read_lRGBA8888_PRE(ki, 0, i, &data[w*i], w);
      }
      
      
      shouldFreeImage=YES;
		img=cairo_image_surface_create_for_data((unsigned char*)data,
                                              CAIRO_FORMAT_ARGB32,
                                              w,
                                              h,
                                              w*sizeof(O2argb8u));
	}
   
   NSAssert(img, nil);
   cairo_identity_matrix(_context);
   [self appendFlip];
   [self appendCTM];
   
   
   cairo_new_path(_context);
   
   cairo_translate(_context, rect.origin.x, rect.origin.y);
	cairo_rectangle(_context,
                   0, 0, rect.size.width, rect.size.height);  
   
   cairo_clip(_context);

	cairo_set_source_surface(_context, img, 0.0, 0.0);

	cairo_paint(_context);
   
   {
      double x,y,x2,y2;
      cairo_clip_extents(_context, &x, &y, &x2, &y2);
      _dirtyRect=NSUnionRect(_dirtyRect, NSMakeRect(x, y, x2-x, y2-y));
   }
   
   if(shouldFreeImage) {
      cairo_surface_destroy(img);
      free(data);
   }
}

-(void)establishFontStateInDeviceIfDirty {
   O2GState *gState=currentState(self);
   
   if(gState->_fontIsDirty){
    [gState clearFontIsDirty];

    O2Font *cgFont=[gState font];
    KTFont *fontState=[[TTFFont alloc] initWithFont:cgFont size:[gState pointSize]];
    NSString    *name=[fontState name];
    CGFloat      pointSize=[fontState pointSize];
   
    [gState setFontState:fontState];
    [fontState release];
   }
}


-(void)showGlyphs:(const CGGlyph *)glyphs count:(unsigned)count {
   [self establishFontStateInDeviceIfDirty];
   
   TTFFont *fontState=(TTFFont*)[currentState(self) fontState];
   int i;
   cairo_glyph_t *cg=alloca(sizeof(cairo_glyph_t)*count);
   BOOL nominal;

   float x=0, y=0;
   for(i=0; i<count; i++)
   {
      NSPoint pos=[fontState positionOfGlyph:glyphs[i] precededByGlyph:CGNullGlyph isNominal:&nominal];
      
      cg[i].x=x;
      cg[i].y=y+pos.y;
      cg[i].index=glyphs[i];
      x+=pos.x;
   }
   
   cairo_font_face_t *face=[[currentState(self) fontState] cairoFont];
   cairo_set_font_face(_context, face);
   cairo_set_font_size(_context, [fontState pointSize]);
   
   cairo_identity_matrix(_context);

   [self appendFlip];

   [self appendCTM];
   [self synchronizeFontCTM];
   [self setCurrentColor:[self fillColor]];
   cairo_move_to(_context, 0, 0);
   
   cairo_show_glyphs(_context, cg, count);
   
}

-(void)showText:(const char *)text length:(unsigned)length {
   [self establishFontStateInDeviceIfDirty];

   unichar unicode[length];
   CGGlyph glyphs[length];
   int     i;
   
   id str=[NSString stringWithUTF8String:text];
   [str getCharacters:unicode range:NSMakeRange(0, length)]; 
    
   [(KTFont*)[currentState(self) fontState] getGlyphs:glyphs forCharacters:unicode length:length];
   [self showGlyphs:glyphs count:length];
}

-(void)flush {
   cairo_surface_flush(_surface);
}

-(cairo_surface_t*)_cairoSurface {
   return _surface;
}


cairo_status_t writeToData(void		  *closure,
                           const unsigned char *data,
                           unsigned int	   length) {
   id obj=(id)closure;
   [obj appendBytes:data length:length];
   return CAIRO_STATUS_SUCCESS;
}

-(NSData *)captureBitmapInRect:(CGRect)rect {
   id ret=[NSMutableData data];
   
   cairo_surface_t *surf=cairo_image_surface_create(CAIRO_FORMAT_ARGB32, rect.size.width, rect.size.height);
   cairo_t *ctx=cairo_create(surf);
   
   cairo_identity_matrix(ctx);
   cairo_reset_clip(ctx);

   cairo_set_source_surface (ctx, _surface, -rect.origin.x, -rect.origin.y);
   
	cairo_paint(ctx);   
   
   cairo_destroy(ctx);
   cairo_surface_write_to_png_stream(surf, writeToData, ret);
   
   cairo_surface_destroy(surf);
   return ret;   
}

-(void)addToDirtyRect:(NSRect)rect {
   _dirtyRect=NSUnionRect(_dirtyRect, rect);
}

-(NSRect)dirtyRect; {
   return _dirtyRect;
}

-(void)resetDirtyRect; {
   _dirtyRect=NSZeroRect;
}

-(void)copyFromBackingContext:(CairoContext*)other
{
   NSRect clip=[other dirtyRect];
   
   if(NSIsEmptyRect(clip))
      return;
   
   cairo_identity_matrix(_context);
   cairo_reset_clip(_context);
   
   
   O2AffineTransform matrix={1, 0, 0, -1, 0, [self size].height};
   clip.origin=O2PointApplyAffineTransform(clip.origin,matrix);
   clip.origin.y-=clip.size.height;
   
   
   cairo_new_path(_context);
   cairo_rectangle(_context, clip.origin.x, clip.origin.y, clip.size.width, clip.size.height);
   cairo_clip(_context);
   cairo_set_source_surface (_context, [other _cairoSurface], 0, 0);
   
	cairo_paint(_context);
   [other resetDirtyRect];
}

@end
