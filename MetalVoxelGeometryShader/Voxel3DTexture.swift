//
//  Vox3DTexture.swift
//  MetalVoxelGeometryShader
//
//  Created by Cap'n Slipp on 3/3/23.
//

import AppKit
import Metal
import MDLVoxelAsset
import With



struct Voxel3DTextureRGBAColor
{
	let r: UInt8, g: UInt8, b: UInt8, a: UInt8
	
	static func from(nsColor: NSColor) -> Voxel3DTextureRGBAColor {
		let rgbColor = nsColor.usingColorSpace(.genericRGB)!
		return Voxel3DTextureRGBAColor(
			r: UInt8(rgbColor.redComponent * CGFloat(UInt8.max)),
			g: UInt8(rgbColor.greenComponent * CGFloat(UInt8.max)),
			b: UInt8(rgbColor.blueComponent * CGFloat(UInt8.max)),
			a: UInt8(rgbColor.alphaComponent * CGFloat(UInt8.max))
		)
	}
}



fileprivate extension MTLSize
{
	var x: Int { self.width }
	var y: Int { self.height }
	var z: Int { self.depth }
}



extension MTLDevice
{
	func makeVoxel3DTextureRGBA(fromAsset asset: MDLVoxelAsset, model: MDLVoxelAssetModel) -> MTLTexture?
	{
		let size = withMap(model.voxelDimensions){ MTLSize(width: Int($0.x), height: Int($0.y), depth: Int($0.z)) }
		
		let descriptor = with(MTLTextureDescriptor.textureBufferDescriptor(
			with: .rgba8Unorm,
			width: size.x,
			usage: .shaderRead
		)){ d in
			d.textureType = .type3D
			d.width = size.width
			d.height = size.height
			d.depth = size.depth
			
			d.cpuCacheMode = .writeCombined
			d.storageMode = .managed // TODO: try .private
		}
		
		guard let texture = self.makeTexture(descriptor: descriptor) else {
			return nil
		}
		
		let voxelCount = Int(size.x * size.y * size.z)
		
		let paletteTextureColors = asset.paletteColors.map(Voxel3DTextureRGBAColor.from(nsColor:))
		
		var rawData = [Voxel3DTextureRGBAColor](
			unsafeUninitializedCapacity: voxelCount,
			initializingWith: { buffer, initializedCount in
				buffer.initialize(repeating: Voxel3DTextureRGBAColor(r: 0x00, g: 0x00, b: 0x00, a: 0x00))
				initializedCount = voxelCount
			}
		)
		let voxelPaletteIndices: [[[NSNumber]]] = model.voxelPaletteIndices;
		for (x, yzArray): (Int, [[NSNumber]]) in voxelPaletteIndices.enumerated() {
			for (y, zArray): (Int, [NSNumber]) in yzArray.enumerated() {
				for (z, colorIndexNumber): (Int, NSNumber) in zArray.enumerated() {
					let colorIndex = colorIndexNumber.intValue
					let rgbaColor = paletteTextureColors[colorIndex]
					rawData[(z * size.y * size.x) + (y * size.x) + x] = rgbaColor
				}
			}
		}
		texture.replace(
			region: MTLRegionMake3D(0, 0, 0, size.width, size.height, size.depth),
			mipmapLevel: 0,
			slice: 0,
			withBytes: rawData,
			bytesPerRow: size.x * MemoryLayout<Voxel3DTextureRGBAColor>.size,
			bytesPerImage: (size.x * size.y) * MemoryLayout<Voxel3DTextureRGBAColor>.size
		)
		
		return texture
	}
}
