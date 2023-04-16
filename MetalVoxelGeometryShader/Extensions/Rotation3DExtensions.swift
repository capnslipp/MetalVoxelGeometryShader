//
//  Rotation3DExtensions.swift
//  MetalVoxelGeometryShader
//
//  Created by Cap'n Slipp on 4/8/23.
//

import Spatial



extension Rotation3D
{
	/// The normalized zero-rotation quaternion (e.g. a real part of `1.0` and imaginary part of `(0, 0, 0)`).
	/// Any quaternion multiplied by the identity value results in the same quaternion (as with all multiplicative identity values in mathematics).
	public static let identity = {
		let identity = Self.zero.normalized()
		assert(identity.quaternion.real == 1.0)
		assert(identity.quaternion.imag == SIMD3<Double>(0, 0, 0))
		return identity
	}()
	/// The facing normal vector such that a rotation to face this direction with `identityUpVector` as a roll-rotation up will result in no rotation— the identity rotation.
	/// E.G. `Rotation3D(forward: Rotation3D.identityFacingVector, up: Rotation3D.identityUpVector) == Rotation3D.identity`.
	public static let identityFacingVector = Vector3D.forward
	/// The up normal vector— generally what's considered “up” in `Rotation3D`'s math calculations (comes into play with euler rotation order assumptions and other contexts).
	/// See `identityFacingVector` for an identity proof.
	public static let identityUpVector = Vector3D.up
	
	
	public var isNaN: Bool {
		let quaternionVector = self.quaternion.vector
		return quaternionVector.x.isNaN || quaternionVector.y.isNaN || quaternionVector.z.isNaN || quaternionVector.w.isNaN
	}
	
	
	public func inversed() -> Rotation3D {
		return Rotation3D(simd_inverse(self.quaternion))
	}
	public static func / (a: Rotation3D, b: Rotation3D) -> Rotation3D {
		return a * b.inversed()
	}
	
	
	public func normalized() -> Rotation3D {
		return Rotation3D(simd_normalize(self.quaternion))
	}
}



extension Rotation3D : Rotatable3D
{
	public func rotated(by rotation: Rotation3D) -> Rotation3D { return rotated(by: rotation.quaternion) }
	public func rotated(by quaternion: simd_quatd) -> Rotation3D {
		Rotation3D(self.quaternion * quaternion)
	}
	
}
