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
	weak var metalKitView: MTKView!
	
	var commandQueue: MTLCommandQueue!
	var dynamicUniformBuffer: MTLBuffer!
	var computePipelineState: MTLComputePipelineState?
	var renderPipelineState: MTLRenderPipelineState?
	var depthState: MTLDepthStencilState!
	var voxelTexture: MTLTexture!
	
	let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
	
	var uniformBufferOffset = 0
	
	var uniformBufferIndex = 0
	
	var uniforms: UnsafeMutablePointer<Uniforms>!
	
	var projectionMatrix: matrix_float4x4 = matrix_float4x4()
	
	var rotation: Float = 0
	
	var meshBuffer: MTLBuffer!
	var DEBUG_computeOutTexture: MTLTexture!
	
	init?(metalKitView: MTKView)
	{
		func printStructInfo<StructT>(_ structT: StructT.Type) {
			print("\(StructT.self):")
			print(indent: 1, "size: \(MemoryLayout<StructT>.size)")
			print(indent: 1, "alignment: \(MemoryLayout<StructT>.alignment)")
			print(indent: 1, "stride: \(MemoryLayout<StructT>.stride)")
		}
		printStructInfo(MeshVertexData_cpu.self)
		print("kMeshVertexDataSize: \(kMeshVertexDataSize)")
		print("")
		printStructInfo(MeshPrimitiveData_cpu.self)
		print("kMeshPrimitiveDataSize: \(kMeshPrimitiveDataSize)")
		print("")
		printStructInfo(CubeMesh_cpu.self)
		print("kCubeMeshSize: \(kCubeMeshSize)")
		print("")
		print("CubeMesh_cpu.vertices align: \(MemoryLayout<CubeMesh_cpu>.offset(of: \.vertices)!)")
		print("kCubeMeshOffsetOfVertices: \(kCubeMeshOffsetOfVertices)")
		print("CubeMesh_cpu.indices align: \(MemoryLayout<CubeMesh_cpu>.offset(of: \.indices)!)")
		print("kCubeMeshOffsetOfIndicies: \(kCubeMeshOffsetOfIndicies)")
		print("CubeMesh_cpu.primitives align: \(MemoryLayout<CubeMesh_cpu>.offset(of: \.primitives)!)")
		print("kCubeMeshOffsetOfPrimitives: \(kCubeMeshOffsetOfPrimitives)")
		
		self.metalKitView = metalKitView
		self.device = metalKitView.device!
		
		super.init()
		
		self.commandQueue = self.device.makeCommandQueue()!
		
		let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
		
		self.dynamicUniformBuffer = self.device.makeBuffer(
			length: uniformBufferSize,
			options: [ .cpuCacheModeWriteCombined, .storageModeShared, ]
		)!
		
		self.dynamicUniformBuffer.label = "Uniform Buffer"
		
		self.uniforms = UnsafeMutableRawPointer(self.dynamicUniformBuffer.contents()).bindMemory(to: Uniforms.self, capacity:1)
		
		metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
		metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
		metalKitView.sampleCount = 1
		
		let mtlVertexDescriptor = buildMetalVertexDescriptor()
		
		do {
			computePipelineState = try buildComputePipelineWithDevice()
		} catch {
			print("Unable to compile compute pipeline state. Error info: \(error)")
			return nil
		}
		
		do {
			renderPipelineState = try buildRenderPipelineWithDevice()
		} catch {
			print("Unable to compile render pipeline state. Error info: \(error)")
			return nil
		}
		
		let depthStateDescriptor = MTLDepthStencilDescriptor()
		depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
		depthStateDescriptor.isDepthWriteEnabled = true
		self.depthState = device.makeDepthStencilState(descriptor:depthStateDescriptor)!
		
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
		
		do {
			self.meshBuffer = try buildComputeMeshBuffer(mtlVertexDescriptor: mtlVertexDescriptor)
			
			let size = MTLSize(kCubesPerBlockXYZ)
			self.DEBUG_computeOutTexture = device.makeTexture(descriptor: with(.textureBufferDescriptor(
				with: .rgba32Uint,
				width: size.width,
				usage: .shaderWrite
			)){
				$0.textureType = .type3D
				$0.width = size.width
				$0.height = size.height
				$0.depth = size.depth
				
				$0.storageMode = .private
			})!
		} catch {
			print("Unable to build MetalKit Mesh. Error info: \(error)")
			return nil
		}
	}

	func buildMetalVertexDescriptor() -> MTLVertexDescriptor
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

	func buildComputePipelineWithDevice() throws -> MTLComputePipelineState
	{
		let (state, _) = try self.device.makeComputePipelineState(
			descriptor: with(.init()){
				$0.label = "Mesh-Generation Compute Pipeline"
				
				let library = self.device.makeDefaultLibrary()!
				
				let function = library.makeFunction(name: "meshGenerationKernel")
				$0.computeFunction = function
				
				$0.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
				$0.maxTotalThreadsPerThreadgroup = Int(kCubesPerBlock);
				//$0.maxCallStackDepth = 1
				//$0.supportIndirectCommandBuffers = true
				
				//$0.stageInputDescriptor = with(.init()){
				//	$0.attributes[0] = 
				//	$0.layouts[0] = 
				//}
				
				//$0.buffers[0].mutability = .mutable
			},
			options: []
		)
		with(state){
			print("compute pipeline state:")
			print(indent: 1, "maxTotalThreadsPerThreadgroup: \($0.maxTotalThreadsPerThreadgroup)")
			print(indent: 1, "threadExecutionWidth: \($0.threadExecutionWidth)")
			print(indent: 1, "staticThreadgroupMemoryLength: \($0.staticThreadgroupMemoryLength)")
			print(indent: 1, "supportIndirectCommandBuffers: \($0.supportIndirectCommandBuffers)")
		}
		return state
	}

	func buildRenderPipelineWithDevice() throws -> MTLRenderPipelineState
	{
		let (state, _) = try self.device.makeRenderPipelineState(
			descriptor: with(.init()) {
				$0.label = "RenderPipeline"
				$0.rasterSampleCount = metalKitView.sampleCount
				
				let library = self.device.makeDefaultLibrary()!
				
				let vertexFunction = library.makeFunction(name: "vertexShader")
				$0.vertexFunction = vertexFunction
				let fragmentFunction = library.makeFunction(name: "fragmentShader")
				$0.fragmentFunction = fragmentFunction
				
				$0.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
				$0.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
				$0.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
			},
			options: []
		)
		with(state){
			print("render pipeline state:")
			print(indent: 1, "maxTotalThreadsPerThreadgroup: \($0.maxTotalThreadsPerThreadgroup)")
			print(indent: 1, "threadgroupSizeMatchesTileSize: \($0.threadgroupSizeMatchesTileSize)")
			print(indent: 1, "supportIndirectCommandBuffers: \($0.supportIndirectCommandBuffers)")
			print(indent: 1, "maxTotalThreadgroupsPerMeshGrid: \($0.maxTotalThreadgroupsPerMeshGrid)")
			print(indent: 1, "maxTotalThreadsPerMeshThreadgroup: \($0.maxTotalThreadsPerMeshThreadgroup)")
			print(indent: 1, "maxTotalThreadsPerObjectThreadgroup: \($0.maxTotalThreadsPerObjectThreadgroup)")
			print(indent: 1, "meshThreadExecutionWidth: \($0.meshThreadExecutionWidth)")
			print(indent: 1, "objectThreadExecutionWidth: \($0.objectThreadExecutionWidth)")
		}
		return state
	}

	func buildComputeMeshBuffer(mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLBuffer {
		let voxelSize = self.voxelTexture.size
		let voxelCount = voxelSize.width * voxelSize.height * voxelSize.depth
		let buffer = device.makeBuffer(
			length: kCubeMeshSize * voxelCount,
			options: [ .storageModePrivate ]
		)!
		buffer.label = "Generated Mesh Buffer"
		return buffer
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
			
			if let renderPassDescriptor = renderPassDescriptor
			{
				if let computePipelineState, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
					computeEncoder.label = "Primary Compute Encoder for draw #\(_drawCallID)"
					
					computeEncoder.setComputePipelineState(computePipelineState)
					
					computeEncoder.setBuffer(dynamicUniformBuffer, offset: uniformBufferOffset, index: 0)
					
					//computeEncoder.useResource(self.voxelTexture, usage: .read)
					computeEncoder.setTexture(self.voxelTexture, index: 0)
					
					//computeEncoder.useResource(self.meshBuffer, usage: .write)
					computeEncoder.setBuffer(self.meshBuffer, offset: 0, index: 1)
					
					computeEncoder.setTexture(self.DEBUG_computeOutTexture, index: 1)
					
					// threadgroupsPerGrid: The number of threadgroups in the object (if present) or mesh shader grid.
					//let objectThreadgroupCount = MTLSize(
					//	width: self.voxelTexture.width / objectThreads.width,
					//	height: self.voxelTexture.height / objectThreads.height,
					//	depth: self.voxelTexture.depth / objectThreads.depth
					//)
					//let objectThreadgroupCount = MTLSize(width: kMaxTotalThreadgroupsPerMeshGrid)
					
					// threadsPerObjectThreadgroup: The number of threads in one object shader threadgroup. Ignored if object shader is not present.
					//let objectThreadCount = 
					
					// threadsPerMeshThreadgroup: The number of threads in one mesh shader threadgroup.
					//let meshThreadCount = MTLSize(width: kThreadsPerCube)
					
					//renderEncoder.drawMeshThreadgroups(objectThreadgroupCount, threadsPerObjectThreadgroup: objectThreadCount, threadsPerMeshThreadgroup: meshThreadCount)
					computeEncoder.dispatchThreads(self.voxelTexture.size, threadsPerThreadgroup: MTLSize(kCubesPerBlockXYZ))
					
					computeEncoder.endEncoding()
				}
				
				/// Final pass rendering code here
				if let renderPipelineState, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
					renderEncoder.label = "Primary Render Encoder for draw #\(_drawCallID)"
					
					renderEncoder.pushDebugGroup("Draw Box")
					
					renderEncoder.setCullMode(.back)
					
					renderEncoder.setFrontFacing(.counterClockwise)
					
					renderEncoder.setRenderPipelineState(renderPipelineState)
					
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


extension MTLTexture
{
	var size: MTLSize { MTLSize(width: self.width, height: self.height, depth: self.depth) }
}



func print(
	indent indentSize: Int,
	_ items: Any...,
	separator: String = " ",
	terminator: String = "\n"
) {
	let indent = repeatElement("\t", count: indentSize).joined()
	let string = items.map{ "\($0)" }.joined(separator: separator)
	Swift.print(indent + string, separator: "", terminator: terminator)
}
