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



// MARK: Mesh Shader - Object Stage

typedef struct {
	half4 color;
	float4x4 transform;
} MeshPayload;
static_assert(kMeshPayloadMemoryLength == sizeof(MeshPayload), "kMeshPayloadMemoryLength must match the size of MeshPayload.");

[[object, max_total_threads_per_threadgroup(kCubesPerBlock)]]
void meshObjectShader(
	object_data MeshPayload *payload [[payload]],
	constant Uniforms & uniforms [[ buffer(0) ]],
	//const device void *inputData [[buffer(0)]],
	const texture3d<half> voxel3DTexture [[ texture(0) ]],
	uint cubeI [[thread_index_in_threadgroup]],
	uint3 positionInGrid [[threadgroup_position_in_grid]],
	mesh_grid_properties meshGridProperties
) {
	if (cubeI < kCubesPerBlock) {
		constexpr sampler colorSampler(coord::pixel);
		uint3 voxelIndex = uint3(positionInGrid.x + 39, positionInGrid.y + 19, positionInGrid.z);
		payload[cubeI].color = voxel3DTexture.sample(colorSampler, float3(voxelIndex));
		//payload[cubeI].color = voxel3DTexture.read(voxelIndex);
		payload[cubeI].transform = uniforms.projectionMatrix * uniforms.modelViewMatrix;
	}
	
	if (cubeI == 0)
		meshGridProperties.set_threadgroups_per_grid(uint3(kCubesPerBlockX, kCubesPerBlockY, kCubesPerBlockZ));
}



// MARK: Mesh Shader - Mesh Stage

typedef struct {
	float4 position [[position]];
} MeshVertexData;

MeshVertexData calculateVertex(uint threadI, uint3 positionInGrid) {
	return (MeshVertexData){
		/* position: */ float4(
			float3(positionInGrid) +
				float3(threadI % 2, threadI / 2 % 2, threadI / 4 % 2),
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
	float3 voxelCoord;
} MeshPrimitiveData;

MeshPrimitiveData calculatePrimitive(uint threadI, uint3 positionInGrid, const object_data MeshPayload& payload) {
	return (MeshPrimitiveData){
		/* color: */ payload.color,
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


[[mesh, max_total_threads_per_threadgroup(kThreadsPerCube)]]
void meshShader(
	CubeMesh outputMesh,
	const object_data MeshPayload& payload [[payload]],
	uint threadI [[thread_index_in_threadgroup]],
	uint3 positionInGrid [[threadgroup_position_in_grid]]
) {
	if (threadI < kVertexCountPerCube) {
		MeshVertexData vertexData = calculateVertex(threadI, positionInGrid);
		vertexData.position = payload.transform * vertexData.position;
		outputMesh.set_vertex(threadI, vertexData);
	}
	
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

fragment float4 fragmentShader(
	FragmentIn in [[stage_in]],
	constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]]
) {
	return float4(in.primitiveData.color);
}
