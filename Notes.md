
## ToDo

- Granting accessibilityy perms: show window while waiting (screenshot?)
- Show some window at first launch, teilling the user that it is just a menu item
- Show the "should I check for updates autom." dialog right on launch
- Add also "auto install" checkmark to settings


## Filtering Code
```swift
// Union of all screen rects in CG coordinates for visibility checks.
// NSScreen.frame uses AppKit coords (bottom-left origin, Y up); convert to CG (top-left, Y down).
let primaryHeight = NSScreen.main?.frame.height ?? 0
let screenRects = NSScreen.screens.map { screen -> CGRect in
    CGRect(x: screen.frame.minX,
           y: primaryHeight - screen.frame.maxY,
           width: screen.frame.width,
           height: screen.frame.height)
}
```

And inside the compactMap closure, after the main guard:

```swift
// Exclude windows with zero alpha (fully transparent / invisible).
if let alpha = dict[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }

// Exclude zero-size helper/utility windows.
guard frame.width > 0, frame.height > 0 else { return nil }

// Exclude windows whose frame does not intersect any actual screen.
guard screenRects.contains(where: { $0.intersects(frame) }) else { return nil }
```
