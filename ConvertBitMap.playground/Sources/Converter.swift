import AppKit
import MetalKit

/*
 Loads an unpacked Apple IIGS graphic ($C1/$0000) and make available
 the generated macOS bit map.
 */
public class Converter {
    public var bmData: [UInt8]

    public init?(_ url: URL) {
        
        var SCB = [UInt8](repeating: 0, count: 256)
        // Each scanline is 160 bytes. Each byte consists of 2 "pixels".
        // There are 200 scanlines in a 320x200 IIGS graphic
        var iigsBitmap = [UInt8](repeating: 0, count: 160*200)
        // First load the entire file
        var rawData: Data? = nil
        do {
            try rawData = Data(contentsOf: url)
        }
        catch let error {
            print("Error", error)
            return nil
        }

        // 1. Extract 160x200 = 32 000 bytes - this is the IIGS bitmap
        var range = Range(0..<32000)
        rawData?.copyBytes(to: &iigsBitmap, from: range)
     
        // 2. Extract 256 bytes - this is the SCB table (only 200 required).
        range = Range(32000..<32256)
        rawData?.copyBytes(to: &SCB, from: range)

        // 3. Extract 16 color tables = 16 x 32 bytes = 512 bytes.
        range = Range(32256..<32768)
        var buffer512 = [UInt8](repeating:0, count: 512)
        rawData?.copyBytes(to: &buffer512, from: range)
        // Declare a 2D array for easier access and copy data from buffer.
        var colorTables = [[UInt16]](repeating: [UInt16](repeating: 0, count: 16),
                                     count: 16)
        var k = 0;
         for row in 0..<16 {
            for col in 0..<16 {
                colorTables[row][col] = UInt16(buffer512[k]) + (UInt16(buffer512[k+1]) << 8)
                k = k + 2
                // Checked - color table entries are correct.
                //print(colorTables[row][col], terminator: " ")
            }
            //print()
         }
 
        bmData = Converter.convert(bitMap: iigsBitmap,
                                   colorTables: colorTables,
                                   scbs: SCB)
    }

    // Convert a IIGS bitmap to a macOS bitmap.
    // Each IIGS byte which has 2 "pixels" becomes 8 bytes.
    // The "pixels" are actually an index (0-15) to a color entry.
    // The color table to be used for a particular scanline is given
    // by its corresponding scanline control byte obtained from the SCBs table
    static func convert(bitMap:[UInt8],
                        colorTables: [[UInt16]],
                        scbs: [UInt8]) -> [UInt8] {
        // The width and height of the macOS bitmap.
        let width = 320
        let height = 200
        let bytesPerPixel = 4
        var macOSBitmap = [UInt8](repeating: 0,
                                  count: width*height*bytesPerPixel)

        for row in 0..<height {
            let whichColorTable = Int(scbs[row] & 0x0f)
            let baseIndex = row * width * bytesPerPixel     // macOS bitmap
            // Each Apple IIGS scanline is 160 bytes for the $C0/$0000 graphic format.
            for col in 0..<160 {
                let index = row * 160 + col                 // IIgs bitmap
                let pixels = bitMap[index]                  // 2 IIGS "pixels"
                var colorEntry = Int((pixels >> 4) & 0x0f)  // bits 4-7 - pixel # 0
                var whichColor = colorTables[whichColorTable][colorEntry]
                var r = ((whichColor & 0x0f00) >> 8) * 17   // 0-15 --> 0, 17, ...238, 255
                var g = ((whichColor & 0x00f0) >> 4) * 17
                var b = (whichColor & 0x000f) * 17
                // Convert the first "pixel" to a true pixel.
                let bmIndex = baseIndex + 8*col
                macOSBitmap[bmIndex+0] = UInt8(r)
                macOSBitmap[bmIndex+1] = UInt8(g)
                macOSBitmap[bmIndex+2] = UInt8(b)
                macOSBitmap[bmIndex+3] = UInt8(255)

                // Convert the second "pixel" to a true pixel.
                colorEntry = Int(pixels & 0x0f)             // bits 3-0 - pixel # 1
                whichColor = colorTables[whichColorTable][colorEntry]
                r = ((whichColor & 0x0f00) >> 8) * 17       // 0-15 --> 0, 17, ...238, 255
                g = ((whichColor & 0x00f0) >> 4) * 17
                b = (whichColor & 0x000f) * 17
                macOSBitmap[bmIndex+4] = UInt8(r)
                macOSBitmap[bmIndex+5] = UInt8(g)
                macOSBitmap[bmIndex+6] = UInt8(b)
                macOSBitmap[bmIndex+7] = UInt8(255)
            }
        }
        // Return the raw bit map for further processing.
        return macOSBitmap
    }
}

/*
 An object of this class is used to display the image.
 */
public class ImageView: NSView {
    var nsImage: NSImage?
    
    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let myBundle = Bundle.main
        let assetURL = myBundle.url(forResource: "ANGELFISH",
                                    withExtension:"SHR")
        let graphicsConverter = Converter(assetURL!)!
        let bmData = graphicsConverter.bmData
        // Create a CGImage object from the raw bit map.
        let cgImage = cgImageFromRawBitmap(bitMapData: bmData)
        let size = NSSize(width: 320, height: 200)
        nsImage = NSImage(cgImage: cgImage!, size: size)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func cgImageFromRawBitmap(bitMapData: UnsafeRawPointer) -> CGImage? {
        let width = 320
        let height = 200
        let bitsPerComponent = 8
        let bytesPerPixel = 4               // Four 8-bit components viz RGBA
        let colorSpace = NSDeviceRGBColorSpace
        // Create an instance of NSBitmapImageRep; pass nil as the first parameter
        // to tell macOS to allocate enough memory hold the image.
        let bir = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: width,
                                   pixelsHigh: height,
                                   bitsPerSample: bitsPerComponent,
                                   samplesPerPixel: bytesPerPixel,
                                   hasAlpha: true,
                                   isPlanar: false,
                                   colorSpaceName: colorSpace,
                                   bytesPerRow: width*bytesPerPixel,
                                   bitsPerPixel: bitsPerComponent*bytesPerPixel)
        memcpy(bir?.bitmapData, bitMapData, width*height*bytesPerPixel)
        guard let bmImageRep = bir
        else {
            return nil
        }
        return bmImageRep.cgImage
    }

    func imageRect() -> NSRect {
        let bounds = self.bounds
        return self.nsImage!.proportionalRectForTargetRect(bounds)
    }
    
 
    override public func draw(_ dirtyRect: NSRect) {
        let image = self.nsImage
        NSGraphicsContext.saveGraphicsState()
        image!.draw(in: imageRect(),
                    from: NSZeroRect,
                    operation: .sourceOver,
                    fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension NSImage
{
    func proportionalRectForTargetRect(_ targetRect: NSRect) ->NSRect {
        if NSEqualSizes(self.size, targetRect.size) {
            return targetRect
        }
        let imageSize = self.size
        let sourceWidth = imageSize.width
        let sourceHeight = imageSize.height

        let widthAdjust = targetRect.size.width / sourceWidth
        let heightAdjust = targetRect.size.height / sourceHeight
        var scaleFactor: CGFloat = 1.0

        if (widthAdjust < heightAdjust) {
            scaleFactor = widthAdjust
        }
        else {
            scaleFactor = heightAdjust
        }

        let finalWidth = sourceWidth * scaleFactor
        let finalHeight = sourceHeight * scaleFactor
        let finalSize = NSMakeSize(finalWidth, finalHeight)

        var finalRect = NSRect()
        finalRect.size = finalSize

        finalRect.origin = targetRect.origin
        finalRect.origin.x += (targetRect.size.width - finalWidth) * 0.5
        finalRect.origin.y += (targetRect.size.height - finalHeight) * 0.5

        return NSIntegralRect(finalRect)
    }
}

