//
//  MTLVertexFormatExtensions.swift
//  MetalVoxelGeometryShader
//
//  Created by Cap'n Slipp on 4/3/23.
//

import Metal
import simd



extension MTLVertexFormat
{
	var size: Int {
		MemoryLayout.size(ofValue: self.equivalentType)
	}
	
	var alignment: Int {
		MemoryLayout.alignment(ofValue: self.equivalentType)
	}
	
	var stride: Int {
		MemoryLayout.stride(ofValue: self.equivalentType)
	}
	
	
	var equivalentType: Any.Type
	{
		switch self {
			case .uchar, .ucharNormalized:
				return simd_uchar1.self
			case .uchar2, .uchar2Normalized:
				return simd_uchar2.self
			case .uchar3, .uchar3Normalized:
				return simd_uchar3.self
			case .uchar4, .uchar4Normalized, .uchar4Normalized_bgra:
				return simd_uchar4.self
			case .char, .charNormalized:
				return simd_char1.self
			case .char2, .char2Normalized:
				return simd_char2.self
			case .char3, .char3Normalized:
				return simd_char3.self
			case .char4, .char4Normalized:
				return simd_char4.self
			case .ushort, .ushortNormalized:
				return simd_ushort1.self
			case .ushort2, .ushort2Normalized:
				return simd_ushort2.self
			case .ushort3, .ushort3Normalized:
				return simd_ushort3.self
			case .ushort4, .ushort4Normalized:
				return simd_ushort4.self
			case .short, .shortNormalized:
				return simd_short1.self
			case .short2, .short2Normalized:
				return simd_short2.self
			case .short3, .short3Normalized:
				return simd_short3.self
			case .short4, .short4Normalized:
				return simd_short4.self
			case .half:
				return simd_short1.self
			case .half2:
				return simd_short2.self
			case .half3:
				return simd_ushort3.self
			case .half4:
				return simd_ushort4.self
			case .float:
				return simd_float1.self
			case .float2:
				return simd_float2.self
			case .float3:
				return simd_float3.self
			case .float4:
				return simd_float4.self
			case .int:
				return simd_int1.self
			case .int2:
				return simd_int2.self
			case .int3:
				return simd_int3.self
			case .int4:
				return simd_int4.self
			case .uint:
				return simd_uint1.self
			case .uint2:
				return simd_uint2.self
			case .uint3:
				return simd_uint3.self
			case .uint4:
				return simd_uint4.self
			case .int1010102Normalized:
				return Int32.self
			case .uint1010102Normalized:
				return UInt32.self
			
			case .invalid:
				fatalError("Invalid case \(self)")
			@unknown default:
				fatalError("Unimplemented case \(self)")
		}
	}
}
