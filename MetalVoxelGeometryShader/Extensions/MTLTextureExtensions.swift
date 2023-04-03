//
//  MTLTextureExtensions.swift
//  MetalVoxelGeometryShader
//
//  Created by Cap'n Slipp on 4/2/23.
//

import Metal



extension MTLTexture
{
	var size: MTLSize {
		MTLSize(width: self.width, height: self.height, depth: self.depth)
	}
}
