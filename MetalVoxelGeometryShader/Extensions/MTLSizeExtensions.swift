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
	
	init(uniform: Int) {
		self.init(uniform, uniform, uniform)
	}
	
	static let one = MTLSize(1, 1, 1)
}



extension MTLSize
{
	static func + (a: Self, b: Self) -> Self {
		return Self(
			a.width + b.width,
			a.height + b.height,
			a.depth + b.depth
		)
	}
	static func += (v: inout Self, o: Self) {
		v = v + o
	}
	
	
	static func - (a: Self, b: Self) -> Self {
		return Self(
			a.width - b.width,
			a.height - b.height,
			a.depth - b.depth
		)
	}
	static func -= (v: inout Self, o: Self) {
		v = v - o
	}
	
	
	static func * (a: Self, b: Self) -> Self {
		return Self(
			a.width * b.width,
			a.height * b.height,
			a.depth * b.depth
		)
	}
	static func *= (v: inout Self, o: Self) {
		v = v * o
	}
	
	
	static func / (a: Self, b: Self) -> Self {
		return Self(
			a.width / b.width,
			a.height / b.height,
			a.depth / b.depth
		)
	}
	static func /= (v: inout Self, o: Self) {
		v = v / o
	}
	
	func dividing(by other: Self, round roundingRule: FloatingPointRoundingRule) -> Self
	{
		switch roundingRule {
			case .toNearestOrAwayFromZero:
				fatalError("not implemented")
			case .toNearestOrEven:
				fatalError("not implemented")
			case .up:
				fatalError("not implemented")
			case .down:
				fatalError("not implemented")
			case .towardZero:
				return self / other
			case .awayFromZero:
				return (self - MTLSize(uniform: 1) + other) / other
			@unknown default:
				fatalError("not implemented")
		}
	}
	
	mutating func divide(by other: Self, round roundingRule: FloatingPointRoundingRule) {
		self = dividing(by: other, round: roundingRule)
	}
	
	
	static func % (a: Self, b: Self) -> Self {
		return Self(
			a.width % b.width,
			a.height % b.height,
			a.depth % b.depth
		)
	}
	static func %= (v: inout Self, o: Self) {
		v = v % o
	}
	
	
	static func * (v: Self, scale: Int) -> Self {
		return v * MTLSize(uniform: scale)
	}
	static func *= (v: inout Self, scale: Int) {
		v = v * scale
	}
	static func * (scale: Int, v: Self) -> Self {
		return MTLSize(uniform: scale) * v
	}
	
	
	static func / (v: Self, inverseScale: Int) -> Self {
		return v / MTLSize(uniform: inverseScale)
	}
	static func /= (v: inout Self, inverseScale: Int) {
		v = v / inverseScale
	}
	static func / (inverseScale: Int, v: Self) -> Self {
		return MTLSize(uniform: inverseScale) / v
	}
	
	
	static func % (v: Self, inverseScale: Int) -> Self {
		return v % MTLSize(uniform: inverseScale)
	}
	static func %= (v: inout Self, inverseScale: Int) {
		v = v / inverseScale
	}
	static func % (inverseScale: Int, v: Self) -> Self {
		return MTLSize(uniform: inverseScale) % v
	}
}
