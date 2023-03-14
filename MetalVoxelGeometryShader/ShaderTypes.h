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
	#define uchar simd_uchar1
	#define uchar3 simd_uchar3
	#define uchar4 simd_uchar4
	#define uint3 simd_uint3
	#define float3 simd_float3
	#define float4 simd_float4
	
	#if defined(TARGET_OS_MAC)
		#define half3 simd_ushort3
		#define half4 simd_ushort4
	#else
		#define half3 simd_half3
		#define half4 simd_half4
	#endif
	
	#define simd_uint3(x,y,z) (simd_uint3){x,y,z}
#endif


#if defined(__METAL_VERSION__)
	#define offsetof(st, m) ((size_t)&(((device st *)0)->m))
#endif


#if defined(__METAL_VERSION__)
	#define CONSTANT constant
#elif defined(__cplusplus)
	#define CONSTANT constexpr
#else // C/Obj-C/Swift
	#define CONSTANT const
#endif



// Optimized for maxTotalThreadsPerThreadgroup: 896, threadExecutionWidth: 16
static CONSTANT uint kCubesPerBlockX = 8;
static CONSTANT uint kCubesPerBlockY = 7;
static CONSTANT uint kCubesPerBlockZ = 16;
static CONSTANT uint3 kCubesPerBlockXYZ = uint3(kCubesPerBlockX, kCubesPerBlockY, kCubesPerBlockZ);
static CONSTANT uint kCubesPerBlock = kCubesPerBlockX * kCubesPerBlockY * kCubesPerBlockZ;

static CONSTANT uint kPrimitiveCountPerCube = 6 * 2;
static CONSTANT uint kIndexCountPerCube = kPrimitiveCountPerCube * 3;
static CONSTANT uint kVertexCountPerCube = kIndexCountPerCube;

static CONSTANT uint kTrianglesPerModel = kPrimitiveCountPerCube;
static CONSTANT uint kThreadsPerCube = 1;

static CONSTANT uint kMaxTotalThreadgroupsPerMeshGrid = 2;
static CONSTANT uint kMaxTotalThreadsPerObjectThreadgroup = kCubesPerBlock;
static CONSTANT uint kMaxTotalThreadsPerMeshThreadgroup = kThreadsPerCube;

static CONSTANT size_t kObjectToMeshPayloadSize = 8 /* half4 */ + 8 /* padding */ +
	(4 * 16) /* float4x4 */ +
	16 /* uint3 */;
static CONSTANT size_t kObjectToMeshPayloadMemoryLength = kObjectToMeshPayloadSize * kCubesPerBlock;


typedef struct _MeshPrimitiveData_cpu {
	uchar4 color;
	uchar3 normal;
	uchar3 voxelCoord;
} MeshPrimitiveData_cpu;
static CONSTANT size_t kMeshPrimitiveDataSize = sizeof(MeshPrimitiveData_cpu);

typedef struct _MeshVertexData_cpu {
	uchar3 position;
	MeshPrimitiveData_cpu primitive;
} MeshVertexData_cpu;
static CONSTANT size_t kMeshVertexDataSize = sizeof(MeshVertexData_cpu);

typedef struct _MeshTriIndexData_cpu {
	uint indices[3];
} MeshTriIndexData_cpu;

#define align16Size(s) ((s + 0xF) & -0x10)

//typedef struct _CubeMesh_cpu {
//	uint index __attribute__((aligned(16)));
//	MeshVertexData_cpu vertices[kVertexCountPerCube] __attribute__((aligned(16)));
//	uint16_t indices[kIndexCountPerCube] __attribute__((aligned(16)));
//	MeshPrimitiveData_cpu primitives[kPrimitiveCountPerCube] __attribute__((aligned(16)));
//} CubeMesh_cpu;
//static CONSTANT size_t kCubeMeshSize = sizeof(CubeMesh_cpu);
//static CONSTANT size_t kCubeMeshOffsetOfVertices = offsetof(CubeMesh_cpu, vertices);
//static CONSTANT size_t kCubeMeshOffsetOfIndicies = offsetof(CubeMesh_cpu, indices);
//static CONSTANT size_t kCubeMeshOffsetOfPrimitives = offsetof(CubeMesh_cpu, primitives);


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
