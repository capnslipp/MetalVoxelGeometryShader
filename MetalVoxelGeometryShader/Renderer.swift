//
//	Renderer.swift
//	MetalVoxelGeometryShader
//
//	Created by Cap'n Slipp on 2/28/23.
//

// Our platform independent renderer class

import Metal
import MetalKit
import MetalPerformanceShaders
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
	var meshVertexDescriptor: MTLVertexDescriptor!
	var computePipelineState: MTLComputePipelineState?
	var renderPipelineState: MTLRenderPipelineState?
	var depthState: MTLDepthStencilState!
	var voxelTexture: MTLTexture!
	var voxelCount: Int!
	var voxelBuffer: MTLBuffer!
	
	let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
	
	var uniformBufferOffset = 0
	
	var uniformBufferIndex = 0
	
	var uniforms: UnsafeMutablePointer<Uniforms>!
	
	var projectionMatrix: matrix_float4x4 = matrix_float4x4()
	
	var rotation: Float = 0
	
	var meshVerticesCount: Int = 0
	var meshVerticesBuffer: MTLBuffer!
	var meshIndicesCount: Int = 0
	var meshIndicesBuffer: MTLBuffer!
	
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
		//printStructInfo(CubeMesh_cpu.self)
		//print("kCubeMeshSize: \(kCubeMeshSize)")
		//print("")
		//print("CubeMesh_cpu.vertices align: \(MemoryLayout<CubeMesh_cpu>.offset(of: \.vertices)!)")
		//print("kCubeMeshOffsetOfVertices: \(kCubeMeshOffsetOfVertices)")
		//print("CubeMesh_cpu.indices align: \(MemoryLayout<CubeMesh_cpu>.offset(of: \.indices)!)")
		//print("kCubeMeshOffsetOfIndicies: \(kCubeMeshOffsetOfIndicies)")
		//print("CubeMesh_cpu.primitives align: \(MemoryLayout<CubeMesh_cpu>.offset(of: \.primitives)!)")
		//print("kCubeMeshOffsetOfPrimitives: \(kCubeMeshOffsetOfPrimitives)")
		
		guard let device = metalKitView.device else { return nil }
		self.device = device
		
		self.metalKitView = metalKitView
		
		print("MPSSupportsMTLDevice: \(MPSSupportsMTLDevice(device))")
		
		super.init()
		
		self.commandQueue = self.device.makeCommandQueue()!
		
		let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
		
		self.dynamicUniformBuffer = self.device.makeBuffer(
			length: uniformBufferSize,
			options: [ .cpuCacheModeWriteCombined, .storageModeShared, ]
		)!
		
		self.dynamicUniformBuffer.label = "Uniform Buffer"
		
		self.uniforms = UnsafeMutableRawPointer(self.dynamicUniformBuffer.contents()).bindMemory(to: Uniforms.self, capacity:1)
		
		with(self.metalKitView){
			$0.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
			$0.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
			
			if device.supportsTextureSampleCount(4) {
				$0.sampleCount = 4
			}
		}
		
		do {
			let path = Bundle.main.path(forResource: "master.Brownstone.NSide", ofType: "vox")!
			let asset = MDLVoxelAsset(url: URL(fileURLWithPath: path), options: [
				kMDLVoxelAssetOptionCalculateShellLevels: true,
				kMDLVoxelAssetOptionSkipNonZeroShellMesh: true,
				kMDLVoxelAssetOptionConvertZUpToYUp: false
			])
			let assetModel = asset.models.first!
			print("assetModel.voxelCount: \(assetModel.voxelCount)")
			
			self.voxelTexture = device.makeVoxel3DTextureRGBA(fromAsset: asset)!
			
			self.voxelCount = Int(assetModel.voxelCount)
			self.voxelBuffer = device.makeBuffer(
				bytes: (assetModel.voxelArray.voxelIndices()! as NSData).bytes,
				length: Int(assetModel.voxelCount) * MemoryLayout<MDLVoxelIndex>.size,
				options: [ .cpuCacheModeWriteCombined, .storageModeShared ]
			)
		} catch {
			print("Unable to generate texture. Error info: \(error)")
			return nil
		}
		
		do {
			try buildComputeMeshBuffers()
			
			let size = MTLSize(width: min(self.voxelCount, 16384))
			self.DEBUG_computeOutTexture = device.makeTexture(descriptor: with(.textureBufferDescriptor(
				with: .rgba32Uint,
				width: size.width,
				usage: .shaderWrite
			)){
				$0.textureType = .type1DArray
				$0.width = size.width
				$0.height = size.height
				$0.depth = size.depth
				$0.arrayLength = Int(kPrimitiveCountPerCube)
				
				$0.storageMode = .private
			})!
		} catch {
			print("Unable to build MetalKit Mesh. Error info: \(error)")
			return nil
		}
		
		self.depthState = device.makeDepthStencilState(descriptor: with(.init()){
			$0.depthCompareFunction = MTLCompareFunction.less
			$0.isDepthWriteEnabled = true
		})!
		
		do {
			computePipelineState = try buildComputePipelineWithDevice()
		} catch {
			print("Unable to compile compute pipeline state. Error info: \(error)")
			return nil
		}
		
		do {
			renderPipelineState = try buildRenderPipelineWithDevice(rasterSampleCount: self.metalKitView.sampleCount)
		} catch {
			print("Unable to compile render pipeline state. Error info: \(error)")
			return nil
		}
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

	func buildRenderPipelineWithDevice(rasterSampleCount: Int = 1) throws -> MTLRenderPipelineState
	{
		let (state, _) = try self.device.makeRenderPipelineState(
			descriptor: with(.init()) {
				$0.label = "RenderPipeline"
				$0.rasterSampleCount = metalKitView.sampleCount
				
				let library = self.device.makeDefaultLibrary()!
				
				$0.vertexDescriptor = self.meshVertexDescriptor
				$0.inputPrimitiveTopology = .triangle
				
				let vertexFunction = library.makeFunction(name: "vertexShader")
				$0.vertexFunction = vertexFunction
				let fragmentFunction = library.makeFunction(name: "fragmentShader")
				$0.fragmentFunction = fragmentFunction
				
				$0.rasterSampleCount = rasterSampleCount
				
				with($0.colorAttachments[0]){
					$0.pixelFormat = metalKitView.colorPixelFormat
					$0.isBlendingEnabled = true
					
					$0.sourceRGBBlendFactor = .sourceAlpha
					$0.destinationRGBBlendFactor = .oneMinusSourceAlpha
					$0.sourceAlphaBlendFactor = .one
					$0.destinationAlphaBlendFactor = .zero
				}
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

	func buildComputeMeshBuffers() throws {
		//let voxelSize = self.voxelTexture.size
		//let voxelCount = voxelSize.width * voxelSize.height * voxelSize.depth
		
		self.meshVerticesCount = self.voxelCount * Int(kVertexCountPerCube)
		self.meshVerticesBuffer = with(device.makeBuffer(
			length: self.meshVerticesCount * kMeshVertexDataSize,
			options: [ .storageModePrivate ]
		)!){
			$0.label = "Generated Mesh Vertices Buffer"
		}
		
		self.meshIndicesCount = self.voxelCount * Int(kIndexCountPerCube)
		self.meshIndicesBuffer = with(device.makeBuffer(
			length: meshIndicesCount * MemoryLayout<UInt32>.size,
			options: [ .storageModePrivate ]
		)!){
			$0.label = "Generated Mesh Indices Buffer"
		}
		
		self.meshVertexDescriptor = with(MTLVertexDescriptor()){
			$0.attributes[0].set(format: .uchar3, offset: kMeshVertexDataOffsetOfPosition, bufferIndex: 0)
			$0.attributes[1].set(format: .char3, offset: kMeshVertexDataOffsetOfPrimitive + kMeshPrimitiveDataOffsetOfNormal, bufferIndex: 0)
			$0.attributes[2].set(format: .uchar3, offset: kMeshVertexDataOffsetOfPrimitive + kMeshPrimitiveDataOffsetOfVoxelCoord, bufferIndex: 0)
			
			$0.layouts[0].set(stepFunction: .perVertex, stepRate: 1, stride: MemoryLayout<MeshVertexData_cpu>.stride)
		}
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

		uniforms[0].projectionMatrix = self.projectionMatrix

		let rotationAxis = SIMD3<Float>(1, 1, 0)
		let modelMatrix = matrix4x4_rotation(radians: rotation, axis: rotationAxis)
		uniforms[0].modelMatrix = modelMatrix
		let viewMatrix = matrix4x4_translation(0.0, 0.0, -16.0)
		uniforms[0].viewMatrix = viewMatrix
		uniforms[0].modelViewMatrix = simd_mul(viewMatrix, modelMatrix)
		rotation += 0.01
		
		uniforms[0].voxelCount = UInt32(self.voxelCount)
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
				let computedGeometryFence = device.makeFence()!
				
				if let computePipelineState, let computeEncoder = commandBuffer.makeComputeCommandEncoder(descriptor: with(.init()){
					$0.dispatchType = .concurrent
					//$0.sampleBufferAttachments[0].
				}) {
					computeEncoder.label = "Primary Compute Encoder for draw #\(_drawCallID)"
					
					computeEncoder.setComputePipelineState(computePipelineState)
					
					computeEncoder.setBuffer(self.dynamicUniformBuffer, offset: self.uniformBufferOffset, index: 0)
					
					//computeEncoder.useResource(self.voxelTexture, usage: .read)
					//computeEncoder.setTexture(self.voxelTexture, index: 0)
					computeEncoder.setBuffer(self.voxelBuffer, offset: 0, index: 3)
					//computeEncoder.setTexture(self.DEBUG_computeOutTexture, index: 1)
					
					//computeEncoder.useResource(self.meshVerticesBuffer, usage: .write)
					computeEncoder.setBuffer(self.meshVerticesBuffer, offset: 0, index: 1)
					computeEncoder.setBuffer(self.meshIndicesBuffer, offset: 0, index: 2)
					
					
					let threadsPerThreadgroup = MTLSize(width: self.computePipelineState!.threadExecutionWidth)
					
					// threadgroupsPerGrid: The number of threadgroups in the object (if present) or mesh shader grid.
					//let threadgroupsPerGrid = self.voxelTexture.size.dividing(by: threadsPerThreadgroup, round: .awayFromZero)
					let threadgroupsPerGrid = MTLSize(width: self.voxelCount).dividing(by: threadsPerThreadgroup, round: .awayFromZero)
					//let objectThreadgroupCount = MTLSize(width: kMaxTotalThreadgroupsPerMeshGrid)
					
					// threadsPerObjectThreadgroup: The number of threads in one object shader threadgroup. Ignored if object shader is not present.
					//let objectThreadCount = 
					
					// threadsPerMeshThreadgroup: The number of threads in one mesh shader threadgroup.
					//let meshThreadCount = MTLSize(width: kThreadsPerCube)
					
					//renderEncoder.drawMeshThreadgroups(objectThreadgroupCount, threadsPerObjectThreadgroup: objectThreadCount, threadsPerMeshThreadgroup: meshThreadCount)
					computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
					
					computeEncoder.updateFence(computedGeometryFence)
					
					computeEncoder.endEncoding()
				}
				
				/// Final pass rendering code here
				if let renderPipelineState, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
					renderEncoder.label = "Primary Render Encoder for draw #\(_drawCallID)"
					
					renderEncoder.pushDebugGroup("Draw Box")
					
					#if os(macOS)
						renderEncoder.memoryBarrier(resources: [ self.meshVerticesBuffer, self.meshIndicesBuffer ], after: [], before: .vertex)
					#endif
					renderEncoder.waitForFence(computedGeometryFence, before: .vertex)
					
					renderEncoder.setCullMode(.back)
					
					renderEncoder.setFrontFacing(.counterClockwise)
					
					renderEncoder.setRenderPipelineState(renderPipelineState)
					
					renderEncoder.setDepthStencilState(self.depthState)
					
					//renderEncoder.setObjectBuffer(objectBuffer, offset: 0, index: 0)
					renderEncoder.setVertexBuffer(self.meshVerticesBuffer, offset: 0, index: 0)
					renderEncoder.setVertexBuffer(self.dynamicUniformBuffer, offset: self.uniformBufferOffset, index: 1)
					renderEncoder.setVertexTexture(self.voxelTexture, index: 0)
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
					
					renderEncoder.drawIndexedPrimitives(
						type: .triangle,
						indexCount: self.meshIndicesCount,
						indexType: .uint32,
						indexBuffer: self.meshIndicesBuffer, indexBufferOffset: 0
					)
					
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


extension MTLVertexAttributeDescriptor
{
	func set(format: MTLVertexFormat, offset: Int, bufferIndex: Int) {
		self.format = format
		self.offset = offset
		self.bufferIndex = bufferIndex
	}
}

extension MTLVertexBufferLayoutDescriptor
{
	func set(stepFunction: MTLVertexStepFunction, stepRate: Int, stride: Int) {
		self.stepFunction = stepFunction
		self.stepRate = stepRate
		self.stride = stride
	}
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
