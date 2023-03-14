//
//	Shaders.metal
//	MetalVoxelGeometryShader
//
//	Created by Cap'n Slipp on 2/28/23.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;



template <typename T>
METAL_FUNC T lerp(T x, T y, T a) { return mix(x, y, a); }

template <typename T>
METAL_FUNC T inverse_lerp(T x, T y, T a) {
	return (a - x) / (y - x);
}



//// MARK: Mesh Shader - Object Stage
//
//typedef struct _ObjectToMeshPayload {
//	half4 color;
//	float4x4 transform;
//	uint3 blockPosition_blocks;
//} ObjectToMeshPayload;
//static_assert(kObjectToMeshPayloadSize == sizeof(ObjectToMeshPayload), "kObjectToMeshPayloadMemoryLength must match the size of MeshPayload.");



// MARK: Mesh Shader - Mesh Stage

typedef struct _MeshPrimitiveData {
	uchar4 color;
	uchar3 normal;
	uchar3 voxelCoord;
} MeshPrimitiveData;
static_assert(kMeshPrimitiveDataSize == sizeof(MeshPrimitiveData), "kMeshPrimitiveDataSize must match the size of MeshPrimitiveData.");
static_assert(sizeof(MeshPrimitiveData_cpu) == sizeof(MeshPrimitiveData), "The size of MeshPrimitiveData_cpu must match the size of MeshPrimitiveData.");

typedef struct _MeshVertexData {
	uchar3 position;
	MeshPrimitiveData primitive;
} MeshVertexData;
static_assert(kMeshVertexDataSize == sizeof(MeshVertexData), "kMeshVertexDataSize must match the size of MeshVertexData.");
static_assert(sizeof(MeshVertexData_cpu) == sizeof(MeshVertexData), "The size of MeshVertexData_cpu must match the size of MeshVertexData.");

//MeshVertexData calculateVertex(uint threadI, uint3 positionInGrid, const object_data ObjectToMeshPayload& payload) {
//	return (MeshVertexData){
//		/* position: */ payload.transform * float4(
//			float3(positionInGrid) +
//				float3(0.5) + 
//				(float3(threadI % 2, threadI / 2 % 2, threadI / 4 % 2) - 0.5) * 0.9,
//			1.0
//		),
//	};
//}

static CONSTANT uchar3 kCubeVertices[kVertexCountPerCube] = {
	uchar3(0, 0, 0),
	uchar3(1, 0, 0),
	uchar3(0, 1, 0),
	uchar3(1, 1, 0),
	uchar3(0, 0, 1),
	uchar3(1, 0, 1),
	uchar3(0, 1, 1),
	uchar3(1, 1, 1),
};

typedef struct _MeshTriIndexData {
	uchar indices[3];
} MeshTriIndexData;

static CONSTANT MeshTriIndexData kCubeTriIndices[kPrimitiveCountPerCube] = {
	// Z-
	(MeshTriIndexData){ 0, 2, 1 },
	(MeshTriIndexData){ 3, 1, 2 },
	// Z+
	(MeshTriIndexData){ 4, 5, 6 },
	(MeshTriIndexData){ 7, 6, 5 },
	// Y-
	(MeshTriIndexData){ 0, 1, 4 },
	(MeshTriIndexData){ 5, 4, 1 },
	// Y+
	(MeshTriIndexData){ 2, 6, 3 },
	(MeshTriIndexData){ 7, 3, 6 },
	// X-
	(MeshTriIndexData){ 0, 4, 2 },
	(MeshTriIndexData){ 6, 2, 4 },
	// X+
	(MeshTriIndexData){ 1, 3, 5 },
	(MeshTriIndexData){ 7, 5, 3 },
};

MeshTriIndexData calculateTriIndices(uint threadI) {
	return kCubeTriIndices[threadI];
}

half3 calculateNormal(int threadI) {
	half3 normal = { 0 };
	// calculates for:
	// 	0 & 1:   (-1, 0, 0)
	// 	2 & 3:   (+1, 0, 0)
	// 	4 & 5:   (0, -1, 0)
	// 	6 & 7:   (0, +1, 0)
	// 	8 & 9:   (0, 0, -1)
	// 	10 & 11: (0, 0, +1)
	normal[threadI / 4 % 3] = (threadI / 2 % 2) * 2 - 1;
	return normal;
}

static CONSTANT uchar3 kCubeNormals[kPrimitiveCountPerCube] = {
	uchar3(-1, 0, 0),
	uchar3(-1, 0, 0),
	uchar3(1, 0, 0),
	uchar3(1, 0, 0),
	uchar3(0, -1, 0),
	uchar3(0, -1, 0),
	uchar3(0, 1, 0),
	uchar3(0, 1, 0),
	uchar3(0, 0, -1),
	uchar3(0, 0, -1),
	uchar3(0, 0, 1),
	uchar3(0, 0, 1),
};

MeshPrimitiveData calculatePrimitive(uchar threadI, ushort3 positionInGrid, uchar4 color) {
	return (MeshPrimitiveData){
		/* color: */ color,
		/* normal: */ kCubeNormals[threadI],
		/* voxelCoord: */ uchar3(positionInGrid),
	};
}


//typedef struct _CubeMesh {
//	uint index;
//	MeshVertexData vertices[kVertexCountPerCube];
//	uint16_t indices[kIndexCountPerCube];
//	MeshPrimitiveData primitives[kPrimitiveCountPerCube];
//} CubeMesh;
//static_assert(kCubeMeshSize == sizeof(CubeMesh), "kCubeMeshSize must match the size of CubeMesh.");
//static_assert(sizeof(CubeMesh_cpu) == sizeof(CubeMesh), "The size of CubeMesh_cpu must match the size of CubeMesh.");


kernel void meshGenerationKernel(
	constant Uniforms & uniforms [[ buffer(0) ]],
	texture3d<ushort, access::read> voxel3DTexture [[ texture(0) ]],
	//texture3d<uint, access::write> DEBUG_outTexture [[ texture(1) ]],
	device MeshVertexData *outputVerticesBuffer [[ buffer(1) ]],
	device uint *outputIndicesBuffer [[ buffer(2) ]],
	ushort3 positionInGrid [[thread_position_in_grid]]
) {
	uint cubeI = ((positionInGrid.z) * voxel3DTexture.get_height() + positionInGrid.y) * voxel3DTexture.get_width() + positionInGrid.x;
	
	uint vertexBase = cubeI * kVertexCountPerCube;
	device MeshVertexData *outputVertices = &outputVerticesBuffer[vertexBase];
	uint indexBase = cubeI * kIndexCountPerCube;
	device uint *outputIndices = &outputIndicesBuffer[indexBase];
	
	uchar3 position = uchar3(positionInGrid);
	uchar4 color = uchar4(voxel3DTexture.read(positionInGrid));
	
	for (uchar primitiveI = 0; primitiveI < kPrimitiveCountPerCube; ++primitiveI) {
		thread const MeshTriIndexData &triIndices = calculateTriIndices(primitiveI);
		outputIndices[primitiveI * 3 + 0] = indexBase + triIndices.indices[0];
		outputIndices[primitiveI * 3 + 1] = indexBase + triIndices.indices[1];
		outputIndices[primitiveI * 3 + 2] = indexBase + triIndices.indices[2];
		
		thread const MeshPrimitiveData &primitive = calculatePrimitive(primitiveI, positionInGrid, color);
		outputVertices[primitiveI * 3 + 0] = (MeshVertexData){
			position + kCubeVertices[primitiveI * 3 + 0],
			primitive
		};
		outputVertices[primitiveI * 3 + 1] = (MeshVertexData){
			position + kCubeVertices[primitiveI * 3 + 1],
			primitive
		};
		outputVertices[primitiveI * 3 + 2] = (MeshVertexData){
			position + kCubeVertices[primitiveI * 3 + 2],
			primitive
		};
	}
	
	//DEBUG_outTexture.write(uint4(uint3(positionInGrid), 0), positionInGrid);
}



// MARK: Vertex Stage

typedef struct {
	float3 position [[attribute(VertexAttributePosition)]];
	float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct {
	float4 position [[position]];
	float2 texCoord;
	float4 voxelCoord;
} ColorInOut;

vertex ColorInOut vertexShader(
	Vertex in [[stage_in]],
	constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]]
) {
	ColorInOut out;
	
	const float4x4 transform = uniforms.projectionMatrix * uniforms.modelViewMatrix;
	
	float4 position = float4(in.position, 1.0);
	out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
	out.texCoord = in.texCoord;
	out.voxelCoord = uniforms.modelMatrix * position;

	return out;
}

//vertex ColorInOut meshGenerationVertexShader(
//	Vertex in [[stage_in]],
//	constant Uniforms & uniforms [[ buffer(0) ]],
//	texture3d<half, access::read> voxel3DTexture [[ texture(0) ]],
//	device CubeMesh *outputMeshes [[ buffer(1) ]]
//) {
//	ColorInOut out;
//	
//	meshGenerationKernel(
//		uniforms,
//		voxel3DTexture,
//		outputMeshes,
//		uint3(in.position),
//		((in.position.z) * kCubesPerBlockY + in.position.y) * kCubesPerBlockX + in.position.x
//	);
//	
//	return out;
//}



// MARK: Fragment Stage

struct FragmentIn
{
	half4 color;
	half3 normal;
	//MeshPrimitiveData primitiveData;
};

fragment half4 fragmentShader(
	FragmentIn in [[stage_in]]
	//constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]]
) {
	half4 color = in.color;
	//color.rgb = abs(half3(in.primitiveData.voxelCoord + 1) / 20);
	
	half3 normal = in.normal;
	half3 lightDirection = normalize(half3(1, 2, 3));
	
	half ambientIntensity = -0.25;
	half lightIntensity = 5.0;
	half colorIntensity = inverse_lerp(-1.0h, 1.0h, dot(normal, lightDirection)) * lightIntensity + ambientIntensity;
	colorIntensity = colorIntensity / (1.0 + colorIntensity);
	
	// TEMP: Normal-coloring
	//color = half4(inverse_lerp(half3(-1), half3(1), normal), 1);
	
	return half4(
		color.rgb * colorIntensity,
		color.a
	);
}
