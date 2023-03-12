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



// MARK: Mesh Shader - Object Stage

typedef struct {
	half4 color;
	float4x4 transform;
	uint3 blockPosition_blocks;
} ObjectToMeshPayload;
static_assert(kObjectToMeshPayloadSize == sizeof(ObjectToMeshPayload), "kObjectToMeshPayloadMemoryLength must match the size of MeshPayload.");

[[object,
	max_total_threadgroups_per_mesh_grid(kMaxTotalThreadgroupsPerMeshGrid),
	max_total_threads_per_threadgroup(kMaxTotalThreadsPerObjectThreadgroup)
]]
void meshObjectShader(
	object_data ObjectToMeshPayload *payloads [[payload]],
	constant Uniforms & uniforms [[ buffer(0) ]],
	//const device void *inputData [[buffer(0)]],
	const texture3d<half> voxel3DTexture [[ texture(0) ]],
	uint threadI [[thread_index_in_threadgroup]],
	uint3 positionInGrid [[thread_position_in_grid]],
	uint3 blockPosition_blocks [[threadgroup_position_in_grid]],
	uint threadgroup_size [[threads_per_threadgroup]],
	mesh_grid_properties meshGridProperties
) {
	//if (blockPosition_blocks.x == 1) return;
	
	uint cubeI = threadI;
	if (cubeI < kCubesPerBlock) {
		//constexpr sampler colorSampler(coord::pixel);
		uint3 voxelIndex = uint3(positionInGrid.x + 39, positionInGrid.y + 19, positionInGrid.z);
		//uint3 voxelIndex = uint3(cubeI + 39, 19, 0);
		//payload.color = voxel3DTexture.sample(colorSampler, float3(voxelIndex));
		payloads[cubeI].color = voxel3DTexture.read(voxelIndex);
		payloads[cubeI].transform = uniforms.projectionMatrix * uniforms.modelViewMatrix;
		payloads[cubeI].blockPosition_blocks = blockPosition_blocks;
	}
	//if (blockPosition_blocks.x == 0)
	//	payloads[cubeI].color = half4(1, 0, 0, 1);
	//if (blockPosition_blocks.x == 1)
	//	payloads[cubeI].color = half4(0, 1, 0, 1);
	//if (cubeI == 63)
	//	payload.color = half4(1, 0, 1, 1);
	//if (cubeI == 64)
	//	payload.color = half4(1, 1, 1, 1);
	//if (cubeI == 0) {
	//	payload.color = half4(
	//		threadgroup_size % 2,
	//		threadgroup_size / 2 % 2,
	//		threadgroup_size / 4 % 2,
	//		//threadgroup_size / 8 % 2,
	//		//threadgroup_size / 16 % 2,
	//		//threadgroup_size / 32 % 2,
	//		1
	//	);
	//}
	
	if (threadI == 0)
		meshGridProperties.set_threadgroups_per_grid(kCubesPerBlockXYZ);
}



// MARK: Mesh Shader - Mesh Stage

typedef struct {
	float4 position [[position]];
} MeshVertexData;

MeshVertexData calculateVertex(uint threadI, uint3 positionInGrid, const object_data ObjectToMeshPayload& payload) {
	return (MeshVertexData){
		/* position: */ payload.transform * float4(
			float3(positionInGrid) +
				float3(0.5) + 
				(float3(threadI % 2, threadI / 2 % 2, threadI / 4 % 2) - 0.5) * 0.9,
			1.0
		),
	};
}


typedef struct {
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


typedef struct {
	half4 color;
	half3 normal;
	float3 voxelCoord;
} MeshPrimitiveData;

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

MeshPrimitiveData calculatePrimitive(uint threadI, uint3 positionInGrid, const object_data ObjectToMeshPayload& payload) {
	return (MeshPrimitiveData){
		/* color: */ payload.color,
		/* normal: */ calculateNormal(threadI),
		/* voxelCoord: */ float3(positionInGrid),
	};
}


using CubeMesh = metal::mesh<
	MeshVertexData, // vertex type
	MeshPrimitiveData, // primitive type
	kVertexCountPerCube, // maximum vertices
	kPrimitiveCountPerCube, // maximum primitives
	metal::topology::triangle // topology
>;


[[mesh,
	max_total_threads_per_threadgroup(kMaxTotalThreadsPerMeshThreadgroup)
]]
void meshShader(
	CubeMesh outputMesh,
	const object_data ObjectToMeshPayload *payloads [[payload]],
	uint threadI [[thread_index_in_threadgroup]],
	uint3 positionInBlock_cubes [[threadgroup_position_in_grid]]
) {
	uint cubeI = (positionInBlock_cubes.z * kCubesPerBlockX * kCubesPerBlockY) +
		(positionInBlock_cubes.y * kCubesPerBlockX) +
		(positionInBlock_cubes.x);
	const object_data ObjectToMeshPayload & payload = payloads[cubeI];
	uint3 positionInGrid = (payload.blockPosition_blocks * kCubesPerBlockXYZ) + positionInBlock_cubes;
	//if (payload.blockPosition_cubes.x >= 64)
	//	return;
	
	if (threadI < kVertexCountPerCube)
		outputMesh.set_vertex(threadI, calculateVertex(threadI, positionInGrid, payload));
	
	if (threadI < kPrimitiveCountPerCube) {
		MeshTriIndexData triIndices = calculateTriIndices(threadI);
		outputMesh.set_index(threadI * 3 + 0, triIndices.indices[0]);
		outputMesh.set_index(threadI * 3 + 1, triIndices.indices[1]);
		outputMesh.set_index(threadI * 3 + 2, triIndices.indices[2]);
	}
	
	if (threadI < kPrimitiveCountPerCube)
		outputMesh.set_primitive(threadI, calculatePrimitive(threadI, positionInGrid, payload));
	
	if (threadI == 0)
		outputMesh.set_primitive_count(kPrimitiveCountPerCube);
}



// MARK: Fragment Stage

struct FragmentIn
{
	MeshVertexData vertexData;
	MeshPrimitiveData primitiveData;
};

fragment half4 fragmentShader(
	FragmentIn in [[stage_in]]
	//constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]]
) {
	half4 color = in.primitiveData.color;
	//color.rgb = abs(half3(in.primitiveData.voxelCoord + 1) / 20);
	
	half3 normal = in.primitiveData.normal;
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
