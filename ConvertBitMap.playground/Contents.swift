/*
 A simple Playground demo to load an unpacked Apple IIGS Super-Hires graphic file ($C1/$0000) and display it.
 Written in Swift 3.x
 Requires XCode 8.x or later.
 */
import Cocoa
import PlaygroundSupport	// for the live preview

let viewFrame = NSMakeRect(0, 0, 640, 400)
let imageView = ImageView(frame: viewFrame)
PlaygroundPage.current.liveView = imageView
