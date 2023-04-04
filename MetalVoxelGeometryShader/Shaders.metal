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
	char3 normal;
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

static CONSTANT uchar3 kCubeVertices[kVertexCountPerCube] = {
	// Z- face
	uchar3(0, 0, 0),
	uchar3(1, 0, 0),
	uchar3(0, 1, 0),
	uchar3(1, 1, 0),
	// Z+ face
	uchar3(0, 0, 1),
	uchar3(1, 0, 1),
	uchar3(0, 1, 1),
	uchar3(1, 1, 1),
	// Y- face
	uchar3(0, 0, 0),
	uchar3(1, 0, 0),
	uchar3(0, 0, 1),
	uchar3(1, 0, 1),
	// Y+ face
	uchar3(0, 1, 0),
	uchar3(1, 1, 0),
	uchar3(0, 1, 1),
	uchar3(1, 1, 1),
	// X- face
	uchar3(0, 0, 0),
	uchar3(0, 1, 0),
	uchar3(0, 0, 1),
	uchar3(0, 1, 1),
	// X+ face
	uchar3(1, 0, 0),
	uchar3(1, 1, 0),
	uchar3(1, 0, 1),
	uchar3(1, 1, 1),
};

uchar3 calculateVertexPosition(uchar faceI, uchar vertexI, uchar3 voxelCoord) {
	return voxelCoord + kCubeVertices[faceI * kVertexCountPerFace + vertexI];
}

MeshVertexData calculateVertex(uchar faceI, uchar vertexI, uchar3 voxelCoord, thread const MeshPrimitiveData &primitive) {
	return (MeshVertexData){
		/* position: */ calculateVertexPosition(faceI, vertexI, voxelCoord),
		/* primitive: */ primitive,
	};
}


typedef struct _MeshTriIndexData {
	uchar indices[3];
} MeshTriIndexData;

static CONSTANT MeshTriIndexData kCubeTriIndices[kPrimitiveCountPerCube] = {
	// Z- face
	(MeshTriIndexData){ 0, 2, 1 },
	(MeshTriIndexData){ 3, 1, 2 },
	// Z+ face
	(MeshTriIndexData){ 4, 5, 6 },
	(MeshTriIndexData){ 7, 6, 5 },
	// Y- face
	(MeshTriIndexData){ 8, 9, 10 },
	(MeshTriIndexData){ 11, 10, 9 },
	// Y+ face
	(MeshTriIndexData){ 12, 14, 13 },
	(MeshTriIndexData){ 15, 13, 14 },
	// X- face
	(MeshTriIndexData){ 16, 18, 17 },
	(MeshTriIndexData){ 19, 17, 18 },
	// X+ face
	(MeshTriIndexData){ 20, 21, 22 },
	(MeshTriIndexData){ 23, 22, 21 },
};

MeshTriIndexData calculateTriIndices(uint primitiveI) {
	return kCubeTriIndices[primitiveI];
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

static CONSTANT char3 kCubeNormals[kFaceCountPerCube] = {
	char3(0, 0, -1),
	char3(0, 0, +1),
	
	char3(0, -1, 0),
	char3(0, +1, 0),
	
	char3(-1, 0, 0),
	char3(+1, 0, 0),
};


MeshPrimitiveData calculateFace(uchar faceI, uchar3 voxelCoord) {
	return (MeshPrimitiveData){
		/* normal: */ kCubeNormals[faceI],
		/* voxelCoord: */ voxelCoord,
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
	//texture3d<ushort, access::read> voxel3DTexture [[ texture(0) ]],
	device const int4 *voxels [[ buffer(3) ]],
	//texture3d<uint, access::write> DEBUG_outTexture [[ texture(1) ]],
	device MeshVertexData *outputVerticesBuffer [[ buffer(1) ]],
	device uint *outputIndicesBuffer [[ buffer(2) ]],
	uint cubeI [[thread_position_in_grid]]
) {
	if (cubeI >= uniforms.voxelCount)
		return;
	
	int4 voxel = voxels[cubeI];
	
	uint vertexBaseI = cubeI * kVertexCountPerCube;
	device MeshVertexData *outputVertices = &outputVerticesBuffer[vertexBaseI];
	uint indexBaseI = cubeI * kIndexCountPerCube;
	device uint *outputIndices = &outputIndicesBuffer[indexBaseI];
	
	uchar3 voxelCoord = uchar3(voxel.xyz);
	
	for (uchar faceI = 0; faceI < kFaceCountPerCube; ++faceI) {
		uint faceVertexBaseI = faceI * kVertexCountPerFace;
		
		for (uchar facePrimitiveI = 0; facePrimitiveI < kPrimitiveCountPerFace; ++facePrimitiveI) {
			uchar primitiveI = (faceI * kPrimitiveCountPerFace) + facePrimitiveI;
			
			thread const MeshTriIndexData &triIndices = calculateTriIndices(primitiveI);
			outputIndices[primitiveI * kIndexCountPerPrimitive + 0] = vertexBaseI + triIndices.indices[0];
			outputIndices[primitiveI * kIndexCountPerPrimitive + 1] = vertexBaseI + triIndices.indices[1];
			outputIndices[primitiveI * kIndexCountPerPrimitive + 2] = vertexBaseI + triIndices.indices[2];
		} // primitiveI
		
		thread const MeshPrimitiveData &primitive = calculateFace(faceI, voxelCoord);
		
		device MeshVertexData *outputFaceVertices = &outputVertices[faceVertexBaseI];
		outputFaceVertices[0] = calculateVertex(faceI, 0, voxelCoord, primitive);
		outputFaceVertices[1] = calculateVertex(faceI, 1, voxelCoord, primitive);
		outputFaceVertices[2] = calculateVertex(faceI, 2, voxelCoord, primitive);
		outputFaceVertices[3] = calculateVertex(faceI, 3, voxelCoord, primitive);
	} // faceI
	
	//DEBUG_outTexture.write(uint4(uint3(positionInGrid), 0), positionInGrid);
}



// MARK: Vertex Stage

typedef struct _VertexIn {
	uchar3 position [[attribute(0)]];
	char3 normal [[attribute(1)]];
	uchar3 voxelCoord [[attribute(2)]];
} VertexIn;

typedef struct _VertexToFragment {
	float4 position [[position]];
	half4 color [[flat]];
	half3 normal [[flat]];;
} VertexToFragment;

vertex VertexToFragment vertexShader(
	VertexIn in [[stage_in]],
	texture3d<ushort, access::read> voxel3DTexture [[ texture(0) ]],
	constant Uniforms & uniforms [[ buffer(1) ]]
) {
	VertexToFragment out;
	
	
	const float4x4 transform = uniforms.projectionMatrix * uniforms.modelViewMatrix;
	
	float4 modelPosition = float4(float3(in.position), 1.0);
	out.position = transform * modelPosition;
	
	out.color = half4(voxel3DTexture.read(ushort3(in.voxelCoord))) / 255.0h;
	
	out.normal = half3(in.normal);

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

fragment half4 fragmentShader(
	VertexToFragment in [[stage_in]]
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
