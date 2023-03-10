//
//  ShaderTypes.h
//  MetalVoxelGeometryShader
//
//  Created by Cap'n Slipp on 2/28/23.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//

#pragma once


#ifdef __METAL_VERSION__
	#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
	typedef metal::int32_t EnumBackingType;
#else
	#import <Foundation/Foundation.h>
	typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>



#if defined(__METAL_VERSION__)
	#define CONSTANT constant
#elif defined(__cplusplus)
	#define CONSTANT constexpr constant
#else // C/Obj-C/Swift
	#define CONSTANT const
#endif



static CONSTANT size_t kMeshPayloadMemoryLength = (8 + 8) + (4 * 16);

static CONSTANT uint kCubesPerBlockX = 1;
static CONSTANT uint kCubesPerBlockY = 1;
static CONSTANT uint kCubesPerBlockZ = 1;
static CONSTANT uint kCubesPerBlock = kCubesPerBlockX * kCubesPerBlockY * kCubesPerBlockZ;

static CONSTANT uint kVertexCountPerCube = 8;
static CONSTANT uint kPrimitiveCountPerCube = 12;//6 * 2;
//static CONSTANT uint kIndexCountPerCube = kPrimitiveCountPerCube * 3;

static CONSTANT uint kTrianglesPerModel = kPrimitiveCountPerCube;
static CONSTANT uint kThreadsPerCube = (kVertexCountPerCube > kPrimitiveCountPerCube) ? kVertexCountPerCube : kPrimitiveCountPerCube;


typedef NS_ENUM(EnumBackingType, BufferIndex)
{
	BufferIndexUniforms      = 0,
	BufferIndexMeshPositions = 1,
	BufferIndexMeshGenerics  = 2
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
	VertexAttributePosition  = 0,
	VertexAttributeTexcoord  = 1,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
	TextureIndexColor    = 0,
	TextureIndexVoxel3DColor = 1,
};

typedef struct
{
	matrix_float4x4 modelMatrix;
	matrix_float4x4 viewMatrix;
	matrix_float4x4 modelViewMatrix;
	matrix_float4x4 projectionMatrix;
} Uniforms;
