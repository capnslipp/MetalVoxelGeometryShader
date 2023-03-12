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
#else
	#define uint3 simd_uint3
	#define simd_uint3(x,y,z) (simd_uint3){x,y,z}
#endif



#if defined(__METAL_VERSION__)
	#define CONSTANT constant
#elif defined(__cplusplus)
	#define CONSTANT constexpr
#else // C/Obj-C/Swift
	#define CONSTANT const
#endif



static CONSTANT uint kCubesPerBlockX = 4;
static CONSTANT uint kCubesPerBlockY = 4;
static CONSTANT uint kCubesPerBlockZ = 4;
static CONSTANT uint3 kCubesPerBlockXYZ = uint3(kCubesPerBlockX, kCubesPerBlockY, kCubesPerBlockZ);
static CONSTANT uint kCubesPerBlock = kCubesPerBlockX * kCubesPerBlockY * kCubesPerBlockZ;

static CONSTANT uint kVertexCountPerCube = 8;
static CONSTANT uint kPrimitiveCountPerCube = 6 * 2;
static CONSTANT uint kIndexCountPerCube = kPrimitiveCountPerCube * 3;

static CONSTANT uint kTrianglesPerModel = kPrimitiveCountPerCube;
static CONSTANT uint kThreadsPerCube = 1;

static CONSTANT uint kMaxTotalThreadgroupsPerMeshGrid = 2;
static CONSTANT uint kMaxTotalThreadsPerObjectThreadgroup = kCubesPerBlock;
static CONSTANT uint kMaxTotalThreadsPerMeshThreadgroup = kThreadsPerCube;

static CONSTANT size_t kObjectToMeshPayloadSize = 8 /* half4 */ + 8 /* padding */ +
	(4 * 16) /* float4x4 */ +
	16 /* uint3 */;
static CONSTANT size_t kObjectToMeshPayloadMemoryLength = kObjectToMeshPayloadSize * kCubesPerBlock;


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
