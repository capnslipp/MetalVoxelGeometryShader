//
//  MTLSizeExtensions.swift
//  MetalVoxelGeometryShader
//
//  Created by Cap'n Slipp on 4/2/23.
//

import Metal



extension MTLSize
{
	var x: Int {
		get { self.width }
		set { self.width = newValue }
	}
	var y: Int {
		get { self.height }
		set { self.height = newValue }
	}
	var z: Int {
		get { self.depth }
		set { self.depth = newValue }
	}
	
	
	init(_ width: Int, _ height: Int, _ depth: Int) {
		self.init(width: width, height: height, depth: depth)
	}
	
	init(_ size: simd_uint3) {
		self.init(Int(size.x), Int(size.y), Int(size.z))
	}
	
	init(width: Int) {
		self.init(width, 1, 1)
	}
	
	static let one = MTLSize(1, 1, 1)
}
