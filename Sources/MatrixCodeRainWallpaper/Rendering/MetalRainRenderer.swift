import AppKit
import Metal
import MetalKit
import QuartzCore
import simd

final class MetalRainRenderer: NSObject, MTKViewDelegate {
    private struct RainColumn {
        var centerX: Float
        var headY: Float
        var speed: Float
        var length: Int
        var fontSize: Float
        var cellHeight: Float
        var inverseCellHeight: Float
        var tailDistance: Float
        var glyphSize: SIMD2<Float>
        var depthBrightness: Float
        var rowCount: Int
        var glyphOffset: Int
    }

    private struct ClockGlyph {
        var glyphIndex: Int
        var whiteness: Float
        var nextMutationTime: TimeInterval
    }

    private struct ClockCluster {
        var isLit: Bool
        var glyphs: [ClockGlyph]
    }

    private struct GlyphInstance {
        var position: SIMD2<Float>
        var size: SIMD2<Float>
        var uvOrigin: SIMD2<Float>
        var uvSize: SIMD2<Float>
        var color: SIMD4<Float>
    }

    private struct RainColumnStaticState {
        var metrics0: SIMD4<Float>
        var metrics1: SIMD4<Float>
        var glyphInfo: SIMD4<UInt32>
    }

    private struct GlyphUV {
        var origin: SIMD2<Float>
        var size: SIMD2<Float>
    }

    private struct ClockLayout {
        var origin: SIMD2<Float>
        var size: SIMD2<Float>
        var cellSize: Float
    }

    private struct Uniforms {
        var viewportSize: SIMD2<Float>
        var rainVisibleSlotsPerColumn: UInt32
        var padding: UInt32
    }

    private struct PseudoRandomGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func nextUInt64() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }

        mutating func nextFloat() -> Float {
            Float(Double(nextUInt64() >> 11) * (1.0 / 9_007_199_254_740_992.0))
        }

        mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
            range.lowerBound + nextFloat() * (range.upperBound - range.lowerBound)
        }

        mutating func nextInt(in range: ClosedRange<Int>) -> Int {
            let count = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int(nextUInt64() % count)
        }

        mutating func nextIndex(count: Int) -> Int {
            guard count > 1 else {
                return 0
            }

            return Int(nextUInt64() % UInt64(count))
        }

        mutating func chance(_ probability: Float) -> Bool {
            nextFloat() < probability
        }

        mutating func skipCount(untilChance probability: Float) -> Int {
            guard probability > 0 else {
                return Int.max
            }

            guard probability < 1 else {
                return 0
            }

            let sample = max(Float.leastNonzeroMagnitude, nextFloat())
            return Int(floor(log(sample) / log1p(-probability)))
        }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct GlyphInstance {
        float2 position;
        float2 size;
        float2 uvOrigin;
        float2 uvSize;
        float4 color;
    };

    struct RainColumnStaticState {
        float4 metrics0;
        float4 metrics1;
        uint4 glyphInfo;
    };

    struct GlyphUV {
        float2 origin;
        float2 size;
    };

    struct Uniforms {
        float2 viewportSize;
        uint rainVisibleSlotsPerColumn;
        uint padding;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
    };

    vertex VertexOut vertex_main(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        constant GlyphInstance *instances [[buffer(0)]],
        constant Uniforms &uniforms [[buffer(1)]]
    ) {
        float2 corners[6] = {
            float2(-0.5, -0.5),
            float2(0.5, -0.5),
            float2(-0.5, 0.5),
            float2(0.5, -0.5),
            float2(0.5, 0.5),
            float2(-0.5, 0.5)
        };

        float2 texcoords[6] = {
            float2(0.0, 0.0),
            float2(1.0, 0.0),
            float2(0.0, 1.0),
            float2(1.0, 0.0),
            float2(1.0, 1.0),
            float2(0.0, 1.0)
        };

        GlyphInstance instance = instances[instanceID];
        float2 pixel = instance.position + corners[vertexID] * instance.size;
        float2 clip = float2(
            pixel.x / uniforms.viewportSize.x * 2.0 - 1.0,
            1.0 - pixel.y / uniforms.viewportSize.y * 2.0
        );

        VertexOut out;
        out.position = float4(clip, 0.0, 1.0);
        out.uv = instance.uvOrigin + texcoords[vertexID] * instance.uvSize;
        out.color = instance.color;
        return out;
    }

    static float4 rain_color(float depthBrightness, float ageInCells, float length) {
        float progress = min(1.0, max(0.0, ageInCells) / max(1.0, length));

        if (ageInCells < 1.0) {
            return float4(
                0.45 + 0.38 * depthBrightness,
                0.72 + 0.28 * depthBrightness,
                0.45 + 0.30 * depthBrightness,
                0.62 + 0.34 * depthBrightness
            );
        }

        float alpha = max(0.025, pow(1.0 - progress, 1.7) * (0.42 + 0.58 * depthBrightness));
        return float4(
            0.0,
            0.34 + 0.48 * depthBrightness,
            0.05 + 0.14 * depthBrightness,
            alpha
        );
    }

    vertex VertexOut rain_vertex_main(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        constant RainColumnStaticState *columns [[buffer(0)]],
        constant Uniforms &uniforms [[buffer(1)]],
        constant uint *glyphIndices [[buffer(2)]],
        constant GlyphUV *glyphUVs [[buffer(3)]],
        constant float *headYs [[buffer(4)]]
    ) {
        float2 corners[6] = {
            float2(-0.5, -0.5),
            float2(0.5, -0.5),
            float2(-0.5, 0.5),
            float2(0.5, -0.5),
            float2(0.5, 0.5),
            float2(-0.5, 0.5)
        };

        float2 texcoords[6] = {
            float2(0.0, 0.0),
            float2(1.0, 0.0),
            float2(0.0, 1.0),
            float2(1.0, 0.0),
            float2(1.0, 1.0),
            float2(0.0, 1.0)
        };

        uint slotsPerColumn = max(1u, uniforms.rainVisibleSlotsPerColumn);
        uint columnIndex = instanceID / slotsPerColumn;
        uint slot = instanceID - columnIndex * slotsPerColumn;
        RainColumnStaticState column = columns[columnIndex];

        float centerX = column.metrics0.x;
        float cellHeight = column.metrics0.y;
        float inverseCellHeight = column.metrics0.z;
        float length = column.metrics0.w;
        float2 glyphSize = column.metrics1.xy;
        float depthBrightness = column.metrics1.z;
        float headY = headYs[columnIndex];
        uint rowCount = column.glyphInfo.x;
        uint glyphOffset = column.glyphInfo.y;
        uint safeRowCount = max(1u, rowCount);
        uint firstVisibleRow = uint(max(0.0, ceil((headY - length * cellHeight) * inverseCellHeight)));
        uint row = firstVisibleRow + slot;
        uint glyphRow = min(row, safeRowCount - 1u);
        uint glyphIndex = glyphIndices[glyphOffset + glyphRow];
        GlyphUV glyphUV = glyphUVs[glyphIndex];

        float y = float(row) * cellHeight;
        float ageInCells = (headY - y) * inverseCellHeight;
        bool visible = row < rowCount && ageInCells >= 0.0 && ageInCells <= length;
        float visibleMask = visible ? 1.0 : 0.0;
        float2 position = float2(centerX, y + cellHeight * 0.5);
        float2 pixel = position + corners[vertexID] * glyphSize * visibleMask;
        float2 clip = float2(
            pixel.x / uniforms.viewportSize.x * 2.0 - 1.0,
            1.0 - pixel.y / uniforms.viewportSize.y * 2.0
        );

        VertexOut out;
        out.position = float4(clip, 0.0, 1.0);
        out.uv = glyphUV.origin + texcoords[vertexID] * glyphUV.size;
        out.color = rain_color(depthBrightness, ageInCells, length) * visibleMask;
        return out;
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        texture2d<float> atlas [[texture(0)]]
    ) {
        constexpr sampler glyphSampler(address::clamp_to_edge, filter::linear);
        float4 glyph = atlas.sample(glyphSampler, in.uv);
        float glyphAlpha = max(glyph.a, max(glyph.r, glyph.g));
        return float4(in.color.rgb, in.color.a * glyphAlpha);
    }

    fragment float4 texture_fragment_main(
        VertexOut in [[stage_in]],
        texture2d<float> sourceTexture [[texture(0)]]
    ) {
        constexpr sampler textureSampler(address::clamp_to_edge, filter::nearest);
        return sourceTexture.sample(textureSampler, in.uv) * in.color;
    }
    """

    private static let clockPatterns: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"],
        "3": ["111", "001", "111", "001", "111"],
        "4": ["101", "101", "111", "001", "001"],
        "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"],
        "7": ["111", "001", "010", "010", "010"],
        "8": ["111", "101", "111", "101", "111"],
        "9": ["111", "101", "111", "001", "111"],
        ":": ["0", "1", "0", "1", "0"]
    ]

    private let glyphSymbols = Array(
        "アイウエオカキクケコサシスセソタチツテトナニヌネノ" +
        "ハヒフヘホマミムメモヤユヨラリルレロワヲン" +
        "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ" +
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ@$%#*+=-"
    ).map(String.init)

    private let minFontSize: Float = 11
    private let maxFontSize: Float = 18
    private let minSpeed: Float = 100
    private let maxSpeed: Float = 260
    private let minRainLength = 10
    private let maxRainLength = 32
    private let columnSpacing: Float = 18
    private let rainSpeedMultiplier: Float = 1
    private let clockRows = 5
    private let digitColumns = 3
    private let colonColumns = 1
    private let characterSpacing = 1
    private let clockWidthFraction: Float = 0.62
    private let clockSideCount = 3
    private let clockGlyphWidthScale: Float = 1.14
    private let clockGlyphHeightScale: Float = 1.24
    private let clockGlowScale: Float = 1.08
    private let rainGlyphMutationPeriod: TimeInterval = 0.5
    private let rainGlyphMutationChance: Float = 0.12
    private let clockGlyphMinimumMutationInterval: TimeInterval = 2.0
    private let clockGlyphMutationBatchInterval: TimeInterval = 0.25
    private let clockGlyphMutationSpread: Float = 6.0
    private let clockTextCheckSafetyMargin: TimeInterval = 0.05
    private let atlasCellSize = 64
    private let atlasColumns = 16

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let rainPipelineState: MTLRenderPipelineState
    private let pipelineState: MTLRenderPipelineState
    private let texturePipelineState: MTLRenderPipelineState
    private let atlasTexture: MTLTexture
    private let glyphUVs: [GlyphUV]
    private let glyphUVBuffer: MTLBuffer
    private let rainInstanceBufferCount = 3
    private var rainColumnStaticBuffers: [MTLBuffer?] = [nil, nil, nil]
    private var rainColumnStaticBufferVersions = [UInt64](repeating: 0, count: 3)
    private var rainHeadYBuffers: [MTLBuffer?] = [nil, nil, nil]
    private var rainGlyphIndexBuffers: [MTLBuffer?] = [nil, nil, nil]
    private var rainGlyphIndexBufferVersions = [UInt64](repeating: 0, count: 3)
    private var rainInstanceCapacity = 1
    private var rainGlyphRowsPerColumn = 1
    private var rainColumnStaticVersion: UInt64 = 1
    private var rainGlyphIndexVersion: UInt64 = 1
    private var rainGlyphIndices: [UInt32] = []
    private var clockInstanceBuffer: MTLBuffer?
    private var clockTexture: MTLTexture?
    private var clockTextureQuad: GlyphInstance?
    private var clockTextureScale: Float = 0
    private var random = PseudoRandomGenerator(seed: MetalRainRenderer.initialPseudoRandomSeed())
    private var columns: [RainColumn] = []
    private var clockInstances: [GlyphInstance] = []
    private var clockClusters: [ClockCluster] = []
    private var viewportSize = SIMD2<Float>(1, 1)
    private var frameIndex = 0
    private var lastFrameTime = CACurrentMediaTime()
    private var cachedClockText = ""
    private var cachedClockMinute = -1
    private var clockTotalColumns = 0
    private var clockInstancesDirty = true
    private var clockInstanceCount = 0
    private var nextRainGlyphMutationTime: TimeInterval = 0
    private var nextClockGlyphMutationTime: TimeInterval = .greatestFiniteMagnitude
    private var nextClockGlyphMutationBatchTime: TimeInterval = 0
    private var nextClockTextCheckTime: TimeInterval = 0

    private var rainVisibleSlotsPerColumn: Int {
        maxRainLength + 2
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Unable to create Metal command queue")
        }

        self.commandQueue = commandQueue

        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let rainDescriptor = MTLRenderPipelineDescriptor()
            rainDescriptor.vertexFunction = library.makeFunction(name: "rain_vertex_main")
            rainDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
            rainDescriptor.colorAttachments[0].pixelFormat = pixelFormat
            rainDescriptor.colorAttachments[0].isBlendingEnabled = true
            rainDescriptor.colorAttachments[0].rgbBlendOperation = .add
            rainDescriptor.colorAttachments[0].alphaBlendOperation = .add
            rainDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            rainDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            rainDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            rainDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            rainPipelineState = try device.makeRenderPipelineState(descriptor: rainDescriptor)

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

            let textureDescriptor = MTLRenderPipelineDescriptor()
            textureDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            textureDescriptor.fragmentFunction = library.makeFunction(name: "texture_fragment_main")
            textureDescriptor.colorAttachments[0].pixelFormat = pixelFormat
            textureDescriptor.colorAttachments[0].isBlendingEnabled = true
            textureDescriptor.colorAttachments[0].rgbBlendOperation = .add
            textureDescriptor.colorAttachments[0].alphaBlendOperation = .add
            textureDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            textureDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            textureDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            textureDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            texturePipelineState = try device.makeRenderPipelineState(descriptor: textureDescriptor)
        } catch {
            fatalError("Unable to build Metal pipeline: \(error)")
        }

        atlasTexture = Self.makeGlyphAtlas(device: device, symbols: glyphSymbols, cellSize: atlasCellSize, columns: atlasColumns)
        let generatedGlyphUVs = Self.makeGlyphUVs(symbolCount: glyphSymbols.count, cellSize: atlasCellSize, columns: atlasColumns)
        glyphUVs = generatedGlyphUVs

        guard let glyphUVBuffer = generatedGlyphUVs.withUnsafeBytes({ bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }) else {
            fatalError("Unable to create glyph UV buffer")
        }
        self.glyphUVBuffer = glyphUVBuffer

        super.init()

        let now = CACurrentMediaTime()
        nextRainGlyphMutationTime = now + rainGlyphMutationPeriod
        updateClockTextIfNeeded(force: true, now: now)
    }

    func resetFrameClock() {
        lastFrameTime = CACurrentMediaTime()
    }

    func resize(to size: CGSize) {
        let newSize = SIMD2<Float>(max(1, Float(size.width)), max(1, Float(size.height)))
        guard abs(newSize.x - viewportSize.x) > 0.5 || abs(newSize.y - viewportSize.y) > 0.5 else {
            return
        }

        viewportSize = newSize
        rebuildColumns()
        clockInstancesDirty = true
        clockTexture = nil
        clockTextureQuad = nil
        clockTextureScale = 0
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        resize(to: view.bounds.size)
    }

    func draw(in view: MTKView) {
        resize(to: view.bounds.size)

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              viewportSize.x > 0,
              viewportSize.y > 0 else {
            return
        }

        let now = CACurrentMediaTime()
        let delta = Float(min(0.1, max(0, now - lastFrameTime)))
        lastFrameTime = now

        updateState(delta: delta, now: now)

        let rainBufferIndex = frameIndex % rainInstanceBufferCount
        let rainColumnStaticBuffer = prepareRainColumnStaticBuffer(at: rainBufferIndex)
        let rainHeadYBuffer = prepareRainHeadYBuffer(at: rainBufferIndex)
        let rainGlyphIndexBuffer = prepareRainGlyphIndexBuffer(at: rainBufferIndex)
        let rainInstanceCount = columns.isEmpty ? 0 : rainInstanceCapacity

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let backingScale = max(1, Float(view.window?.backingScaleFactor ?? view.layer?.contentsScale ?? 1))
        renderClockTextureIfNeeded(commandBuffer: commandBuffer, backingScale: backingScale)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        var uniforms = Uniforms(
            viewportSize: viewportSize,
            rainVisibleSlotsPerColumn: UInt32(max(1, rainVisibleSlotsPerColumn)),
            padding: 0
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(atlasTexture, index: 0)

        if let rainColumnStaticBuffer, let rainHeadYBuffer, let rainGlyphIndexBuffer, rainInstanceCount > 0 {
            encoder.setRenderPipelineState(rainPipelineState)
            encoder.setVertexBuffer(rainColumnStaticBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(rainGlyphIndexBuffer, offset: 0, index: 2)
            encoder.setVertexBuffer(glyphUVBuffer, offset: 0, index: 3)
            encoder.setVertexBuffer(rainHeadYBuffer, offset: 0, index: 4)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: rainInstanceCount)
        }

        if let clockTexture, var clockTextureQuad {
            encoder.setRenderPipelineState(texturePipelineState)
            encoder.setVertexBytes(&clockTextureQuad, length: MemoryLayout<GlyphInstance>.stride, index: 0)
            encoder.setFragmentTexture(clockTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)
        }

        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateState(delta: Float, now: TimeInterval) {
        frameIndex &+= 1

        for index in columns.indices {
            columns[index].headY += columns[index].speed * rainSpeedMultiplier * delta

            let tailY = columns[index].headY - columns[index].tailDistance
            if tailY > viewportSize.y + columns[index].cellHeight {
                recycleColumn(at: index)
            }
        }

        if now >= nextRainGlyphMutationTime {
            mutateRainGlyphs()
            nextRainGlyphMutationTime = now + rainGlyphMutationPeriod
        }

        if now >= nextClockGlyphMutationTime && now >= nextClockGlyphMutationBatchTime {
            mutateClockGlyphs(now: now)
            nextClockGlyphMutationBatchTime = now + clockGlyphMutationBatchInterval
        }

        if now >= nextClockTextCheckTime {
            updateClockTextIfNeeded(now: now)
        }
    }

    private func rebuildColumns() {
        guard viewportSize.x > 0, viewportSize.y > 0 else {
            columns = []
            rainInstanceCapacity = 1
            rainGlyphRowsPerColumn = 1
            rainGlyphIndices = []
            markRainColumnStaticDirty()
            markRainGlyphIndicesDirty()
            return
        }

        let count = max(1, Int(viewportSize.x / columnSpacing))
        rainGlyphRowsPerColumn = max(1, Int(ceil(viewportSize.y / (minFontSize + 4))) + 2)
        rainGlyphIndices = (0..<(count * rainGlyphRowsPerColumn)).map { _ in
            UInt32(randomGlyphIndex())
        }
        columns = (0..<count).map { index in
            makeColumn(
                index: index,
                headY: random.nextFloat(in: 0...viewportSize.y),
                glyphOffset: index * rainGlyphRowsPerColumn
            )
        }
        rainInstanceCapacity = max(1, count * rainVisibleSlotsPerColumn)
        markRainColumnStaticDirty()
        markRainGlyphIndicesDirty()
    }

    private func makeColumn(index: Int, headY: Float, glyphOffset: Int) -> RainColumn {
        let speed = random.nextFloat(in: minSpeed...maxSpeed)
        let fontSize = fontSize(for: speed)
        let cellHeight = fontSize + 4
        let length = random.nextInt(in: minRainLength...maxRainLength)
        let rowCount = min(rainGlyphRowsPerColumn, max(1, Int(ceil(viewportSize.y / cellHeight)) + 2))
        let derived = rainColumnDerivedValues(fontSize: fontSize, cellHeight: cellHeight, length: length)
        let centerX = Float(index) * columnSpacing + columnSpacing * 0.5

        return RainColumn(
            centerX: centerX,
            headY: headY,
            speed: speed,
            length: length,
            fontSize: fontSize,
            cellHeight: cellHeight,
            inverseCellHeight: derived.inverseCellHeight,
            tailDistance: derived.tailDistance,
            glyphSize: derived.glyphSize,
            depthBrightness: derived.depthBrightness,
            rowCount: rowCount,
            glyphOffset: glyphOffset
        )
    }

    private func recycleColumn(at index: Int) {
        columns[index].headY = random.nextFloat(in: -220...0)
        columns[index].speed = random.nextFloat(in: minSpeed...maxSpeed)
        columns[index].fontSize = fontSize(for: columns[index].speed)
        columns[index].cellHeight = columns[index].fontSize + 4
        columns[index].length = random.nextInt(in: minRainLength...maxRainLength)
        let derived = rainColumnDerivedValues(
            fontSize: columns[index].fontSize,
            cellHeight: columns[index].cellHeight,
            length: columns[index].length
        )
        columns[index].inverseCellHeight = derived.inverseCellHeight
        columns[index].tailDistance = derived.tailDistance
        columns[index].glyphSize = derived.glyphSize
        columns[index].depthBrightness = derived.depthBrightness
        columns[index].rowCount = min(rainGlyphRowsPerColumn, max(1, Int(ceil(viewportSize.y / columns[index].cellHeight)) + 2))
        markRainColumnStaticDirty()
    }

    private func mutateRainGlyphs() {
        var columnIndex = random.skipCount(untilChance: rainGlyphMutationChance)
        var mutated = false

        while columnIndex < columns.count {
            let column = columns[columnIndex]
            guard column.rowCount > 0 else {
                columnIndex += 1 + random.skipCount(untilChance: rainGlyphMutationChance)
                continue
            }

            let tailY = column.headY - column.tailDistance
            let firstRow = max(0, Int(floor(tailY * column.inverseCellHeight)))
            let lastRow = min(
                column.rowCount - 1,
                Int(ceil((column.headY + column.cellHeight) * column.inverseCellHeight))
            )

            if firstRow <= lastRow {
                let row = random.nextInt(in: firstRow...lastRow)
                rainGlyphIndices[column.glyphOffset + row] = UInt32(randomGlyphIndex())
                mutated = true
            }

            columnIndex += 1 + random.skipCount(untilChance: rainGlyphMutationChance)
        }

        if mutated {
            markRainGlyphIndicesDirty()
        }
    }

    private func mutateClockGlyphs(now: TimeInterval) {
        var nextMutationTime = TimeInterval.greatestFiniteMagnitude
        var mutated = false

        for clusterIndex in clockClusters.indices where clockClusters[clusterIndex].isLit {
            for glyphIndex in clockClusters[clusterIndex].glyphs.indices {
                if clockClusters[clusterIndex].glyphs[glyphIndex].nextMutationTime <= now {
                    clockClusters[clusterIndex].glyphs[glyphIndex] = randomClockGlyph(now: now)
                    mutated = true
                }

                nextMutationTime = min(
                    nextMutationTime,
                    clockClusters[clusterIndex].glyphs[glyphIndex].nextMutationTime
                )
            }
        }

        nextClockGlyphMutationTime = nextMutationTime.isFinite ? nextMutationTime : now + clockGlyphMinimumMutationInterval

        if mutated {
            clockInstancesDirty = true
        }
    }

    private func prepareRainColumnStaticBuffer(at bufferIndex: Int) -> MTLBuffer? {
        guard !columns.isEmpty else {
            return nil
        }

        let requiredLength = columns.count * MemoryLayout<RainColumnStaticState>.stride

        if rainColumnStaticBuffers[bufferIndex] == nil || (rainColumnStaticBuffers[bufferIndex]?.length ?? 0) < requiredLength {
            let capacity = max(requiredLength, (rainColumnStaticBuffers[bufferIndex]?.length ?? 4096) * 2)
            rainColumnStaticBuffers[bufferIndex] = device.makeBuffer(length: capacity, options: .storageModeShared)
            rainColumnStaticBufferVersions[bufferIndex] = 0
        }

        guard let buffer = rainColumnStaticBuffers[bufferIndex] else {
            return nil
        }

        guard rainColumnStaticBufferVersions[bufferIndex] != rainColumnStaticVersion else {
            return buffer
        }

        let pointer = buffer.contents().bindMemory(to: RainColumnStaticState.self, capacity: columns.count)

        for index in columns.indices {
            let column = columns[index]
            pointer[index] = RainColumnStaticState(
                metrics0: SIMD4<Float>(
                    column.centerX,
                    column.cellHeight,
                    column.inverseCellHeight,
                    Float(column.length)
                ),
                metrics1: SIMD4<Float>(
                    column.glyphSize.x,
                    column.glyphSize.y,
                    column.depthBrightness,
                    0
                ),
                glyphInfo: SIMD4<UInt32>(
                    UInt32(column.rowCount),
                    UInt32(column.glyphOffset),
                    0,
                    0
                )
            )
        }

        rainColumnStaticBufferVersions[bufferIndex] = rainColumnStaticVersion
        return buffer
    }

    private func prepareRainHeadYBuffer(at bufferIndex: Int) -> MTLBuffer? {
        guard !columns.isEmpty else {
            return nil
        }

        let requiredLength = columns.count * MemoryLayout<Float>.stride

        if rainHeadYBuffers[bufferIndex] == nil || (rainHeadYBuffers[bufferIndex]?.length ?? 0) < requiredLength {
            let capacity = max(requiredLength, (rainHeadYBuffers[bufferIndex]?.length ?? 4096) * 2)
            rainHeadYBuffers[bufferIndex] = device.makeBuffer(length: capacity, options: .storageModeShared)
        }

        guard let buffer = rainHeadYBuffers[bufferIndex] else {
            return nil
        }

        let pointer = buffer.contents().bindMemory(to: Float.self, capacity: columns.count)

        for index in columns.indices {
            pointer[index] = columns[index].headY
        }

        return buffer
    }

    private func prepareRainGlyphIndexBuffer(at bufferIndex: Int) -> MTLBuffer? {
        guard !rainGlyphIndices.isEmpty else {
            return nil
        }

        let requiredLength = rainGlyphIndices.count * MemoryLayout<UInt32>.stride

        if rainGlyphIndexBuffers[bufferIndex] == nil || (rainGlyphIndexBuffers[bufferIndex]?.length ?? 0) < requiredLength {
            let capacity = max(requiredLength, (rainGlyphIndexBuffers[bufferIndex]?.length ?? 4096) * 2)
            rainGlyphIndexBuffers[bufferIndex] = device.makeBuffer(length: capacity, options: .storageModeShared)
            rainGlyphIndexBufferVersions[bufferIndex] = 0
        }

        guard let buffer = rainGlyphIndexBuffers[bufferIndex] else {
            return nil
        }

        if rainGlyphIndexBufferVersions[bufferIndex] != rainGlyphIndexVersion {
            let _ = rainGlyphIndices.withUnsafeBytes { bytes in
                memcpy(buffer.contents(), bytes.baseAddress!, requiredLength)
            }
            rainGlyphIndexBufferVersions[bufferIndex] = rainGlyphIndexVersion
        }

        return buffer
    }

    private func makeClockLayout(origin: SIMD2<Float>? = nil) -> ClockLayout? {
        guard clockTotalColumns > 0, !clockClusters.isEmpty else {
            return nil
        }

        let targetWidth = viewportSize.x * clockWidthFraction
        let cellSize = targetWidth / Float(clockTotalColumns)
        let size = SIMD2<Float>(targetWidth, Float(clockRows) * cellSize)
        let screenOrigin = SIMD2<Float>(
            (viewportSize.x - size.x) / 2,
            (viewportSize.y - size.y) / 2
        )

        return ClockLayout(origin: origin ?? screenOrigin, size: size, cellSize: cellSize)
    }

    private func renderClockTextureIfNeeded(commandBuffer: MTLCommandBuffer, backingScale: Float) {
        if abs(clockTextureScale - backingScale) > 0.01 {
            clockInstancesDirty = true
        }

        guard clockInstancesDirty else {
            return
        }

        guard let screenLayout = makeClockLayout(),
              let localLayout = makeClockLayout(origin: .zero),
              let clockTexture = ensureClockTexture(size: screenLayout.size, backingScale: backingScale) else {
            self.clockTexture = nil
            clockTextureQuad = nil
            clockInstanceCount = 0
            clockInstancesDirty = false
            return
        }

        clockInstances.removeAll(keepingCapacity: true)
        clockInstances.reserveCapacity(estimateClockInstanceCapacity())
        buildClockInstances(into: &clockInstances, layout: localLayout)
        clockInstanceCount = clockInstances.count

        guard clockInstanceCount > 0,
              let clockInstanceBuffer = uploadInstances(clockInstances, using: &clockInstanceBuffer) else {
            clockTextureQuad = nil
            clockInstancesDirty = false
            return
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = clockTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(clockInstanceBuffer, offset: 0, index: 0)

        var uniforms = Uniforms(
            viewportSize: screenLayout.size,
            rainVisibleSlotsPerColumn: UInt32(max(1, rainVisibleSlotsPerColumn)),
            padding: 0
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(atlasTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: clockInstanceCount)
        encoder.endEncoding()

        clockTextureQuad = GlyphInstance(
            position: screenLayout.origin + screenLayout.size / 2,
            size: screenLayout.size,
            uvOrigin: SIMD2<Float>(0, 0),
            uvSize: SIMD2<Float>(1, 1),
            color: SIMD4<Float>(1, 1, 1, 1)
        )
        clockInstancesDirty = false
    }

    private func ensureClockTexture(size: SIMD2<Float>, backingScale: Float) -> MTLTexture? {
        let width = max(1, Int(ceil(size.x * backingScale)))
        let height = max(1, Int(ceil(size.y * backingScale)))

        if let clockTexture,
           clockTexture.width == width,
           clockTexture.height == height,
           abs(clockTextureScale - backingScale) <= 0.01 {
            return clockTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        clockTextureScale = backingScale
        clockTexture = device.makeTexture(descriptor: descriptor)
        return clockTexture
    }

    private func buildClockInstances(into instances: inout [GlyphInstance], layout: ClockLayout) {
        for row in 0..<clockRows {
            for column in 0..<clockTotalColumns {
                let clusterIndex = row * clockTotalColumns + column
                guard clusterIndex < clockClusters.count, clockClusters[clusterIndex].isLit else {
                    continue
                }

                let cellOrigin = SIMD2<Float>(
                    layout.origin.x + Float(column) * layout.cellSize,
                    layout.origin.y + Float(row) * layout.cellSize
                )
                buildClockStroke(
                    cellOrigin: cellOrigin,
                    cellSize: layout.cellSize,
                    glyphs: clockClusters[clusterIndex].glyphs,
                    into: &instances
                )
            }
        }
    }

    private func buildClockStroke(
        cellOrigin: SIMD2<Float>,
        cellSize: Float,
        glyphs: [ClockGlyph],
        into instances: inout [GlyphInstance]
    ) {
        let glyphStep = clockGlyphStep(for: cellSize)
        let clusterSize = glyphStep * Float(clockSideCount)
        let start = SIMD2<Float>(
            cellOrigin.x + cellSize / 2 - clusterSize / 2,
            cellOrigin.y + cellSize / 2 - clusterSize / 2
        )

        for row in 0..<clockSideCount {
            for column in 0..<clockSideCount {
                let glyphIndex = row * clockSideCount + column
                guard glyphIndex < glyphs.count else {
                    continue
                }

                let glyph = glyphs[glyphIndex]
                let foregroundSize = SIMD2<Float>(
                    glyphStep * clockGlyphWidthScale,
                    glyphStep * clockGlyphHeightScale
                )
                let glowSize = SIMD2<Float>(
                    foregroundSize.x * clockGlowScale,
                    foregroundSize.y * clockGlowScale
                )
                let position = SIMD2<Float>(
                    start.x + Float(column) * glyphStep + glyphStep / 2,
                    start.y + Float(row) * glyphStep + glyphStep / 2
                )
                let glowColor = SIMD4<Float>(0.48, 1.0, 0.62, 0.10)
                let foregroundColor = clockColor(for: glyph.whiteness)

                appendGlyph(
                    glyph.glyphIndex,
                    position: position,
                    size: glowSize,
                    color: glowColor,
                    into: &instances
                )
                appendGlyph(
                    glyph.glyphIndex,
                    position: position,
                    size: foregroundSize,
                    color: foregroundColor,
                    into: &instances
                )
            }
        }
    }

    private func appendGlyph(
        _ glyphIndex: Int,
        position: SIMD2<Float>,
        size: SIMD2<Float>,
        color: SIMD4<Float>,
        into instances: inout [GlyphInstance]
    ) {
        let index = max(0, min(glyphSymbols.count - 1, glyphIndex))
        let uv = glyphUVs[index]

        instances.append(
            GlyphInstance(
                position: position,
                size: size,
                uvOrigin: uv.origin,
                uvSize: uv.size,
                color: color
            )
        )
    }

    private func uploadInstances(_ instances: [GlyphInstance], using buffer: inout MTLBuffer?) -> MTLBuffer? {
        let requiredLength = instances.count * MemoryLayout<GlyphInstance>.stride
        guard requiredLength > 0 else {
            return nil
        }

        if buffer == nil || (buffer?.length ?? 0) < requiredLength {
            let capacity = max(requiredLength, (buffer?.length ?? 4096) * 2)
            buffer = device.makeBuffer(length: capacity, options: .storageModeShared)
        }

        guard let buffer else {
            return nil
        }

        let _ = instances.withUnsafeBytes { bytes in
            memcpy(buffer.contents(), bytes.baseAddress, requiredLength)
        }

        return buffer
    }

    private func estimateClockInstanceCapacity() -> Int {
        let litClusters = clockClusters.reduce(0) { total, cluster in
            total + (cluster.isLit ? 1 : 0)
        }
        return max(1, litClusters * clockSideCount * clockSideCount * 2)
    }

    private func clockColor(for whiteness: Float) -> SIMD4<Float> {
        let value = max(0, min(1, whiteness))
        return SIMD4<Float>(
            0.50 + 0.48 * value,
            0.82 + 0.18 * value,
            0.56 + 0.42 * value,
            0.80 + 0.20 * value
        )
    }

    private func clockGlyphStep(for cellSize: Float) -> Float {
        max(1, cellSize / Float(clockSideCount))
    }

    private func fontSize(for speed: Float) -> Float {
        let progress = (speed - minSpeed) / (maxSpeed - minSpeed)
        return round(minFontSize + progress * (maxFontSize - minFontSize))
    }

    private func rainColumnDerivedValues(
        fontSize: Float,
        cellHeight: Float,
        length: Int
    ) -> (
        inverseCellHeight: Float,
        tailDistance: Float,
        glyphSize: SIMD2<Float>,
        depthBrightness: Float
    ) {
        let sizeProgress = (fontSize - minFontSize) / (maxFontSize - minFontSize)
        let depthBrightness = 0.42 + 0.58 * max(0, min(1, sizeProgress))
        let glyphSize = SIMD2<Float>(
            min(columnSpacing * 0.88, fontSize * 1.05),
            fontSize * 1.18
        )

        return (
            inverseCellHeight: 1 / cellHeight,
            tailDistance: Float(length) * cellHeight,
            glyphSize: glyphSize,
            depthBrightness: depthBrightness
        )
    }

    private func randomGlyphIndex() -> Int {
        random.nextIndex(count: glyphSymbols.count)
    }

    private func markRainColumnStaticDirty() {
        rainColumnStaticVersion &+= 1

        if rainColumnStaticVersion == 0 {
            rainColumnStaticVersion = 1
            rainColumnStaticBufferVersions = [UInt64](repeating: 0, count: rainInstanceBufferCount)
        }
    }

    private func markRainGlyphIndicesDirty() {
        rainGlyphIndexVersion &+= 1

        if rainGlyphIndexVersion == 0 {
            rainGlyphIndexVersion = 1
            rainGlyphIndexBufferVersions = [UInt64](repeating: 0, count: rainInstanceBufferCount)
        }
    }

    private func randomClockGlyph(now: TimeInterval) -> ClockGlyph {
        ClockGlyph(
            glyphIndex: randomGlyphIndex(),
            whiteness: random.nextFloat(),
            nextMutationTime: now + clockGlyphMinimumMutationInterval + TimeInterval(random.nextFloat(in: 0...clockGlyphMutationSpread))
        )
    }

    private func randomClockClusterGlyphs(now: TimeInterval) -> [ClockGlyph] {
        let count = clockSideCount * clockSideCount
        return (0..<count).map { _ in randomClockGlyph(now: now) }
    }

    private func updateClockTextIfNeeded(force: Bool = false, now: TimeInterval) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let minuteKey = hour * 60 + minute

        guard force || minuteKey != cachedClockMinute else {
            scheduleNextClockTextCheck(now: now)
            return
        }

        let previousText = cachedClockText
        cachedClockMinute = minuteKey
        cachedClockText = String(format: "%02d:%02d", hour, minute)
        applyClockText(
            cachedClockText,
            resetAll: force || previousText.isEmpty,
            now: now
        )
        scheduleNextClockTextCheck(now: now)
    }

    private func applyClockText(_ text: String, resetAll: Bool, now: TimeInterval) {
        let totalColumns = clockColumnCount(for: text)
        guard totalColumns > 0 else {
            clockTotalColumns = 0
            clockClusters = []
            clockInstancesDirty = true
            nextClockGlyphMutationTime = now + clockGlyphMinimumMutationInterval
            nextClockGlyphMutationBatchTime = now
            return
        }

        let requiredCount = totalColumns * clockRows
        let litCells = clockLitCells(for: text, totalColumns: totalColumns)
        let shouldRebuild = resetAll || clockTotalColumns != totalColumns || clockClusters.count != requiredCount

        if shouldRebuild {
            clockTotalColumns = totalColumns
            clockClusters = (0..<requiredCount).map { _ in
                ClockCluster(isLit: false, glyphs: randomClockClusterGlyphs(now: now))
            }
        }

        for index in 0..<requiredCount {
            let shouldBeLit = index < litCells.count && litCells[index]
            guard clockClusters[index].isLit != shouldBeLit else {
                continue
            }

            clockClusters[index].isLit = shouldBeLit

            if shouldBeLit {
                clockClusters[index].glyphs = randomClockClusterGlyphs(now: now)
            }
        }

        rescheduleNextClockGlyphMutationTime(now: now)
        nextClockGlyphMutationBatchTime = min(nextClockGlyphMutationBatchTime, now)
        clockInstancesDirty = true
    }

    private func clockLitCells(for text: String, totalColumns: Int) -> [Bool] {
        var litCells = Array(repeating: false, count: totalColumns * clockRows)
        var columnOffset = 0

        for character in text {
            let pattern = Self.clockPatterns[character] ?? []

            for row in 0..<clockRows where row < pattern.count {
                for (column, value) in pattern[row].enumerated() where value == "1" {
                    let gridColumn = columnOffset + column
                    guard gridColumn < totalColumns else {
                        continue
                    }

                    litCells[row * totalColumns + gridColumn] = true
                }
            }

            columnOffset += (character == ":" ? colonColumns : digitColumns) + characterSpacing
        }

        return litCells
    }

    private func rescheduleNextClockGlyphMutationTime(now: TimeInterval) {
        var nextMutationTime = TimeInterval.greatestFiniteMagnitude

        for cluster in clockClusters where cluster.isLit {
            for glyph in cluster.glyphs {
                nextMutationTime = min(nextMutationTime, glyph.nextMutationTime)
            }
        }

        nextClockGlyphMutationTime = nextMutationTime.isFinite ? nextMutationTime : now + clockGlyphMinimumMutationInterval
    }

    private func scheduleNextClockTextCheck(now: TimeInterval) {
        nextClockTextCheckTime = now + secondsUntilNextMinute()
    }

    private func secondsUntilNextMinute() -> TimeInterval {
        let timestamp = Date().timeIntervalSince1970
        let elapsed = timestamp.truncatingRemainder(dividingBy: 60)
        return max(0.2, 60 - elapsed + clockTextCheckSafetyMargin)
    }

    private func clockColumnCount(for text: String) -> Int {
        let contentColumns = text.reduce(0) { total, character in
            total + (character == ":" ? colonColumns : digitColumns)
        }
        return contentColumns + max(0, text.count - 1) * characterSpacing
    }

    private static func makeGlyphUVs(symbolCount: Int, cellSize: Int, columns: Int) -> [GlyphUV] {
        let rows = Int(ceil(Float(symbolCount) / Float(columns)))
        let atlasWidth = Float(columns * cellSize)
        let atlasHeight = Float(max(1, rows * cellSize))
        let inset: Float = 1.5

        return (0..<symbolCount).map { index in
            let column = index % columns
            let row = index / columns
            let textureRow = rows - 1 - row
            let origin = SIMD2<Float>(
                (Float(column * cellSize) + inset) / atlasWidth,
                (Float(textureRow * cellSize) + inset) / atlasHeight
            )
            let size = SIMD2<Float>(
                (Float(cellSize) - inset * 2) / atlasWidth,
                (Float(cellSize) - inset * 2) / atlasHeight
            )

            return GlyphUV(origin: origin, size: size)
        }
    }

    private static func makeGlyphAtlas(
        device: MTLDevice,
        symbols: [String],
        cellSize: Int,
        columns: Int
    ) -> MTLTexture {
        let rows = Int(ceil(Float(symbols.count) / Float(columns)))
        let width = columns * cellSize
        let height = max(1, rows * cellSize)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Unable to create glyph atlas bitmap")
        }

        bitmap.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(cellSize) * 0.62, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        for (index, symbol) in symbols.enumerated() {
            let glyph = NSString(string: symbol)
            let column = index % columns
            let row = index / columns
            let rect = NSRect(
                x: CGFloat(column * cellSize),
                y: CGFloat(row * cellSize),
                width: CGFloat(cellSize),
                height: CGFloat(cellSize)
            )
            let size = glyph.size(withAttributes: attributes)
            guard size.width > 0, size.height > 0 else {
                continue
            }

            let maxWidth = rect.width * 0.82
            let scaleX = min(1, maxWidth / size.width)
            let point = NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2
            )

            if scaleX < 1 {
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: rect.midX, yBy: 0)
                transform.scaleX(by: scaleX, yBy: 1)
                transform.translateX(by: -rect.midX, yBy: 0)
                transform.concat()
                glyph.draw(at: point, withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                glyph.draw(at: point, withAttributes: attributes)
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor),
              let data = bitmap.bitmapData else {
            fatalError("Unable to create glyph atlas texture")
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: bitmap.bytesPerRow
        )

        return texture
    }

    private static func initialPseudoRandomSeed() -> UInt64 {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let processID = UInt64(ProcessInfo.processInfo.processIdentifier)
        return timestamp ^ (processID &* 0x9E3779B97F4A7C15)
    }
}
