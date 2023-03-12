//
//	Renderer.swift
//	MetalVoxelGeometryShader
//
//	Created by Cap'n Slipp on 2/28/23.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd
import MDLVoxelAsset
import With



// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 1

enum RendererError : Error {
	case badVertexDescriptor
}

class Renderer : NSObject, MTKViewDelegate
{
	public let device: MTLDevice
	let commandQueue: MTLCommandQueue
	var dynamicUniformBuffer: MTLBuffer
	var pipelineState: MTLRenderPipelineState
	var depthState: MTLDepthStencilState
	var colorMap: MTLTexture
	var voxelTexture: MTLTexture
	
	let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
	
	var uniformBufferOffset = 0
	
	var uniformBufferIndex = 0
	
	var uniforms: UnsafeMutablePointer<Uniforms>
	
	var projectionMatrix: matrix_float4x4 = matrix_float4x4()
	
	var rotation: Float = 0
	
	//var mesh: MTKMesh
	
	init?(metalKitView: MTKView)
	{
		self.device = metalKitView.device!
		self.commandQueue = self.device.makeCommandQueue()!
		
		let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
		
		self.dynamicUniformBuffer = self.device.makeBuffer(
			length: uniformBufferSize,
			options: [ .cpuCacheModeWriteCombined, .storageModeShared, ]
		)!
		
		self.dynamicUniformBuffer.label = "UniformBuffer"
		
		uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:Uniforms.self, capacity:1)
		
		metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
		metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
		metalKitView.sampleCount = 1
		
		//let mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
		
		do {
			pipelineState = try Renderer.buildMeshRenderPipelineWithDevice(
				device: device,
				metalKitView: metalKitView
			)
			print("pipelineState.maxTotalThreadsPerThreadgroup: \(pipelineState.maxTotalThreadsPerThreadgroup)")
			print("pipelineState.threadgroupSizeMatchesTileSize: \(pipelineState.threadgroupSizeMatchesTileSize)")
			print("pipelineState.supportIndirectCommandBuffers: \(pipelineState.supportIndirectCommandBuffers)")
			print("pipelineState.maxTotalThreadgroupsPerMeshGrid: \(pipelineState.maxTotalThreadgroupsPerMeshGrid)")
			print("pipelineState.maxTotalThreadsPerMeshThreadgroup: \(pipelineState.maxTotalThreadsPerMeshThreadgroup)")
			print("pipelineState.maxTotalThreadsPerObjectThreadgroup: \(pipelineState.maxTotalThreadsPerObjectThreadgroup)")
			print("pipelineState.meshThreadExecutionWidth: \(pipelineState.meshThreadExecutionWidth)")
			print("pipelineState.objectThreadExecutionWidth: \(pipelineState.objectThreadExecutionWidth)")
		} catch {
			print("Unable to compile render pipeline state. Error info: \(error)")
			return nil
		}
		
		let depthStateDescriptor = MTLDepthStencilDescriptor()
		depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
		depthStateDescriptor.isDepthWriteEnabled = true
		self.depthState = device.makeDepthStencilState(descriptor:depthStateDescriptor)!
		
		//do {
		//	mesh = try Renderer.buildMesh(device: device, mtlVertexDescriptor: mtlVertexDescriptor)
		//} catch {
		//	print("Unable to build MetalKit Mesh. Error info: \(error)")
		//	return nil
		//}
		
		do {
			colorMap = try Renderer.loadTexture(device: device, textureName: "ColorMap")
		} catch {
			print("Unable to load texture. Error info: \(error)")
			return nil
		}
		
		do {
			let path = Bundle.main.path(forResource: "master.Brownstone.NSide", ofType: "vox")!
			let asset = MDLVoxelAsset(url: URL(fileURLWithPath: path), options: [
				kMDLVoxelAssetOptionCalculateShellLevels: false,
				kMDLVoxelAssetOptionSkipNonZeroShellMesh: false,
				kMDLVoxelAssetOptionConvertZUpToYUp: false,
				kMDLVoxelAssetOptionMeshGenerationMode: MDLVoxelAssetMeshGenerationMode.skip.rawValue,
			])
			self.voxelTexture = device.makeVoxel3DTextureRGBA(fromAsset: asset, model: asset.models.first!)!
		} catch {
			print("Unable to generate texture. Error info: \(error)")
			return nil
		}
		
		super.init()
	}

	class func buildMetalVertexDescriptor() -> MTLVertexDescriptor
	{
		// Create a Metal vertex descriptor specifying how vertices will by laid out for input into our render
		//	 pipeline and how we'll layout our Model IO vertices

		let mtlVertexDescriptor = MTLVertexDescriptor()

		mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
		mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
		mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue

		mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
		mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
		mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue

		mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = 12
		mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
		mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex

		mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = 8
		mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
		mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex

		return mtlVertexDescriptor
	}

	class func buildRenderPipelineWithDevice(
		device: MTLDevice,
		metalKitView: MTKView,
		mtlVertexDescriptor: MTLVertexDescriptor
	) throws -> MTLRenderPipelineState {
		/// Build a render state pipeline object

		let library = device.makeDefaultLibrary()

		let vertexFunction = library?.makeFunction(name: "vertexShader")
		let fragmentFunction = library?.makeFunction(name: "fragmentShader")

		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.label = "RenderPipeline"
		pipelineDescriptor.rasterSampleCount = metalKitView.sampleCount
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor

		pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
		pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
		pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat

		return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
	}

	class func buildMeshRenderPipelineWithDevice(
		device: MTLDevice,
		metalKitView: MTKView
	) throws -> MTLRenderPipelineState
	{
		let meshPipelineDescriptor = with(MTLMeshRenderPipelineDescriptor()) {
			$0.label = "MeshRenderPipeline"
			$0.rasterSampleCount = metalKitView.sampleCount
			
			let library = device.makeDefaultLibrary()
			
			let meshObjectFunction = library?.makeFunction(name: "meshObjectShader")
			$0.objectFunction = meshObjectFunction
			let meshFunction = library?.makeFunction(name: "meshShader")
			$0.meshFunction = meshFunction
			let fragmentFunction = library?.makeFunction(name: "fragmentShader")
			$0.fragmentFunction = fragmentFunction
			$0.payloadMemoryLength = kObjectToMeshPayloadMemoryLength
			//$0.maxTotalThreadgroupsPerMeshGrid = 8
			//$0.maxTotalThreadsPerObjectThreadgroup = Int(kCubesPerBlock)
			//$0.maxTotalThreadsPerMeshThreadgroup = Int(kVertexCountPerCube)
			
			$0.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
			$0.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
			$0.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
		}
		
		let (state, _) = try device.makeRenderPipelineState(descriptor: meshPipelineDescriptor, options: [])
		return state
	}

	class func buildMesh(
		device: MTLDevice,
		mtlVertexDescriptor: MTLVertexDescriptor
	) throws -> MTKMesh {
		/// Create and condition mesh data to feed into a pipeline using the given vertex descriptor

		let metalAllocator = MTKMeshBufferAllocator(device: device)

		let mdlMesh = MDLMesh.newBox(
			withDimensions: SIMD3<Float>(4, 4, 4),
			segments: SIMD3<UInt32>(2, 2, 2),
			geometryType: MDLGeometryType.triangles,
			inwardNormals:false,
			allocator: metalAllocator
		)
		
		let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlVertexDescriptor)
		
		guard let attributes = mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else {
			throw RendererError.badVertexDescriptor
		}
		attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
		attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate
		
		mdlMesh.vertexDescriptor = mdlVertexDescriptor
		
		return try MTKMesh(mesh:mdlMesh, device:device)
	}

	class func loadTexture(device: MTLDevice,
						   textureName: String) throws -> MTLTexture {
		/// Load texture data with optimal parameters for sampling

		let textureLoader = MTKTextureLoader(device: device)

		let textureLoaderOptions = [
			MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
			MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)
		]

		return try textureLoader.newTexture(
			name: textureName,
			scaleFactor: 1.0,
			bundle: nil,
			options: textureLoaderOptions
		)
	}

	private func updateDynamicBufferState()
	{
		/// Update the state of our uniform buffers before rendering

		uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight

		uniformBufferOffset = alignedUniformsSize * uniformBufferIndex

		uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:Uniforms.self, capacity:1)
	}

	private func updateGameState()
	{
		/// Update any game state before rendering

		uniforms[0].projectionMatrix = projectionMatrix

		let rotationAxis = SIMD3<Float>(1, 1, 0)
		let modelMatrix = matrix4x4_rotation(radians: rotation, axis: rotationAxis)
		uniforms[0].modelMatrix = modelMatrix
		let viewMatrix = matrix4x4_translation(0.0, 0.0, -16.0)
		uniforms[0].viewMatrix = viewMatrix
		uniforms[0].modelViewMatrix = simd_mul(viewMatrix, modelMatrix)
		rotation += 0.01
	}
	
	
	var _drawCallID = 0
	
	func draw(in view: MTKView)
	{
		_drawCallID += 1
		
		/// Per frame updates hare

		_ = self.inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
		
		if let commandBuffer = self.commandQueue.makeCommandBuffer(descriptor: with(.init()){
			$0.errorOptions = .encoderExecutionStatus
		}) {
			commandBuffer.label = "Command Buffer for draw #\(_drawCallID)"
			
			commandBuffer.addCompletedHandler { [weak self] _ in
				self?.inFlightSemaphore.signal()
			}
			
			self.updateDynamicBufferState()
			
			self.updateGameState()
			
			/// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
			///	  holding onto the drawable and blocking the display pipeline any longer than necessary
			let renderPassDescriptor = view.currentRenderPassDescriptor
			
			if let renderPassDescriptor = renderPassDescriptor {
				
				/// Final pass rendering code here
				if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
					renderEncoder.label = "Primary Render Encoder for draw #\(_drawCallID)"
					
					renderEncoder.pushDebugGroup("Draw Box")
					
					renderEncoder.setCullMode(.back)
					
					renderEncoder.setFrontFacing(.counterClockwise)
					
					renderEncoder.setRenderPipelineState(pipelineState)
					
					renderEncoder.setDepthStencilState(depthState)
					
					//renderEncoder.setObjectBuffer(objectBuffer, offset: 0, index: 0)
					renderEncoder.setObjectBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: 0)
					//renderEncoder.setMeshTexture(meshTexture, atIndex: 2)
					//renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
					//renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
					
					//for (index, element) in mesh.vertexDescriptor.layouts.enumerated() {
					//	guard let layout = element as? MDLVertexBufferLayout else {
					//		return
					//	}
					//	
					//	if layout.stride != 0 {
					//		let buffer = mesh.vertexBuffers[index]
					//		renderEncoder.setVertexBuffer(buffer.buffer, offset:buffer.offset, index: index)
					//	}
					//}
					
					//renderEncoder.setFragmentTexture(colorMap, index: TextureIndex.color.rawValue)
					
					//renderEncoder.setFragmentTexture(self.voxelTexture, index: TextureIndex.voxel3DColor.rawValue)
					
					//for submesh in mesh.submeshes {
					//	renderEncoder.drawIndexedPrimitives(
					//		type: submesh.primitiveType,
					//		indexCount: submesh.indexCount,
					//		indexType: submesh.indexType,
					//		indexBuffer: submesh.indexBuffer.buffer,
					//		indexBufferOffset: submesh.indexBuffer.offset
					//	)
					//}
					
					renderEncoder.useResource(self.voxelTexture, usage: .read, stages: .object)
					renderEncoder.setObjectTexture(self.voxelTexture, index: 0)
					
					// threadgroupsPerGrid: The number of threadgroups in the object (if present) or mesh shader grid.
					//let objectThreadgroupCount = MTLSize(
					//	width: self.voxelTexture.width / objectThreads.width,
					//	height: self.voxelTexture.height / objectThreads.height,
					//	depth: self.voxelTexture.depth / objectThreads.depth
					//)
					let objectThreadgroupCount = MTLSize(width: kMaxTotalThreadgroupsPerMeshGrid)
					
					// threadsPerObjectThreadgroup: The number of threads in one object shader threadgroup. Ignored if object shader is not present.
					let objectThreadCount = MTLSize(kCubesPerBlockXYZ)
					
					// threadsPerMeshThreadgroup: The number of threads in one mesh shader threadgroup.
					let meshThreadCount = MTLSize(width: kThreadsPerCube)
					
					renderEncoder.drawMeshThreadgroups(objectThreadgroupCount, threadsPerObjectThreadgroup: objectThreadCount, threadsPerMeshThreadgroup: meshThreadCount)
					
					renderEncoder.popDebugGroup()
					
					renderEncoder.endEncoding()
					
					if let drawable = view.currentDrawable {
						commandBuffer.present(drawable)
					}
				}
			}
			
			commandBuffer.addCompletedHandler{ commandBuffer in
				for log in commandBuffer.logs {
					print(log)
				}
			}
			
			commandBuffer.commit()
			
			if let error = commandBuffer.error as NSError? {
				print(error)
			}
		}
	}

	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
	{
		/// Respond to drawable size or orientation changes here
		
		let aspect = Float(size.width) / Float(size.height)
		projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(90), aspectRatio:aspect, nearZ: 1.0, farZ: 1000.0)
	}
}

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
	let unitAxis = normalize(axis)
	let ct = cosf(radians)
	let st = sinf(radians)
	let ci = 1 - ct
	let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
	return matrix_float4x4.init(columns:(
		vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
		vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
		vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
		vector_float4(                  0,                   0,                   0, 1)
	))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
	return matrix_float4x4.init(columns:(
		vector_float4(1, 0, 0, 0),
		vector_float4(0, 1, 0, 0),
		vector_float4(0, 0, 1, 0),
		vector_float4(translationX, translationY, translationZ, 1)
	))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
	let ys = 1 / tanf(fovy * 0.5)
	let xs = ys / aspectRatio
	let zs = farZ / (nearZ - farZ)
	return matrix_float4x4.init(columns:(
		vector_float4(xs,  0,          0,  0),
		vector_float4( 0, ys,          0,  0),
		vector_float4( 0,  0,         zs, -1),
		vector_float4( 0,  0, zs * nearZ,  0)
	))
}

func radians_from_degrees(_ degrees: Float) -> Float {
	return (degrees / 180) * .pi
}


extension MTLSize
{
	init(_ width: Int, _ height: Int, _ depth: Int) {
		self.init(width: width, height: height, depth: depth)
	}
	
	init(_ size: uint3) {
		self.init(Int(size.x), Int(size.y), Int(size.z))
	}
	
	init(width: uint) {
		self.init(Int(width), 1, 1)
	}
	
	static let one = MTLSize(1, 1, 1)
}
