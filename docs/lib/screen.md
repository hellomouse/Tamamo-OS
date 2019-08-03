This library is the primary renderer for Tamamo OS, utilizing a double-buffered technique to minimize GPU calls. The result is something many times faster than directly calling the native GPU, at the cost of higher RAM use (Around 20-40% of a T3.5 RAM stick).

The idea is the same as other double-buffered algorithms for OC: there are two buffers, one to store the current screen state and another to store changes to be made. When an update call is made, the change buffer is collapsed onto the current state buffer, which is then grouped by background/foreground categories and rendered onto the screen, minimizing color change gpu calls.

![Animation of buffered vs non-buffered](https://media.giphy.com/media/MagIYaQQxbVFXBbBPS/giphy.gif)

*Top: double-buffered drawing. Bottom: char by char drawing*

Furthermore, the screen lib comes with additional methods for basic drawing such as text and geometries, which can utilize color blending to mimic transparency.

# Table of Contents
- [Main Methods](#main-methods)
    + [screen.setResolution](#screensetresolutionint-w-int-h)
    + [screen.getResolution](#screengetresolution-int-width-int-height)
    + [screen.bind](#screenbindstring-address-boolean-resetfalse)
    + [screen.setDrawingBound](#screensetdrawingboundint-x1-int-y1-int-x2-int-y2-boolean-usecurrent)
    + [screen.getDrawingBound](#screengetdrawingbound-int-x1-int-y1-int-x2-int-y2)
    + [screen.resetDrawingBound](#screenresetdrawingbound)
    + [screen.resetPalette](#screenresetpalette)
    + [screen.setGPUProxy](#screensetgpuproxytable-gpu)
    + [screen.getGPUProxy](#screengetgpuproxy-table-gpuproxy)
- [Rendering Methods](#rendering-methods)
    + [screen.clear](#screenclearint-color-float-alpha-00-10)
    + [screen.update](#screenupdateboolean-force)
- [Basic Drawing](#basic-drawing)
    + [screen.setBackground](#screensetbackgroundint-color-boolean-ispalette-int-previouscolor-boolean-ispaletteindex)
    + [screen.setForeground](#screensetforegroundint-color-boolean-ispalette-int-previouscolor-boolean-ispaletteindex)
    + [screen.getBackground](#screengetbackground-int-previouscolor-boolean-ispaletteindex)
    + [screen.getForeground](#screengetforeground-int-previouscolor-boolean-ispaletteindex)
    + [screen.set](#screensetint-x-int-y-string-string-boolean-vertical-boolean-success)
    + [screen.copy](#screencopyint-x-int-y-int-w-int-h-int-tx-int-ty-boolean-success)
    + [screen.fill](#screenfillint-x-int-y-int-w-int-h-string-symbol-boolean-success)
- [Higher level drawing](#higher-level-drawing)
    + [screen.drawRectangle](#screendrawrectangleint-x-int-y-int-w-int-h-float-alpha-00-10-string-symbol-boolean-success)
    + [screen.drawRectangleOutline](#screendrawrectangleoutlineint-x-int-y-int-w-int-h-float-alpha-00-10-string-symbol-boolean-success)
    + [screen.drawBrailleRectangle](#screendrawbraillerectanglefloat-x-float-y-float-w-float-h-float-alpha-00-10-boolean-success)
    + [screen.drawBrailleRectangleOutline](#screendrawbraillerectangleoutlinefloat-x-float-y-float-w-float-h-float-alpha-00-10-boolean-success)
    + [screen.drawThinRectangleOutline](#screendrawthinrectangleoutlineint-x-int-y-int-w-int-h-float-alpha-00-10-boolean-success)
    + [screen.drawText](#screendrawtextint-x-int-y-string-string--float-alpha-00-10-boolean-blendbg-boolean-success)
    + [screen.drawEllipse](#screendrawellipseint-x-int-y-int-a-int-b-float-alpha-00-10-string-symbol-boolean-success)
    + [screen.drawEllipseOutline](#screendrawellipseoutlineint-x-int-y-int-a-int-b-float-alpha-00-10-string-symbol-boolean-success)
    + [screeen.drawBrailleEllipse](#screeendrawbrailleellipsefloat-x-float-y-float-a-float-b--float-alpha-00-10-boolean-success)
    + [screeen.drawBrailleEllipseOutline](#screeendrawbrailleellipseoutlinefloat-x-float-y-float-a-float-b--float-alpha-00-10-boolean-success)
    + [screen.drawLine](#screendrawlineint-x1-int-y1-int-x2-int-y2-float-alpha-00-10-string-symbol-boolean-success)
    + [screen.drawBrailleLine](#screendrawbraillelinefloat-x1-float-y1-float-x2-float-y2-float-alpha-00-10-boolean-success)
- [Auxiliary Methods](#auxiliary-methods)
    + [screen.flush](#screenflushint-w-int-h)
    + [screen.rawGet](#screenrawgetint-x-int-y-boolean-dontnormalize-int-bgcolor-int-fgcolor-string-symbol)
    + [screen.rawSet](#screenrawsetint-x-int-y-int-fgcolor-int-bgcolor-int-symbol)
    + [screen.getIndex](#screengetindexint-x-int-y-int-index)
    + [screen.getCoords](#screengetcoordsint-index-int-x-int-y)
    + [screen.getCurrentBuffer](#screengetcurrentbuffer-table-backgroundbuffer-table-foregroundbuffer-table-symbolbuffer)
    + [screen.getChangeBuffer](#screengetchangebuffer-table-backgroundbuffer-table-foregroundbuffer-table-symbolbuffer)
- [Example](#example)
- [Using screen.lua in existing programs](#using-screenlua-in-existing-programs)

# Main Methods
### screen.setResolution(*int* w, *int* h)
Sets the screen resolution and buffer size to the given size, clearing the buffer by filling it with black and the whitespace symbol.

### screen.getResolution(): *int* width, *int* height
Returns the current screen resolution / buffer size in characters. There's also **screen.getWidth()** and **screen.getHeight()** for individual components of size.

### screen.bind(*string* address, **boolean* reset=false)
Binds GPU to given screen component address. Buffer will be filled with black and whitespace symbol. If **reset** is true buffer will be resized to the current new screen resolution.

### screen.setDrawingBound(*int* x1, *int* y1, *int* x2, *int* y2, *boolean* useCurrent)
Defines the rectangle region of the screen that can be drawn in. Once set, rendering done outside of this region will be ignored. If the **useCurrent** flag is true, then it will take the intersection of the current drawing bound with the new one as the new drawing bound, otherwise it will override any previous drawing bounds.

Calling **setDrawingBound()** with no arguments sets the drawing bound to (1, 1) to (bufferWidth, bufferHeight), which is the default limit. 

#### Additional Behavior:

If any of the numbers are non-integer they will be rounded down. Coordinates cannot exceed screen bounds, and will be automatically rounded to nearest valid screen bound if they do. Code will throw an error if **(x1, y1)** is not the top-left corner of the rectangle defined, or if the area bounded is 0.

### screen.getDrawingBound(): *int* x1, *int* y1, *int* x2, *int* y2
Returns the current drawing bound.

### screen.resetDrawingBound()
Sets the current drawing bound to (1, 1) to (bufferWidth, bufferHeight). Functionally identical to calling **setDrawingBound()** with no arguments.

### screen.resetPalette()
Resets the GPU palette to the default OC gray colors.

### screen.setGPUProxy(*table* gpu)
Switch the gpu proxy to given argument. Buffer will be filled with black whitespace symbols.

### screen.getGPUProxy(): *table* GPUProxy
Returns current GPU component proxy.


# Rendering Methods

### screen.clear(*int* color, **float* alpha *[0.0; 1.0]*)
Draw a rectangle across the entire screen with color and optional alpha value.

### screen.update(**boolean* force)
Collapses the change buffer onto the current buffer and renders everything changes to the screen. If the optional **force** argument is enabled it will redraw the entire current buffer from scratch.

# Basic Drawing
### screen.setBackground(*int* color, **boolean* isPalette): *int* previousColor, *boolean* isPaletteIndex
Sets the current background color used for set and fill, works the same way as gpu.setBackground. Returns previous background color, and if it's a palette index.

### screen.setForeground(*int* color, **boolean* isPalette): *int* previousColor, *boolean* isPaletteIndex
Sets the current foreground color used for set and fill, works the same way as gpu.setForeground. Returns previous foreground color, and if it's a palette index.

### screen.getBackground(): *int* previousColor, *boolean* isPaletteIndex
Gets the current background color used for set and fill, works the same way as gpu.getBackground. Returns the current background color, and if it's a palette index.

### screen.getForeground(): *int* previousColor, *boolean* isPaletteIndex
Gts the current foreground color used for set and fill, works the same way as gpu.getForeground. Returns the current foreground color, and if it's a palette index.

### screen.set(*int* x, *int* y, *string* string, **boolean* vertical): *boolean* success
Writes a string to the screen with current background and foreground. All characters (including line breaks) will be displayed in a single row or column depending on if *vertical* is true. Returns `true` if buffer was updated, `false` if not. This method does not call update().

*Note: returns `true` even if string is only partially written to buffer*

### screen.copy(*int* x, *int* y, *int* w, *int* h, *int* tx, *int* ty): *boolean* success
Displaces a rectangular region of the screen defined by x, y, w and h (where x and y are the top left corner of a rectangle) by tx and ty. Returns `true` if buffer was updated, `false` if not.

Copy will respect any screen drawing bounds that are set. Note that copy() will copy as if the current buffer were flushed, as in any changes not currently drawn to the screen will also be copied. This method does not call update()

### screen.fill(*int* x, *int* y, *int* w, *int* h, *string* symbol): *boolean* success
Fills a rectangle with the specified character. The fill character must be a string of length one, i.e. a single character. Returns `true` if buffer was updated, `false` if not. This method does not call update()

# Higher level drawing
These methods use the current background color; use `screen.setBackground()` to set the color used to draw. Note that `screen.setBackground` is seperate from `gpu.setBackground`. In the methods that allow specifying a custom symbol, the current screen foreground color (not GPU foreground!) will also be applied to non-space symbols.

### screen.drawRectangle(*int* x, *int* y, *int* w, *int* h, **float* alpha *[0.0; 1.0]*, **string* symbol): *boolean* success
Draws a rectangle, with optional alpha (default 1) and a symbol (default: " ").

### screen.drawRectangleOutline(*int* x, *int* y, *int* w, *int* h, **float* alpha *[0.0; 1.0]*, **string* symbol): *boolean* success
Draws a rectangle, but only the outer edge (interior is empty). This is done with optional alpha (default 1) and a symbol (default: " ").

### screen.drawBrailleRectangle(*float* x, *float* y, *float* w, *float* h, **float* alpha *[0.0; 1.0]*): *boolean* success
Draws a rectangle with braille characters, allowing sub-char precision. x values are accurate to the nearest 0.5, and y values are accurate to the nearest 0.25 (So for example I could do `screen.drawBrailleRectangle(1.5, 2.25, 2.5, 1.75)`). Alpha is optional (default: 1).

### screen.drawBrailleRectangleOutline(*float* x, *float* y, *float* w, *float* h, **float* alpha *[0.0; 1.0]*): *boolean* success
Draws a rectangle outline with braille characters, allowing sub-char precision. x values are accurate to the nearest 0.5, and y values are accurate to the nearest 0.25 (So for example I could do `screen.drawBrailleRectangleOutline(1.5, 2.25, 2.5, 1.75)`). Alpha is optional default: 1). The drawn rectangle has a thickness of 1 braille dot.

### screen.drawThinRectangleOutline(*int* x, *int* y, *int* w, *int* h, **float* alpha *[0.0; 1.0]*): *boolean* success
Draws a rectangle outline with box drawing characters. This creates a rectangle outline that's thinner than the braille outline, but does not support sub-char precision. Alpha is optional (default: 1).

### screen.drawText(*int* x, *int* y, *string* string,  **float* alpha *[0.0; 1.0]*, **boolean* blendBg): *boolean* success
Draw text at specified location. All text will be on one row, newlines and such will be rendered as special characters. If blendBg is enabled (default: true) then the text will "camouflage" itself against whatever background is behind it, otherwise it will function identically to `screen.set` and use the current screen background color. Alpha is optional (default: 1).

### screen.drawEllipse(*int* x, *int* y, *int* a, *int* b, **float* alpha *[0.0; 1.0]*, **string* symbol): *boolean* success
Draws an ellipse centered at x, y with semi-axii of lengths a and b (along the x and y direction respectively). You can optionally specify an alpha (default 1) and a symbol (default: " ").

### screen.drawEllipseOutline(*int* x, *int* y, *int* a, *int* b, **float* alpha *[0.0; 1.0]*, **string* symbol): *boolean* success
Draws a hollow ellipse centered at x, y with semi-axii of lengths a and b (along the x and y direction respectively). You can optionally specify an alpha (default 1) and a symbol (default: " ").

### screeen.drawBrailleEllipse(*float* x, *float* y, *float* a, *float* b, , **float* alpha *[0.0; 1.0]*): *boolean* success
Draws an ellipse using braille characters, allowing sub-char precision. x values are accurate to the nearest 0.5, and y values are accurate to the nearest 0.25. The ellipse is centered at x, y with semi-axii of lengths a and b (along the x and y direction respectively). You can optionally specify an alpha (default 1).

### screeen.drawBrailleEllipseOutline(*float* x, *float* y, *float* a, *float* b, , **float* alpha *[0.0; 1.0]*): *boolean* success
Draws an ellipse outline using braille characters, allowing sub-char precision. x values are accurate to the nearest 0.5, and y values are accurate to the nearest 0.25. The ellipse is centered at x, y with semi-axii of lengths a and b (along the x and y direction respectively). You can optionally specify an alpha (default 1). The drawn ellipse has a thickness of 1 braille dot.

### screen.drawLine(*int* x1, *int* y1, *int* x2, *int* y2, **float* alpha *[0.0; 1.0]*, **string* symbol): *boolean* success
Draws a line from (x1, y1) to (x2, y2). You can optionally specify an alpha (default 1) and a symbol (default: " ").

### screen.drawBrailleLine(*float* x1, *float* y1, *float* x2, *float* y2, **float* alpha *[0.0; 1.0]*): *boolean* success
Draws a line from (x1, y1) to (x2, y2) using braille characters and an optional alpha (default: 1). x coordinates are accurate to the nearest 0.5, and y coordinates are accurate to the nearest 0.25. The line has a thickness of 1 braille dot.


# Auxiliary Methods
These methods are mostly used internally and will not be useful, but in case you need to use it in your program they are listed here.

### screen.flush(*int* w, *int* h)
Clears the current screen buffer with black and whitespace symbols. Also resets any drawing bounds set. If either *w* or *h* are **not specified** w and h will be set to the current GPU resolution. Note this method does not change GPU resolution or actually fill the screen, it only re-creates the buffer.

### screen.rawGet(*int* x, *int* y, **boolean* dontNormalize): *int* bgColor, *int* fgColor, *string* symbol
Returns the background, foreground and symbol at a location. By default palette colors are normalized into a hex number instead of a palette index. Will return the change buffer first, and if there are no changes it returns the current buffer.

### screen.rawSet(*int* x, *int* y, *int* fgColor, *int* bgColor, *int* symbol)
Quick "raw" set that respects drawing bounds. This method **does not do type checking of any kind**, use with caution! To specify a palette index instead of a direct color, make the number negative. For example, *fgColor = -1* would mean the palette index 0 (First palette color).


### screen.getIndex(*int* x, *int* y): *int* index
Converts screen x,y coordinates into a buffer index. For example, if the buffer had a width of 10 and a height of 5, a coordinate of (1, 2) would have an index of 11, being the 11th character reading left to right, top down.

### screen.getCoords(*int* index): *int* x, *int* y
Inverse of **getIndex**, converts a buffer index into screen coordinates from (1, 1) to (bufferWidth, bufferHeight)

### screen.getCurrentBuffer(): *table* backgroundBuffer, *table* foregroundBuffer, *table* symbolBuffer
Get the buffers representing what is currently on the screen. Each buffer is 1-dimensional, coordinates can be converted to a table index with **screen.getIndex**.

### screen.getChangeBuffer(): *table* backgroundBuffer, *table* foregroundBuffer, *table* symbolBuffer
Get the buffers representing changes to be applied in the next *update()* call. Each buffer is 1-dimensional, coordinates can be converted to a table index with **screen.getIndex**.

# Example
```lua
-- Import screen lib
local screen = require("screen")

-- Fill background with black
screen.clear()

-- Draw rectangle grid with random colors
for y = 1, 3 do
  for x = 1, 5 do
    screen.setBackground(math.random(0x0, 0xFFFFFF))
    screen.drawRectangle(x * 7, y * 4, 6, 3)
  end
end

-- Draw a white braille ellipse outline
screen.setBackground(0xFFFFFF)
screen.drawBrailleEllipseOutline(24, 9.5, 10, 5)

-- Draw a yellow line
screen.setBackground(0xFFFF00)
screen.drawBrailleLine(7, 15, 41, 4)

-- Draw some white text
screen.setForeground(0xFFFFFF)
screen.drawText(18, 16, "Hello World!")

-- Draw changed pixels on screen
screen.update(true)
```
Output:

![Example output](https://i.imgur.com/b5eohnS.png)


# Using screen.lua in existing programs
For the most part you can simply replace gpu with screen and add `screen.update()` when you want to flush changes to a buffer. For example, this program

```lua
local gpu = require("component").gpu
gpu.setBackground(0xFFFFFF)
gpu.fill(1, 1, 20, 30)
gpu.setForeground(0x0)
gpu.set(5, 5, "Hello world!")
```

can be adapted to screen.lua as follows:

```lua
local screen = require("screen")
screen.setBackground(0xFFFFFF)
screen.fill(1, 1, 20, 30)
screen.setForeground(0x0)
screen.set(5, 5, "Hello world!")
screen.update() -- Flush changes to screen
```

Not all gpu methods are re-implemented in screen, so check this page for which methods are implemented and which aren't. For the ones that are not implemented you can keep the original gpu method, as it (probably) won't interact with screen.lua's internal buffer.
