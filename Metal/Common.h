
//  Copyright © 1887 Sherlock Holmes. All rights reserved.
//  Found amongst his effects by r0ml

#ifndef Common_h
#define Common_h

constant int uniformId = 0;
constant int kbuffId = 3;
constant int computeBuffId = 15;
constant int audioBuffId = 20;
constant int fftBuffId = 24;

constant int inputTextureId = 0;
constant int renderInputId = 10;
constant int renderOutputId = 30;
constant int cubeId = 20;
constant int renderedTextsId = 40;
constant int videoId = 50;
constant int webcamId = 60;

struct string { char name[256]; } ;

using namespace metal;

#ifndef VertexOut
#define VertexOut VertexOutTriangle
#endif

struct VertexOutTriangle {
  float4  where [[position]];   // this is in the range -1 -> 1 in the vertex shader,  0 -> viewSize in the fragment shader
  float4  color;
  float4  barrio;               // this is in the range 0 -> 1 in the vertex shader
  int3 parm;
};

struct VertexOutPoint {
  float4  where [[position]];
  float4  color;
  float4  barrio;
  int3 parm;
  float point_size [[point_size]]; // only for pointcloud
};

#include "support.h"
#include "sdf.h"
#include "constants.h"
#include "glsl.h"

typedef struct {
  float4 iDate;                        // (year, month, day, time in seconds)
  float2 iMouse;                       // mouse pixel coords
  float2 lastTouch;
  float2 iResolution;                  // viewport resolution (in pixels)
  uint2  keyPress;                     // keyPress.x is the current key down
                                       // keyPress.y is the key just clicked on this frame only
  int   iFrame;                       // shader playback frame
  float iTime;                        // shader playback time (in seconds)
  float iTimeDelta;                   // time (in seconds) since last frame
  int mouseButtons;
  int eventModifiers;
} Uniform;

struct KBuffer;

float2 textureSize(texture2d<float> t);

/*struct VertexOut {
  float4  where [[position]];
  float4  color;
};*/

#ifndef shaderName
#warning you must #define shaderName ()
// it would be awesome if I could actually get just the basename of the filename and automate this
#define shaderName __FILE__
#endif

// =========================================================================================

#ifndef ComputeBuffer
#define ComputeBuffer float4
#endif

#define computeFn(a) _computeFn(a, shaderName)
#define _computeFn(a, b) __computeFn(a, b)
#define __computeFn(a, b) kernel void b##___##a##___Kernel ( \
uint3 xCoord [[thread_position_in_grid]], \
constant Uniform &uni [[ buffer(uniformId) ]], \
device KBuffer &kbuff [[ buffer(kbuffId) ]], \
device ComputeBuffer &computeBuffer [[ buffer(computeBuffId) ]] \
)

// =========================================================================================
// New render

#define vertexFn(a) _vertexFn(a, shaderName)
#define _vertexFn(a, b) __vertexFn(a, b)
#define __vertexFn(a, b) vertex VertexOut b##___##a##___Vertex ( \
uint vid [[ vertex_id ]], \
uint iid [[ instance_id ]], \
constant Uniform &uni [[ buffer(uniformId) ]], \
constant KBuffer &kbuff [[ buffer(kbuffId) ]], \
device const ComputeBuffer &computeBuffer [[ buffer(computeBuffId) ]] \
)

// #ifndef FragmentOutput
typedef float4 FragmentOutput0;
// #endif

struct FragmentOutput1 {
  float4 fragColor [[color(0)]];
  float4 pass1 [[color(1)]];
};

struct FragmentOutput2 {
  float4 fragColor [[color(0)]];
  float4 pass1 [[color(1)]];
  float4 pass2 [[color(2)]];
};

struct FragmentOutput3 {
  float4 fragColor [[color(0)]];
  float4 pass1 [[color(1)]];
  float4 pass2 [[color(2)]];
  float4 pass3 [[color(3)]];
};

struct FragmentOutput4 {
  float4 fragColor [[color(0)]];
  float4 pass1 [[color(1)]];
  float4 pass2 [[color(2)]];
  float4 pass3 [[color(3)]];
  float4 pass4 [[color(4)]];
};

#define fragmentFn(a) _fragmentFn(a, 0, shaderName)
#define fragmentFn1(a) _fragmentFn(a, 1, shaderName)
#define fragmentFn2(a) _fragmentFn(a, 2, shaderName)
#define fragmentFn3(a) _fragmentFn(a, 3, shaderName)
#define fragmentFn4(a) _fragmentFn(a, 4, shaderName)


#define _fragmentFn(a, n, b) __fragmentFn(a, n, b)
#define __fragmentFn(a, n, b) typedef FragmentOutput##n FragmentOutput; \
fragment FragmentOutput##n b##___##a##___Fragment ( \
VertexOut thisVertex [[stage_in]], \
float2 pointCoord [[point_coord]], \
constant Uniform &uni [[buffer(uniformId)]], \
device KBuffer &kbuff [[ buffer(kbuffId) ]], \
array<texture2d<float>, numberOfTextures> texture [[texture(inputTextureId)]], \
array<texture2d<float, access::sample>, n> renderInput [[texture(renderInputId)]], \
array<texturecube<float>, numberOfCubes> cube [[texture(cubeId)]], \
array<texture2d<float>, numberOfTexts> text [[texture(renderedTextsId)]], \
device float* audio [[buffer(audioBuffId)]], \
device float* fft [[buffer(fftBuffId)]], \
array<texture2d<float>, numberOfVideos> video [[texture(videoId)]], \
texture2d<float> webcam [[texture(webcamId)]], \
device const ComputeBuffer &computeBuffer [[ buffer(computeBuffId) ]] \
)

#define filterFn(a) _filterFn(a, shaderName)
#define _filterFn(a, b) __filterFn(a, b)
#define __filterFn(a, b) fragment FragmentOutput b##a##___Filter ( \
VertexOut thisVertex [[stage_in]], \
array<texture2d<float>, numberOfTextures> texture [[texture(inputTextureId)]], \
device const ComputeBuffer &computeBuffer [[ buffer(computeBuffId) ]] \
)

// ===========================================================================================================

// this is required for pre-scanning calls to this macro
#define initialize() ___initialize(shaderName)

#define ___initialize(n) __initialize(n)

#define __initialize(n) \
static void _initialize(constant Uniform& uni, device KBuffer& kbuff); \
\
kernel void n##InitializeOptions ( \
  constant Uniform &uni [[ buffer(uniformId) ]], \
  device KBuffer &kbuff [[ buffer(kbuffId) ]] \
) { \
  kbuff = KBuffer(); \
  _initialize(uni, kbuff ); \
} \
\
void _initialize(constant Uniform &uni, device KBuffer& kbuff)

// ==================================================

#define stringSet(a, b) {\
  char unb[] = b; \
  _stringSet(a, sizeof(unb), unb); \
}

// void stringSet(device string& lval, uint n, const char[] );
template <typename T>
static void _stringSet(device string& lval, uint nv, T val) {
  for(unsigned int i = 0;i < nv /*sizeof(val)*/; i++) {
    lval.name[i]=val[i];
  }
}

void stringCopy(device string& lval, uint n, thread char *val);

#define setTex(n, v) _stringSet(kbuff.textures[n], sizeof(v), v)
#define setMusic(n,v) _stringSet(kbuff.music[n], sizeof(v), v)
#define setVideo(n, v) _stringSet(kbuff.videos[n], sizeof(v), v)
#define setCube(n, v) _stringSet(kbuff.cubes[n], sizeof(v), v)

#endif /* Common_h */
