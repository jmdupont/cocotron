/*------------------------------------------------------------------------
 *
 * Derivative of the OpenVG 1.0.1 Reference Implementation
 * -------------------------------------
 *
 * Copyright (c) 2007 The Khronos Group Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and /or associated documentation files
 * (the "Materials "), to deal in the Materials without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Materials,
 * and to permit persons to whom the Materials are furnished to do so,
 * subject to the following conditions: 
 *
 * The above copyright notice and this permission notice shall be included 
 * in all copies or substantial portions of the Materials. 
 *
 * THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE MATERIALS OR
 * THE USE OR OTHER DEALINGS IN THE MATERIALS.
 *
 *-------------------------------------------------------------------*/

#import "VGPath.h"
#import "VGmath.h"

static inline void		RI_SWAP(CGFloat *a, CGFloat *b)				{ CGFloat tmp = *a; *a = *b; *b = tmp; }
static inline CGFloat	RI_RAD_TO_DEG(CGFloat a)					{ return (CGFloat)(a * 180.0f/ M_PI); }

static inline CGPoint Vector2Negate(CGPoint result){
   return CGPointMake(-result.x,-result.y);
}

static inline CGFloat Vector2Length(CGPoint v){
   return sqrt((double)v.x*(double)v.x+(double)v.y*(double)v.y);
}

static inline BOOL Vector2IsEqual(CGPoint v1,CGPoint v2 ){
   return (v1.x == v2.x) && (v1.y == v2.y);
}

static inline BOOL Vector2IsZero(CGPoint v){
  return (v.x == 0.0f) && (v.y == 0.0f);
}

static inline CGPoint Vector2MultiplyByFloat(CGPoint v,CGFloat f){
   return CGPointMake(v.x*f,v.y*f);
}

static inline CGPoint Vector2Add(CGPoint v1,CGPoint v2 ){
   return CGPointMake(v1.x+v2.x, v1.y+v2.y);
}

//if v is a zero vector, returns a zero vector
static inline CGPoint Vector2Normalize(CGPoint v){
   double l = (double)v.x*(double)v.x+(double)v.y*(double)v.y;
   
   if( l != 0.0 )
    l = 1.0 / sqrt(l);
    
   return CGPointMake((CGFloat)((double)v.x * l), (CGFloat)((double)v.y * l));
}

static inline CGPoint Vector2PerpendicularCW(CGPoint v){
   return CGPointMake(v.y, -v.x);
}

static inline CGPoint Vector2PerpendicularCCW(CGPoint v){
   return CGPointMake(-v.y, v.x);
}

static inline CGPoint Vector2Perpendicular(CGPoint v, BOOL cw){
   if(cw)
    return CGPointMake(v.y, -v.x);
    
   return CGPointMake(-v.y, v.x);
}


enum VertexFlags {
   START_SUBPATH			= (1<<0),
   END_SUBPATH				= (1<<1),
   START_SEGMENT			= (1<<2),
   END_SEGMENT				= (1<<3),
   CLOSE_SUBPATH			= (1<<4),
   IMPLICIT_CLOSE_SUBPATH	= (1<<5)
};

typedef struct Vertex {
   CGPoint			userPosition;
   CGPoint			userTangent;
   CGFloat			pathLength;
   unsigned int	flags;
} Vertex;
    
	//data produced by tessellation
typedef struct VertexIndex {
   int		start;
   int		end;
} VertexIndex;

typedef struct  {
   CGPoint			p;
   CGPoint			t;
   CGPoint			ccw;
   CGPoint			cw;
   CGFloat			pathLength;
   unsigned int	flags;
   BOOL			inDash;
} StrokeVertex;
    
static inline StrokeVertex StrokeVertexInit(){
   StrokeVertex result;
   
   result.p=CGPointMake(0,0);
   result.t=CGPointMake(0,0);
   result.ccw=CGPointMake(0,0);
   result.cw=CGPointMake(0,0);
   result.pathLength=0;
   result.flags=0;
   result.inDash=NO;
        
   return result;
}

#define RI_FLOAT_MAX FLT_MAX

/*-------------------------------------------------------------------*//*!
* \brief	Form a reliable normalized average of the two unit input vectors.
*           The average always lies to the given direction from the first
*			vector.
* \param	u0, u1 Unit input vectors.
* \param	cw True if the average should be clockwise from u0, NO if
*              counterclockwise.
* \return	Average of the two input vectors.
* \note		
*//*-------------------------------------------------------------------*/

static CGPoint unitAverageWithDirection(CGPoint u0, CGPoint u1, BOOL cw) {
   CGPoint u =Vector2MultiplyByFloat(Vector2Add(u0 , u1), 0.5f);
   CGPoint n0 = Vector2PerpendicularCCW(u0);

   if( Vector2Dot(u, u) > 0.25f ){
    //the average is long enough and thus reliable
    if( Vector2Dot(n0, u1) < 0.0f )
     u = Vector2Negate(u);	//choose the larger angle
   }
   else {
    // the average is too short, use the average of the normals to the vectors instead
    CGPoint n1 = Vector2PerpendicularCW(u1);
    u = Vector2MultiplyByFloat(Vector2Add(n0 , n1), 0.5f);
   }
   
   if( cw )
    u = Vector2Negate(u);

   return Vector2Normalize(u);
}

/*-------------------------------------------------------------------*//*!
* \brief	Form a reliable normalized average of the two unit input vectors.
*			The average lies on the side where the angle between the input
*			vectors is less than 180 degrees.
* \param	u0, u1 Unit input vectors.
* \return	Average of the two input vectors.
* \note		
*//*-------------------------------------------------------------------*/

static CGPoint unitAverage(CGPoint u0, CGPoint u1){
   CGPoint u =Vector2MultiplyByFloat(Vector2Add(u0 , u1), 0.5f);

   if( Vector2Dot(u, u) < 0.25f ){
   	// the average is unreliable, use the average of the normals to the vectors instead
    CGPoint n0 = Vector2PerpendicularCCW(u0);
    CGPoint n1 = Vector2PerpendicularCW(u1);
    u = Vector2MultiplyByFloat(Vector2Add(n0 , n1) , 0.5f);
    if( Vector2Dot(n1, u0) < 0.0f )
     u = Vector2Negate(u);
   }

   return Vector2Normalize(u);
}

// Interpolate the given unit tangent vectors to the given direction on a unit circle.

static CGPoint circularLerpWithDirection(CGPoint t0, CGPoint t1, CGFloat ratio, BOOL cw) {
   CGPoint u0 = t0, u1 = t1;
   CGFloat l0 = 0.0f, l1 = 1.0f;
   int i;
    
   for(i=0;i<8;i++) {
    CGPoint n = unitAverageWithDirection(u0, u1, cw);
    CGFloat l = 0.5f * (l0 + l1);
    if( ratio < l ){
     u1 = n;
     l1 = l;
    }
    else {
     u0 = n;
     l0 = l;
    }
   }
    
   return u0;
}

// Interpolate the given unit tangent vectors on a unit circle. Smaller angle between the vectors is used.

static CGPoint circularLerp(CGPoint t0, CGPoint t1, CGFloat ratio){
   CGPoint u0 = t0, u1 = t1;
   CGFloat l0 = 0.0f, l1 = 1.0f;
   int i;
   
   for(i=0;i<8;i++) {
    CGPoint n = unitAverage(u0, u1);
    CGFloat l = 0.5f * (l0 + l1);
    if( ratio < l ){
     u1 = n;
     l1 = l;
    }
    else {
     u0 = n;
     l0 = l;
    }
   }
   
   return u0;
}

@implementation VGPath

-initWithKGPath:(O2Path *)path {
   _path=[path retain];
	self->m_userMinx=0.0f;
	self->m_userMiny=0.0f;
	self->m_userMaxx=0.0f;
	self->m_userMaxy=0.0f;
    self->_vertexCount=0;
    self->_vertexCapacity=2;
    self->_vertices=NSZoneMalloc(NULL,self->_vertexCapacity*sizeof(Vertex));
    self->_segmentToVertexCapacity=2;
    self->_segmentToVertex=NSZoneMalloc(NULL,self->_segmentToVertexCapacity*sizeof(VertexIndex));
    return self;
}

-(void)dealloc {
   NSZoneFree(NULL,self->_vertices);
   NSZoneFree(NULL,self->_segmentToVertex);
   [super dealloc];
}

/// Given a path segment type, returns the number of coordinates it uses.

int CGPathElementTypeToNumCoordinates(CGPathElementType segment){
	RI_ASSERT(((int)segment) >= 0 && ((int)segment) <= 4);
	static const int coords[5] = {1,1,2,3,0};
	return coords[(int)segment];
}

// Computes the number of coordinates a segment sequence uses.

int VGPathCountNumCoordinates(const uint8_t* segments, int numSegments){
   RI_ASSERT(segments);
   RI_ASSERT(numSegments >= 0);

   int coordinates = 0;
   int i;
   for(i=0;i<numSegments;i++)
    coordinates += CGPathElementTypeToNumCoordinates((CGPathElementType)segments[i]);
    
   return coordinates;
}

// Tessellates a path for filling and appends resulting edges to a rasterizer.

void VGPathFill(VGPath *self,CGAffineTransform pathToSurface, KGRasterizer *rasterizer){

   VGPathTessellateIfNeeded(self);

   CGPoint p0=CGPointMake(0,0);
   int     i;
   
   for(i=0;i<self->_vertexCount;i++){
    CGPoint p1 = CGPointApplyAffineTransform(self->_vertices[i].userPosition,pathToSurface );

    if(!(self->_vertices[i].flags & START_SEGMENT)){
    	//in the middle of a segment
     O2DContextAddEdge(rasterizer,p0, p1);
    }

    p0 = p1;
   }
}

/* Smoothly interpolates between two StrokeVertices. Positions
   are interpolated linearly, while tangents are interpolated
   on a unit circle. Stroking is implemented so that overlapping
   geometry doesnt cancel itself when filled with nonzero rule.
   The resulting polygons are closed. */


void VGPathInterpolateStroke(CGAffineTransform pathToSurface, KGRasterizer *rasterizer,StrokeVertex v0,StrokeVertex v1, CGFloat strokeWidth){
	CGPoint ppccw = CGPointApplyAffineTransform(v0.ccw,pathToSurface);
	CGPoint ppcw = CGPointApplyAffineTransform(v0.cw,pathToSurface);
	CGPoint endccw = CGPointApplyAffineTransform(v1.ccw,pathToSurface);
	CGPoint endcw = CGPointApplyAffineTransform(v1.cw,pathToSurface);

	const CGFloat tessellationAngle = 5.0f;

	CGFloat angle = RI_RAD_TO_DEG((CGFloat)acos(RI_CLAMP(Vector2Dot(v0.t, v1.t), -1.0f, 1.0f))) / tessellationAngle;
	int samples = RI_INT_MAX((int)ceil(angle), 1);
	CGPoint prev = v0.p;
	CGPoint prevt = v0.t;
	CGPoint position = v0.p;
	CGPoint pnccw = ppccw;
	CGPoint pncw = ppcw;
    int     j;
    
	for(j=0;j<samples;j++){
		CGFloat t = (CGFloat)(j+1) / (CGFloat)samples;
		position = Vector2Add(Vector2MultiplyByFloat(v0.p , (1.0f - t)) , Vector2MultiplyByFloat(v1.p ,t));
		CGPoint tangent = circularLerp(v0.t, v1.t, t);
		CGPoint n = Vector2MultiplyByFloat(Vector2Normalize(Vector2PerpendicularCCW(tangent)) , strokeWidth * 0.5f);

		if(j == samples-1)
			position = v1.p;

		CGPoint npccw = CGPointApplyAffineTransform(Vector2Add(prev, n),pathToSurface);
		CGPoint npcw = CGPointApplyAffineTransform(Vector2Subtract(prev, n),pathToSurface);
		CGPoint nnccw = CGPointApplyAffineTransform(Vector2Add(position,n),pathToSurface);
		CGPoint nncw = CGPointApplyAffineTransform(Vector2Subtract(position , n),pathToSurface);

		O2DContextAddEdge(rasterizer,npccw, nnccw);
		O2DContextAddEdge(rasterizer,nnccw, nncw);
		O2DContextAddEdge(rasterizer,nncw, npcw);	
		O2DContextAddEdge(rasterizer,npcw, npccw);

		if(Vector2Dot(n,prevt) <= 0.0f){
			O2DContextAddEdge(rasterizer,pnccw, npcw);
			O2DContextAddEdge(rasterizer,npcw, pncw);	
			O2DContextAddEdge(rasterizer,pncw, npccw);
			O2DContextAddEdge(rasterizer,npccw, pnccw);
		}
		else {
			O2DContextAddEdge(rasterizer,pnccw, npccw);
			O2DContextAddEdge(rasterizer,npccw, pncw);
			O2DContextAddEdge(rasterizer,pncw, npcw);	
			O2DContextAddEdge(rasterizer,npcw, pnccw);
		}

		ppccw = npccw;
		ppcw = npcw;
		pnccw = nnccw;
		pncw = nncw;
		prev = position;
		prevt = tangent;
	}

	//connect the last segment to the end coordinates
	CGPoint n = Vector2PerpendicularCCW(v1.t);
    
   if(Vector2Dot(n,prevt) <= 0.0f){
    O2DContextAddEdge(rasterizer,pnccw, endcw);
    O2DContextAddEdge(rasterizer,endcw, pncw);
    O2DContextAddEdge(rasterizer,pncw, endccw);
    O2DContextAddEdge(rasterizer,endccw, pnccw);
   }
   else {
    O2DContextAddEdge(rasterizer,pnccw, endccw);
    O2DContextAddEdge(rasterizer,endccw, pncw);
    O2DContextAddEdge(rasterizer,pncw, endcw);
    O2DContextAddEdge(rasterizer,endcw, pnccw);
   }
}

// Generate edges for stroke caps. Resulting polygons are closed.

void VGPathDoCap(CGAffineTransform pathToSurface, KGRasterizer *rasterizer,StrokeVertex v, CGFloat strokeWidth, CGLineCap capStyle){
	CGPoint ccwt = CGPointApplyAffineTransform(v.ccw,pathToSurface);
	CGPoint cwt = CGPointApplyAffineTransform(v.cw,pathToSurface);

	switch(capStyle){
    
	case kCGLineCapButt:
		break;

	case kCGLineCapRound: {
		const CGFloat tessellationAngle = 5.0f;

		CGFloat angle = 180.0f / tessellationAngle;

		int samples = (int)ceil(angle);
		CGFloat step = 1.0f / samples;
		CGFloat t = step;
		CGPoint u0 = Vector2Normalize(Vector2Subtract(v.ccw,v.p));
		CGPoint u1 = Vector2Normalize(Vector2Subtract(v.cw,v.p));
		CGPoint prev = ccwt;
		O2DContextAddEdge(rasterizer,cwt, ccwt);
        int j;
        
		for(j=1;j<samples;j++){
			CGPoint next = Vector2Add(v.p , Vector2MultiplyByFloat(circularLerpWithDirection(u0, u1, t, YES) , strokeWidth * 0.5f));
			next = CGPointApplyAffineTransform(next,pathToSurface);

			O2DContextAddEdge(rasterizer,prev, next);
			prev = next;
			t += step;
		}
		O2DContextAddEdge(rasterizer,prev, cwt);
		break;
	}

	case kCGLineCapSquare: {
		CGPoint t = v.t;
		t=Vector2Normalize(t);
		CGPoint ccws = CGPointApplyAffineTransform(Vector2Add(v.ccw , Vector2MultiplyByFloat(t , strokeWidth * 0.5f)),pathToSurface );
		CGPoint cws = CGPointApplyAffineTransform(Vector2Add(v.cw , Vector2MultiplyByFloat(t , strokeWidth * 0.5f)),pathToSurface );
		O2DContextAddEdge(rasterizer,cwt, ccwt);
		O2DContextAddEdge(rasterizer,ccwt, ccws);
		O2DContextAddEdge(rasterizer,ccws, cws);
		O2DContextAddEdge(rasterizer,cws, cwt);
		break;
	}
	}
}

// Generate edges for stroke joins. Resulting polygons are closed.

void VGPathDoJoin(CGAffineTransform pathToSurface, KGRasterizer *rasterizer, StrokeVertex v0, StrokeVertex v1, CGFloat strokeWidth, CGLineJoin joinStyle, CGFloat miterLimit){
	CGPoint ccw0t = CGPointApplyAffineTransform(v0.ccw,pathToSurface);
	CGPoint cw0t = CGPointApplyAffineTransform(v0.cw,pathToSurface);
	CGPoint ccw1t = CGPointApplyAffineTransform(v1.ccw,pathToSurface);
	CGPoint cw1t = CGPointApplyAffineTransform(v1.cw,pathToSurface);
	CGPoint m0t = CGPointApplyAffineTransform(v0.p,pathToSurface);
	CGPoint m1t = CGPointApplyAffineTransform(v1.p,pathToSurface);

	CGPoint tccw = Vector2Subtract(v1.ccw,v0.ccw);
	CGPoint s, e, m, st, et;
	BOOL cw;

	if( Vector2Dot(tccw, v0.t) > 0.0f )
	{	//draw ccw miter (draw from point 0 to 1)
		s = ccw0t;
		e = ccw1t;
		st = v0.t;
		et = v1.t;
		m = v0.ccw;
		cw = NO;
		O2DContextAddEdge(rasterizer,m0t, ccw0t);
		O2DContextAddEdge(rasterizer,ccw1t, m1t);
		O2DContextAddEdge(rasterizer,m1t, m0t);
	}
	else
	{	//draw cw miter (draw from point 1 to 0)
		s = cw1t;
		e = cw0t;
		st = v1.t;
		et = v0.t;
		m = v0.cw;
		cw = YES;
		O2DContextAddEdge(rasterizer,cw0t, m0t);
		O2DContextAddEdge(rasterizer,m1t, cw1t);
		O2DContextAddEdge(rasterizer,m0t, m1t);
	}

	switch(joinStyle)
	{
	case kCGLineJoinMiter:
	{
		CGFloat theta = (CGFloat)acos(RI_CLAMP(Vector2Dot(v0.t, Vector2Negate(v1.t)), -1.0f, 1.0f));
		CGFloat miterLengthPerStrokeWidth = 1.0f / (CGFloat)sin(theta*0.5f);
		if( miterLengthPerStrokeWidth < miterLimit )
		{	//miter
			CGFloat l = (CGFloat)cos(theta*0.5f) * miterLengthPerStrokeWidth * (strokeWidth * 0.5f);
			l = RI_MIN(l, RI_FLOAT_MAX);	//force finite
			CGPoint c = Vector2Add(m , Vector2MultiplyByFloat(v0.t, l));
			c = CGPointApplyAffineTransform(c,pathToSurface);
			O2DContextAddEdge(rasterizer,s, c);
			O2DContextAddEdge(rasterizer,c, e);
		}
		else
		{	//bevel
			O2DContextAddEdge(rasterizer,s, e);
		}
		break;
	}

	case kCGLineJoinRound:
	{
		const CGFloat tessellationAngle = 5.0f;

		CGPoint prev = s;
		CGFloat angle = RI_RAD_TO_DEG((CGFloat)acos(RI_CLAMP(Vector2Dot(st, et), -1.0f, 1.0f))) / tessellationAngle;
		int samples = (int)ceil(angle);
		if( samples )
		{
			CGFloat step = 1.0f / samples;
			CGFloat t = step;
            int     j;
			for(j=1;j<samples;j++)
			{
				CGPoint position = Vector2Add(Vector2MultiplyByFloat(v0.p , (1.0f - t)) , Vector2MultiplyByFloat(v1.p , t));
				CGPoint tangent = circularLerpWithDirection(st, et, t, YES);

				CGPoint next = Vector2Add(position , Vector2MultiplyByFloat(Vector2Normalize(Vector2Perpendicular(tangent, cw)) , strokeWidth * 0.5f));
				next = CGPointApplyAffineTransform(next,pathToSurface);

				O2DContextAddEdge(rasterizer,prev, next);
				prev = next;
				t += step;
			}
		}
		O2DContextAddEdge(rasterizer,prev, e);
		break;
	}

	case kCGLineJoinBevel:
		if(!cw)
			O2DContextAddEdge(rasterizer,ccw0t, ccw1t);
		else
			O2DContextAddEdge(rasterizer,cw1t, cw0t);	
		break;
	}
}

// Tessellate a path, apply stroking, dashing, caps and joins, and append resulting edges to a rasterizer.

void VGPathStroke(VGPath *self,CGAffineTransform pathToSurface, KGRasterizer *rasterizer, const CGFloat* dashPattern,int dashPatternSize, CGFloat dashPhase, BOOL dashPhaseReset, CGFloat strokeWidth, CGLineCap capStyle, CGLineJoin joinStyle, CGFloat miterLimit){
	RI_ASSERT(strokeWidth >= 0.0f);
	RI_ASSERT(miterLimit >= 1.0f);

	VGPathTessellateIfNeeded(self);

	if(!self->_vertexCount)
		return;

	BOOL dashing = YES;

	if( dashPatternSize & 1 )
		dashPatternSize--;	//odd number of dash pattern entries, discard the last one
	CGFloat dashPatternLength = 0.0f;
    int     i;
	for(i=0;i<dashPatternSize;i++)
		dashPatternLength += RI_MAX(dashPattern[i], 0.0f);
	if(!dashPatternSize || dashPatternLength == 0.0f )
		dashing = NO;
	dashPatternLength = RI_MIN(dashPatternLength, RI_FLOAT_MAX);

	//walk along the path
	//stop at the next event which is either:
	//-path vertex
	//-dash stop
	//for robustness, decisions based on geometry are done only once.
	//inDash keeps track whether the last point was in dash or not

	//loop vertex events
	{
		CGFloat nextDash = 0.0f;
		int d = 0;
		BOOL inDash = YES;
		StrokeVertex v0=StrokeVertexInit(), v1=StrokeVertexInit(), vs=StrokeVertexInit();
        
		for(i=0;i<self->_vertexCount;i++)
		{
			//read the next vertex
			const Vertex v = self->_vertices[i];
			v1.p = v.userPosition;
			v1.t = v.userTangent;
			RI_ASSERT(!Vector2IsZero(v1.t));	//don't allow zero tangents
			v1.ccw = Vector2Add(v1.p , Vector2MultiplyByFloat(Vector2Normalize(Vector2PerpendicularCCW(v1.t)) , strokeWidth * 0.5f));
			v1.cw = Vector2Add(v1.p , Vector2MultiplyByFloat(Vector2Normalize(Vector2PerpendicularCW(v1.t)) , strokeWidth * 0.5f));
			v1.pathLength = v.pathLength;
			v1.flags = v.flags;
			v1.inDash = dashing ? inDash : YES;	//NOTE: for other than START_SEGMENT vertices inDash will be updated after dashing

			//process the vertex event
			if(v.flags & START_SEGMENT)
			{
				if(v.flags & START_SUBPATH)
				{
					if( dashing )
					{	//initialize dashing by finding which dash or gap the first point of the path lies in
						if(dashPhaseReset || i == 0)
						{
							d = 0;
							inDash = YES;
							nextDash = v1.pathLength - RI_MOD(dashPhase, dashPatternLength);
							for(;;)
							{
								CGFloat prevDash = nextDash;
								nextDash = prevDash + RI_MAX(dashPattern[d], 0.0f);
								if(nextDash >= v1.pathLength)
									break;

								if( d & 1 )
									inDash = YES;
								else
									inDash = NO;
								d = (d+1) % dashPatternSize;
							}
							v1.inDash = inDash;
							//the first point of the path lies between prevDash and nextDash
							//d in the index of the next dash stop
							//inDash is YES if the first point is in a dash
						}
					}
					vs = v1;	//save the subpath start point
				}
				else
				{
					if( v.flags & IMPLICIT_CLOSE_SUBPATH )
					{	//do caps for the start and end of the current subpath
						if( v0.inDash )
							VGPathDoCap(pathToSurface, rasterizer, v0, strokeWidth, capStyle);	//end cap
						if( vs.inDash )
						{
							StrokeVertex vi = vs;
							vi.t = Vector2Negate(vi.t);
							RI_SWAP(&vi.ccw.x, &vi.cw.x);
							RI_SWAP(&vi.ccw.y, &vi.cw.y);
							VGPathDoCap(pathToSurface, rasterizer, vi, strokeWidth, capStyle);	//start cap
						}
					}
					else
					{	//join two segments
						RI_ASSERT(v0.inDash == v1.inDash);
						if( v0.inDash )
							VGPathDoJoin(pathToSurface, rasterizer, v0, v1, strokeWidth, joinStyle, miterLimit);
					}
				}
			}
			else
			{	//in the middle of a segment
				if( !(v.flags & IMPLICIT_CLOSE_SUBPATH) )
				{	//normal segment, do stroking
					if( dashing )
					{
						StrokeVertex prevDashVertex = v0;	//dashing of the segment starts from the previous vertex

						if(nextDash + 10000.0f * dashPatternLength < v1.pathLength)
                            NSLog(@"too many dashes");

						//loop dash events until the next vertex event
						//zero length dashes are handled as a special case since if they hit the vertex,
						//we want to include their starting point to this segment already in order to generate a join
						int numDashStops = 0;
						while(nextDash < v1.pathLength || (nextDash <= v1.pathLength && dashPattern[(d+1) % dashPatternSize] == 0.0f))
						{
							CGFloat edgeLength = v1.pathLength - v0.pathLength;
							CGFloat ratio = 0.0f;
							if(edgeLength > 0.0f)
								ratio = (nextDash - v0.pathLength) / edgeLength;
							StrokeVertex nextDashVertex=StrokeVertexInit();
							nextDashVertex.p = Vector2Add(Vector2MultiplyByFloat(v0.p , (1.0f - ratio)) , Vector2MultiplyByFloat(v1.p , ratio));
							nextDashVertex.t = circularLerp(v0.t, v1.t, ratio);
							nextDashVertex.ccw = Vector2Add(nextDashVertex.p , Vector2MultiplyByFloat(Vector2Normalize(Vector2PerpendicularCCW(nextDashVertex.t)) , strokeWidth * 0.5f));
							nextDashVertex.cw = Vector2Add(nextDashVertex.p , Vector2MultiplyByFloat(Vector2Normalize(Vector2PerpendicularCW(nextDashVertex.t)) , strokeWidth * 0.5f));

							if( inDash )
							{	//stroke from prevDashVertex -> nextDashVertex
								if( numDashStops )
								{	//prevDashVertex is not the start vertex of the segment, cap it (start vertex has already been joined or capped)
									StrokeVertex vi = prevDashVertex;
									vi.t = Vector2Negate(vi.t);
									RI_SWAP(&vi.ccw.x, &vi.cw.x);
									RI_SWAP(&vi.ccw.y, &vi.cw.y);
									VGPathDoCap(pathToSurface, rasterizer, vi, strokeWidth, capStyle);
								}
								VGPathInterpolateStroke(pathToSurface, rasterizer, prevDashVertex, nextDashVertex, strokeWidth);
								VGPathDoCap(pathToSurface, rasterizer, nextDashVertex, strokeWidth, capStyle);	//end cap
							}
							prevDashVertex = nextDashVertex;

							if( d & 1 )
							{	//dash starts
								RI_ASSERT(!inDash);
								inDash = YES;
							}
							else
							{	//dash ends
								RI_ASSERT(inDash);
								inDash = NO;
							}
							d = (d+1) % dashPatternSize;
							nextDash += RI_MAX(dashPattern[d], 0.0f);
							numDashStops++;
						}
						
						if( inDash )
						{	//stroke prevDashVertex -> v1
							if( numDashStops )
							{	//prevDashVertex is not the start vertex of the segment, cap it (start vertex has already been joined or capped)
								StrokeVertex vi = prevDashVertex;
								vi.t = Vector2Negate(vi.t);
								RI_SWAP(&vi.ccw.x, &vi.cw.x);
								RI_SWAP(&vi.ccw.y, &vi.cw.y);
								VGPathDoCap(pathToSurface, rasterizer, vi, strokeWidth, capStyle);
							}
							VGPathInterpolateStroke(pathToSurface, rasterizer, prevDashVertex, v1, strokeWidth);
							//no cap, leave path open
						}

						v1.inDash = inDash;	//update inDash status of the segment end point
					}
					else	//no dashing, just interpolate segment end points
						VGPathInterpolateStroke(pathToSurface, rasterizer, v0, v1, strokeWidth);
				}
			}

			if((v.flags & END_SEGMENT) && (v.flags & CLOSE_SUBPATH))
			{	//join start and end of the current subpath
				if( v1.inDash && vs.inDash )
					VGPathDoJoin(pathToSurface, rasterizer, v1, vs, strokeWidth, joinStyle, miterLimit);
				else
				{	//both start and end are not in dash, cap them
					if( v1.inDash )
						VGPathDoCap(pathToSurface, rasterizer, v1, strokeWidth, capStyle);	//end cap
					if( vs.inDash )
					{
						StrokeVertex vi = vs;
						vi.t = Vector2Negate(vi.t);
						RI_SWAP(&vi.ccw.x, &vi.cw.x);
						RI_SWAP(&vi.ccw.y, &vi.cw.y);
						VGPathDoCap(pathToSurface, rasterizer, vi, strokeWidth, capStyle);	//start cap
					}
				}
			}

			v0 = v1;
		}
	}

}

// Tessellates a path, and returns a position and a tangent on the path given a distance along the path.

void VGPathGetPointAlong(VGPath *self,int startIndex, int numSegments, CGFloat distance, CGPoint *p, CGPoint *t){
	RI_ASSERT(startIndex >= 0 && startIndex + numSegments <= self->_numberOfElements && numSegments > 0);

	VGPathTessellateIfNeeded(self);

	RI_ASSERT(startIndex >= 0 && startIndex < self->_numberOfElements);
	RI_ASSERT(startIndex + numSegments >= 0 && startIndex + numSegments <= self->_numberOfElements);

	int startVertex = self->_segmentToVertex[startIndex].start;
	int endVertex = self->_segmentToVertex[startIndex + numSegments - 1].end;

	if(!self->_vertexCount || (startVertex == -1 && endVertex == -1))
	{	// no vertices in the tessellated path. The path is empty or consists only of zero-length segments.
		*p=CGPointMake(0,0);
		*t=CGPointMake(1,0);
		return;
	}
	if(startVertex == -1)
		startVertex = 0;

	RI_ASSERT(startVertex >= 0 && startVertex < self->_vertexCount);
	RI_ASSERT(endVertex >= 0 && endVertex < self->_vertexCount);

	distance += self->_vertices[startVertex].pathLength;	//map distance to the range of the whole path

	if(distance <= self->_vertices[startVertex].pathLength)
	{	//return the first point of the path
		*p = self->_vertices[startVertex].userPosition;
		*t = self->_vertices[startVertex].userTangent;
		return;
	}

	if(distance >= self->_vertices[endVertex].pathLength)
	{	//return the last point of the path
		*p = self->_vertices[endVertex].userPosition;
		*t = self->_vertices[endVertex].userTangent;
		return;
	}

	//search for the segment containing the distance
    int s;
	for(s=startIndex;s<startIndex+numSegments;s++)
	{
		int start = self->_segmentToVertex[s].start;
		int end = self->_segmentToVertex[s].end;
		if(start < 0)
			start = 0;
		if(end < 0)
			end = 0;
		RI_ASSERT(start >= 0 && start < self->_vertexCount);
		RI_ASSERT(end >= 0 && end < self->_vertexCount);

		if(distance >= self->_vertices[start].pathLength && distance < self->_vertices[end].pathLength)
		{	//segment contains the queried distance
            int i;
			for(i=start;i<end;i++)
			{
				Vertex v0 = self->_vertices[i];
				Vertex v1 = self->_vertices[i+1];
				if(distance >= v0.pathLength && distance < v1.pathLength)
				{	//segment found, interpolate linearly between its end points
					CGFloat edgeLength = v1.pathLength - v0.pathLength;
					RI_ASSERT(edgeLength > 0.0f);
					CGFloat r = (distance - v0.pathLength) / edgeLength;
					*p = Vector2Add(Vector2MultiplyByFloat(v0.userPosition , (1.0f - r)) , Vector2MultiplyByFloat(v1.userPosition , r));
					*t = Vector2Add(Vector2MultiplyByFloat(v0.userTangent,(1.0f - r))  , Vector2MultiplyByFloat(v1.userTangent,r));
					return;
				}
			}
		}
	}

	RI_ASSERT(0);	//point not found (should never get here)
}

// Tessellates a path, and computes its length.

CGFloat VGPathGetLength(VGPath *self,int startIndex, int numSegments){
	RI_ASSERT(startIndex >= 0 && startIndex + numSegments <= self->_numberOfElements && numSegments > 0);

	VGPathTessellateIfNeeded(self);

	RI_ASSERT(startIndex >= 0 && startIndex < self->_numberOfElements);
	RI_ASSERT(startIndex + numSegments >= 0 && startIndex + numSegments <= self->_numberOfElements);

	int startVertex = self->_segmentToVertex[startIndex].start;
	int endVertex = self->_segmentToVertex[startIndex + numSegments - 1].end;

	if(!self->_vertexCount)
		return 0.0f;

	CGFloat startPathLength = 0.0f;
	if(startVertex >= 0)
	{
		RI_ASSERT(startVertex >= 0 && startVertex < self->_vertexCount);
		startPathLength = self->_vertices[startVertex].pathLength;
	}
	CGFloat endPathLength = 0.0f;
	if(endVertex >= 0)
	{
		RI_ASSERT(endVertex >= 0 && endVertex < self->_vertexCount);
		endPathLength = self->_vertices[endVertex].pathLength;
	}

	return endPathLength - startPathLength;
}

// Tessellates a path, and computes its bounding box in user space.

void VGPathGetPathBounds(VGPath *self,CGFloat *minx, CGFloat *miny, CGFloat *maxx, CGFloat *maxy){
	VGPathTessellateIfNeeded(self);

	if(self->_vertexCount)
	{
		*minx = self->m_userMinx;
		*miny = self->m_userMiny;
		*maxx = self->m_userMaxx;
		*maxy = self->m_userMaxy;
	}
	else
	{
		*minx = *miny = 0;
		*maxx = *maxy = -1;
	}
}

// Tessellates a path, and computes its bounding box in surface space.

void VGPathGetPathTransformedBounds(VGPath *self,CGAffineTransform pathToSurface, CGFloat *minx, CGFloat *miny, CGFloat *maxx, CGFloat *maxy){

	VGPathTessellateIfNeeded(self);

	if(self->_vertexCount==0) {
		*minx = *miny = 0;
		*maxx = *maxy = -1;
	}
    else {
		CGPoint p0=CGPointMake(self->m_userMinx, self->m_userMiny);
		CGPoint p1=CGPointMake(self->m_userMinx, self->m_userMaxy);
		CGPoint p2=CGPointMake(self->m_userMaxx, self->m_userMaxy);
		CGPoint p3=CGPointMake(self->m_userMaxx, self->m_userMiny);
		p0 = CGPointApplyAffineTransform(p0,pathToSurface);
		p1 = CGPointApplyAffineTransform(p1,pathToSurface);
		p2 = CGPointApplyAffineTransform(p2,pathToSurface);
		p3 = CGPointApplyAffineTransform(p3,pathToSurface);

		*minx = RI_MIN(RI_MIN(RI_MIN(p0.x, p1.x), p2.x), p3.x);
		*miny = RI_MIN(RI_MIN(RI_MIN(p0.y, p1.y), p2.y), p3.y);
		*maxx = RI_MAX(RI_MAX(RI_MAX(p0.x, p1.x), p2.x), p3.x);
		*maxy = RI_MAX(RI_MAX(RI_MAX(p0.y, p1.y), p2.y), p3.y);
	}
}

// Adds a vertex to a tessellated path.

void VGPathAddVertex(VGPath *self,CGPoint p, CGPoint t, CGFloat pathLength, unsigned int flags){
	RI_ASSERT(!Vector2IsZero(t));

	Vertex v;
	v.pathLength = pathLength;
	v.userPosition = p;
	v.userTangent = t;
	v.flags = flags;
    
    if(self->_vertexCount+1>self->_vertexCapacity){
     self->_vertexCapacity*=2;
     self->_vertices=(Vertex *)NSZoneRealloc(NULL,self->_vertices,self->_vertexCapacity*sizeof(Vertex));
    }
    self->_vertices[self->_vertexCount++]=v;

	self->m_userMinx = RI_MIN(self->m_userMinx, v.userPosition.x);
	self->m_userMiny = RI_MIN(self->m_userMiny, v.userPosition.y);
	self->m_userMaxx = RI_MAX(self->m_userMaxx, v.userPosition.x);
	self->m_userMaxy = RI_MAX(self->m_userMaxy, v.userPosition.y);
}

// Adds an edge to a tessellated path.

void VGPathAddEdge(VGPath *self,CGPoint p0, CGPoint p1, CGPoint t0, CGPoint t1, unsigned int startFlags, unsigned int endFlags){
	CGFloat pathLength = 0.0f;

	RI_ASSERT(!Vector2IsZero(t0) && !Vector2IsZero(t1));

	//segment midpoints are shared between edges
	if( startFlags & START_SEGMENT )
	{
		if(self->_vertexCount > 0)
			pathLength = self->_vertices[self->_vertexCount-1].pathLength;

		VGPathAddVertex(self,p0, t0, pathLength, startFlags);
	}

	//other than implicit close paths (caused by a MOVE_TO) add to path length
	if( !(endFlags & IMPLICIT_CLOSE_SUBPATH) )
	{
		//NOTE: with extremely large coordinates the floating point path length is infinite
		CGFloat l = Vector2Length(Vector2Subtract(p1,p0));
		pathLength = self->_vertices[self->_vertexCount-1].pathLength + l;
		pathLength = RI_MIN(pathLength, RI_FLOAT_MAX);
	}

	VGPathAddVertex(self,p1, t1, pathLength, endFlags);
}

// Tessellates a close-path segment.

void VGPathAddEndPath(VGPath *self,CGPoint p0, CGPoint p1, BOOL subpathHasGeometry, unsigned int flags){
	if(!subpathHasGeometry)
	{	//single vertex
		CGPoint t=CGPointMake(1.0f,0.0f);
		VGPathAddEdge(self,p0, p1, t, t, START_SEGMENT | START_SUBPATH, END_SEGMENT | END_SUBPATH);
		VGPathAddEdge(self,p0, p1, Vector2Negate(t), Vector2Negate(t), IMPLICIT_CLOSE_SUBPATH | START_SEGMENT, IMPLICIT_CLOSE_SUBPATH | END_SEGMENT);
		return;
	}
	//the subpath contains segment commands that have generated geometry

	//add a close path segment to the start point of the subpath
	RI_ASSERT(self->_vertexCount > 0);
	self->_vertices[self->_vertexCount-1].flags |= END_SUBPATH;

	CGPoint t = Vector2Normalize(Vector2Subtract(p1,p0));
	if(Vector2IsZero(t))
		t = self->_vertices[self->_vertexCount-1].userTangent;	//if the segment is zero-length, use the tangent of the last segment end point so that proper join will be generated
	RI_ASSERT(!Vector2IsZero(t));

	VGPathAddEdge(self,p0, p1, t, t, flags | START_SEGMENT, flags | END_SEGMENT);
}

// Tessellates a line-to segment.

BOOL VGPathAddLineTo(VGPath *self,CGPoint p0, CGPoint p1, BOOL subpathHasGeometry){
	if(Vector2IsEqual(p0 ,p1))
		return NO;	//discard zero-length segments

	//compute end point tangents
	CGPoint t = Vector2Normalize(Vector2Subtract(p1,p0));
	RI_ASSERT(!Vector2IsZero(t));

	unsigned int startFlags = START_SEGMENT;
	if(!subpathHasGeometry)
		startFlags |= START_SUBPATH;
	VGPathAddEdge(self,p0, p1, t, t, startFlags, END_SEGMENT);
	return YES;
}

// Tessellates a quad-to segment.

/*
 Given a quadratic Bézier curve with control points (x0, y0), (x1, y1), and (x2, y2), an identical cubic Bézier curve may be formed using the control points (x0, y0), (x0 + 2*x1, y0 + 2*y1)/3, (x2 + 2*x1, y2 + 2*y1)/3, (x2, y2)
  */
  
BOOL VGPathAddQuadTo(VGPath *self,CGPoint p0, CGPoint p1, CGPoint p2, BOOL subpathHasGeometry){
	if(Vector2IsEqual(p0,p1) && Vector2IsEqual(p0,p2))
	{
		RI_ASSERT(Vector2IsEqual(p1,p2));
		return NO;	//discard zero-length segments
	}

	//compute end point tangents

	CGPoint incomingTangent = Vector2Normalize(Vector2Subtract(p1,p0));
	CGPoint outgoingTangent = Vector2Normalize(Vector2Subtract(p2,p1));
	if(Vector2IsEqual(p0,p1))
		incomingTangent = Vector2Normalize(Vector2Subtract(p2,p0));
	if(Vector2IsEqual(p1,p2))
		outgoingTangent = Vector2Normalize(Vector2Subtract(p2 ,p0));
	RI_ASSERT(!Vector2IsZero(incomingTangent) && !Vector2IsZero(outgoingTangent));

	unsigned int startFlags = START_SEGMENT;
	if(!subpathHasGeometry)
		startFlags |= START_SUBPATH;

	const int segments = 256;
	CGPoint pp = p0;
	CGPoint tp = incomingTangent;
	unsigned int prevFlags = startFlags;
    int i;
	for(i=1;i<segments;i++)
	{
		CGFloat t = (CGFloat)i / (CGFloat)segments;
		CGFloat u = 1.0f-t;
		CGPoint pn = Vector2Add(Vector2Add(Vector2MultiplyByFloat(p0,u*u) , Vector2MultiplyByFloat(p1,2.0f*t*u)),Vector2MultiplyByFloat(p2,t*t));
		CGPoint tn = Vector2Add(Vector2Add(Vector2MultiplyByFloat(p0,(-1.0f+t)), Vector2MultiplyByFloat(p1,(1.0f-2.0f*t))),Vector2MultiplyByFloat(p2,t));
		tn = Vector2Normalize(tn);
		if(Vector2IsZero(tn))
			tn = tp;

		VGPathAddEdge(self,pp, pn, tp, tn, prevFlags, 0);

		pp = pn;
		tp = tn;
		prevFlags = 0;
	}
	VGPathAddEdge(self,pp, p2, tp, outgoingTangent, prevFlags, END_SEGMENT);
	return YES;
}

// Tessellates a cubic-to segment.

// Bezier to lines from: Windows Graphics Programming by Feng Yuan
static void bezier(VGPath *self,double x1,double y1,double x2, double y2,double x3,double y3,double x4,double y4,unsigned *prevFlags,CGPoint *pp,CGPoint *tp){
   // Ax+By+C=0 is the line (x1,y1) (x4,y4);
   double A=y4-y1;
   double B=x1-x4;
   double C=y1*(x4-x1)-x1*(y4-y1);
   double AB=A*A+B*B;

   if((A*x2+B*y2+C)*(A*x2+B*y2+C)<AB && (A*x3+B*y3+C)*(A*x3+B*y3+C)<AB){
    CGPoint v0=CGPointMake(x1,y1);
    CGPoint v1=CGPointMake(x4,y4);
    CGPoint t = Vector2Normalize(Vector2Subtract(v1,v0));

    VGPathAddEdge(self,v0, v1, *tp, t, *prevFlags, 0);
    *prevFlags=0;
    *pp=v1;
    *tp=t;
    return;
   }
   else {
    double x12=x1+x2;
    double y12=y1+y2;
    double x23=x2+x3;
    double y23=y2+y3;
    double x34=x3+x4;
    double y34=y3+y4;
    double x1223=x12+x23;
    double y1223=y12+y23;
    double x2334=x23+x34;
    double y2334=y23+y34;
    double x=x1223+x2334;
    double y=y1223+y2334;

    bezier(self,x1,y1,x12/2,y12/2,x1223/4,y1223/4,x/8,y/8,prevFlags,pp,tp);
    bezier(self,x/8,y/8,x2334/4,y2334/4,x34/2,y34/2,x4,y4,prevFlags,pp,tp);
   }
}

BOOL VGPathAddCubicTo(VGPath *self,CGPoint p0, CGPoint p1, CGPoint p2, CGPoint p3, BOOL subpathHasGeometry){
	if(Vector2IsEqual(p0,p1) && Vector2IsEqual(p0,p2) && Vector2IsEqual(p0 ,p3))
	{
		RI_ASSERT(Vector2IsEqual(p1 , p2) && Vector2IsEqual(p1 , p3) && Vector2IsEqual(p2 , p3));
		return NO;	//discard zero-length segments
	}

	//compute end point tangents
	CGPoint incomingTangent = Vector2Normalize(Vector2Subtract(p1, p0));
	CGPoint outgoingTangent = Vector2Normalize(Vector2Subtract(p3, p2));
	if(Vector2IsEqual(p0 , p1))
	{
		incomingTangent = Vector2Normalize(Vector2Subtract(p2 ,p0));
		if(Vector2IsEqual(p1, p2))
			incomingTangent = Vector2Normalize(Vector2Subtract(p3,p0));
	}
	if(Vector2IsEqual(p2, p3))
	{
		outgoingTangent = Vector2Normalize(Vector2Subtract(p3 ,p1));
		if(Vector2IsEqual(p1, p2))
			outgoingTangent = Vector2Normalize(Vector2Subtract(p3,p0));
	}
	RI_ASSERT(!Vector2IsZero(incomingTangent) && !Vector2IsZero(outgoingTangent));

	unsigned int startFlags = START_SEGMENT;
	if(!subpathHasGeometry)
		startFlags |= START_SUBPATH;

#if 1
// This works, but does not take the CTM (i.e. scaling) into effect
	unsigned int prevFlags = startFlags;
	CGPoint pp = p0;
	CGPoint tp = incomingTangent;
    bezier(self,p0.x,p0.y,p1.x,p1.y,p2.x,p2.y,p3.x,p3.y,&prevFlags,&pp,&tp);
	VGPathAddEdge(self,pp, p3, tp, outgoingTangent, prevFlags, END_SEGMENT);
#else
	const int segments = 256;
	CGPoint pp = p0;
	CGPoint tp = incomingTangent;
	unsigned int prevFlags = startFlags;
    int i;
	for(i=1;i<segments;i++)
	{
		CGFloat t = (CGFloat)i / (CGFloat)segments;
		CGFloat u = 1.0f-t;
		CGPoint pn = Vector2Add(Vector2Add(Vector2Add(Vector2MultiplyByFloat(p0,u*u*u), Vector2MultiplyByFloat(p1,3.0f*t*u*u)) ,Vector2MultiplyByFloat(p2,3.0f*t*t*u)),Vector2MultiplyByFloat(p3,t*t*t));
		CGPoint tn = Vector2Add(Vector2Add(Vector2Add(Vector2MultiplyByFloat(p0,(-1.0f + 2.0f*t - t*t)) , Vector2MultiplyByFloat(p1,(1.0f - 4.0f*t + 3.0f*t*t))) , Vector2MultiplyByFloat(p2,(2.0f*t - 3.0f*t*t) )) ,Vector2MultiplyByFloat(p3,t*t));
		tn = Vector2Normalize(tn);
		if(Vector2IsZero(tn))
			tn = tp;

		VGPathAddEdge(self,pp, pn, tp, tn, prevFlags, 0);

		pp = pn;
		tp = tn;
		prevFlags = 0;
	}
	VGPathAddEdge(self,pp, p3, tp, outgoingTangent, prevFlags, END_SEGMENT);
#endif
	return YES;
}

// Tessellates a path.

/*		tessellation output format: A list of vertices describing the
		path tessellated into line segments and relevant aspects of the
		input data. Each path segment has a start vertex, a number of
		internal vertices (possibly zero), and an end vertex. The start
		and end of segments and subpaths have been flagged, as well as
  		implicit and explicit close subpath segments. */

void VGPathTessellateIfNeeded(VGPath *self){
	if( self->_vertexCount > 0 )
		return;	//already tessellated

	self->m_userMinx = RI_FLOAT_MAX;
	self->m_userMiny = RI_FLOAT_MAX;
	self->m_userMaxx = -RI_FLOAT_MAX;
	self->m_userMaxy = -RI_FLOAT_MAX;

	{
        unsigned numberOfElements=[self->_path numberOfElements];
        if(self->_segmentToVertexCapacity<numberOfElements){
         self->_segmentToVertexCapacity=numberOfElements;
         self->_segmentToVertex=NSZoneRealloc(NULL,self->_segmentToVertex,self->_segmentToVertexCapacity*sizeof(VertexIndex));
        }
        
		int coordIndex = 0;
		CGPoint s=CGPointMake(0,0);		//the beginning of the current subpath
		CGPoint o=CGPointMake(0,0);		//the last point of the previous segment
		CGPoint p=CGPointMake(0,0);		//the last internal control point of the previous segment, if the segment was a (regular or smooth) quadratic or cubic Bezier, or else the last point of the previous segment

		//tessellate the path segments
		coordIndex = 0;
		s=CGPointMake(0,0);
		o=CGPointMake(0,0);
		p=CGPointMake(0,0);
		BOOL subpathHasGeometry = NO;
		CGPathElementType prevSegment = kCGPathElementMoveToPoint;
        int i;
        const unsigned char *elements=[self->_path elements];
        const CGPoint *points=[self->_path points];
        
		for(i=0;i<numberOfElements;i++)
		{
			CGPathElementType segment = elements[i];
			int coords = CGPathElementTypeToNumCoordinates(segment);
			self->_segmentToVertex[i].start = self->_vertexCount;

			switch(segment)
			{
			case kCGPathElementCloseSubpath:
			{
				RI_ASSERT(coords == 0);
				VGPathAddEndPath(self,o, s, subpathHasGeometry, CLOSE_SUBPATH);
				p = s;
				o = s;
				subpathHasGeometry = NO;
				break;
			}

			case kCGPathElementMoveToPoint:
			{
				RI_ASSERT(coords == 1);
				CGPoint c=points[coordIndex];
				if(prevSegment != kCGPathElementMoveToPoint && prevSegment != kCGPathElementCloseSubpath)
					VGPathAddEndPath(self,o, s, subpathHasGeometry, IMPLICIT_CLOSE_SUBPATH);
				s = c;
				p = c;
				o = c;
				subpathHasGeometry = NO;
				break;
			}

			case kCGPathElementAddLineToPoint:
			{
				RI_ASSERT(coords == 1);
				CGPoint c=points[coordIndex];
				if(VGPathAddLineTo(self,o, c, subpathHasGeometry))
					subpathHasGeometry = YES;
				p = c;
				o = c;
				break;
			}

			case kCGPathElementAddQuadCurveToPoint:
			{
				RI_ASSERT(coords == 2);
				CGPoint c0=points[coordIndex];
				CGPoint c1=points[coordIndex+1];
				if(VGPathAddQuadTo(self,o, c0, c1, subpathHasGeometry))
					subpathHasGeometry = YES;
				p = c0;
				o = c1;
				break;
			}

			case kCGPathElementAddCurveToPoint:
			{
				RI_ASSERT(coords == 3);
				CGPoint c0=points[coordIndex+0];
				CGPoint c1=points[coordIndex+1];
				CGPoint c2=points[coordIndex+2];
				if(VGPathAddCubicTo(self,o, c0, c1, c2, subpathHasGeometry))
					subpathHasGeometry = YES;
				p = c1;
				o = c2;
				break;
			}

			}

			if(self->_vertexCount > self->_segmentToVertex[i].start)
			{	//segment produced vertices
				self->_segmentToVertex[i].end = self->_vertexCount - 1;
			}
			else
			{	//segment didn't produce vertices (zero-length segment). Ignore it.
				self->_segmentToVertex[i].start = self->_segmentToVertex[i].end = self->_vertexCount-1;
			}
			prevSegment = segment;
			coordIndex += coords;
		}

		//add an implicit MOVE_TO to the end to close the last subpath.
		//if the subpath contained only zero-length segments, this produces the necessary geometry to get it stroked
		// and included in path bounds. The geometry won't be included in the pointAlongPath query.
		if(prevSegment != kCGPathElementMoveToPoint && prevSegment != kCGPathElementCloseSubpath)
			VGPathAddEndPath(self,o, s, subpathHasGeometry, IMPLICIT_CLOSE_SUBPATH);

#if 0 // DEBUG
		//check that the flags are correct
		int prev = -1;
		BOOL subpathStarted = NO;
		BOOL segmentStarted = NO;
		for(int i=0;i<self->_vertexCount;i++)
		{
			Vertex  v = self->_vertices[i];

			if(v.flags & START_SUBPATH)
			{
				RI_ASSERT(!subpathStarted);
				RI_ASSERT(v.flags & START_SEGMENT);
				RI_ASSERT(!(v.flags & END_SUBPATH));
				RI_ASSERT(!(v.flags & END_SEGMENT));
				RI_ASSERT(!(v.flags & CLOSE_SUBPATH));
				RI_ASSERT(!(v.flags & IMPLICIT_CLOSE_SUBPATH));
				subpathStarted = YES;
			}
			
			if(v.flags & START_SEGMENT)
			{
				RI_ASSERT(subpathStarted || (v.flags & CLOSE_SUBPATH) || (v.flags & IMPLICIT_CLOSE_SUBPATH));
				RI_ASSERT(!segmentStarted);
				RI_ASSERT(!(v.flags & END_SUBPATH));
				RI_ASSERT(!(v.flags & END_SEGMENT));
				segmentStarted = YES;
			}
			
			if( v.flags & CLOSE_SUBPATH )
			{
				RI_ASSERT(segmentStarted);
				RI_ASSERT(!subpathStarted);
				RI_ASSERT((v.flags & START_SEGMENT) || (v.flags & END_SEGMENT));
				RI_ASSERT(!(v.flags & IMPLICIT_CLOSE_SUBPATH));
				RI_ASSERT(!(v.flags & START_SUBPATH));
				RI_ASSERT(!(v.flags & END_SUBPATH));
			}
			if( v.flags & IMPLICIT_CLOSE_SUBPATH )
			{
				RI_ASSERT(segmentStarted);
				RI_ASSERT(!subpathStarted);
				RI_ASSERT((v.flags & START_SEGMENT) || (v.flags & END_SEGMENT));
				RI_ASSERT(!(v.flags & CLOSE_SUBPATH));
				RI_ASSERT(!(v.flags & START_SUBPATH));
				RI_ASSERT(!(v.flags & END_SUBPATH));
			}
			
			if( prev >= 0 )
			{
				RI_ASSERT(segmentStarted);
				RI_ASSERT(subpathStarted || ((self->_vertices[prev].flags & CLOSE_SUBPATH) && (self->_vertices[i].flags & CLOSE_SUBPATH)) ||
						  ((self->_vertices[prev].flags & IMPLICIT_CLOSE_SUBPATH) && (self->_vertices[i].flags & IMPLICIT_CLOSE_SUBPATH)));
			}

			prev = i;
			if(v.flags & END_SEGMENT)
			{
				RI_ASSERT(subpathStarted || (v.flags & CLOSE_SUBPATH) || (v.flags & IMPLICIT_CLOSE_SUBPATH));
				RI_ASSERT(segmentStarted);
				RI_ASSERT(!(v.flags & START_SUBPATH));
				RI_ASSERT(!(v.flags & START_SEGMENT));
				segmentStarted = NO;
				prev = -1;
			}
			
			if(v.flags & END_SUBPATH)
			{
				RI_ASSERT(subpathStarted);
				RI_ASSERT(v.flags & END_SEGMENT);
				RI_ASSERT(!(v.flags & START_SUBPATH));
				RI_ASSERT(!(v.flags & START_SEGMENT));
				RI_ASSERT(!(v.flags & CLOSE_SUBPATH));
				RI_ASSERT(!(v.flags & IMPLICIT_CLOSE_SUBPATH));
				subpathStarted = NO;
			}
		}
#endif	//RI_DEBUG
	}

}

@end
