//
//  SIMDMatrixExtensions.swift
//  MetalVoxelGeometryShader
//
//  Created by Cap'n Slipp on 4/7/23.
//

import simd



protocol SIMDMatrixExtensions
{
	associatedtype Scalar : SIMDScalar, BinaryFloatingPoint
	typealias Vector = SIMD4<Scalar>
	typealias RowVector = SIMD4<Scalar>
	
	init(_ floatMatrix: float4x4)
	init(_ doubleMatrix: double4x4)
	
	init(columns: [Vector])
	var columnsArray: [Vector] { get set }
	
	var rows: [RowVector] { get set }
	
	
	/// MARK: `simd_float4x4`/`simd_double4x4` Implemented Members
	
	init(columns: (Vector, Vector, Vector, Vector))
	var columns: (Vector, Vector, Vector, Vector) { get set }
	
	init(rows: [Vector])
}



extension float4x4 : SIMDMatrixExtensions
{
	typealias Scalar = Float
}

extension double4x4 : SIMDMatrixExtensions
{
	typealias Scalar = Double
}


extension SIMDMatrixExtensions
{
	init(_ floatMatrix: float4x4) {
		self.init(columns: (
			Vector(floatMatrix[0]),
			Vector(floatMatrix[1]),
			Vector(floatMatrix[2]),
			Vector(floatMatrix[3])
		))
	}
	
	init(_ doubleMatrix: double4x4) {
		self.init(columns: (
			Vector(doubleMatrix[0]),
			Vector(doubleMatrix[1]),
			Vector(doubleMatrix[2]),
			Vector(doubleMatrix[3])
		))
	}
	
	
	init(columns columnsArray: [Vector])
	{
		precondition(columnsArray.count == 4)
		self.init(columns: ( columnsArray[0], columnsArray[1], columnsArray[2], columnsArray[3] ))
	}
	
	var columnsArray: [Vector] {
		get {
			let columns = self.columns
			return [ columns.0, columns.1, columns.2, columns.3 ]
		}
		set {
			precondition(newValue.count == 4)
			self.columns = ( newValue[0], newValue[1], newValue[2], newValue[3] )
		}
	}
	
	
	var rows: [RowVector] {
		get {
			let columns = self.columns
			return [
				RowVector(columns.0.x, columns.1.x, columns.2.x, columns.3.x),
				RowVector(columns.0.y, columns.1.y, columns.2.y, columns.3.y),
				RowVector(columns.0.z, columns.1.z, columns.2.z, columns.3.z),
				RowVector(columns.0.w, columns.1.w, columns.2.w, columns.3.w),
			]
		}
		set {
			self = Self(rows: newValue)
		}
	}
}
