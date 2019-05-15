This library is the primary render for the OS, utilizing a double-buffered technique to minimize GPU calls. The result is something that's many times faster than directly calling the native GPU, at the cost of higher RAM consumption.

The idea is the same as any other double-buffered drawing algorithim: there are two buffers, one to store the current screen state and another to store changes to be made. When an update call is made, the change buffer is collapsed onto the current state buffer, which is then grouped by background/foreground categories, and is then rendered onto the screen (minimizing color change gpu calls)

Among this basic optimization, there are also several minor ones which are outlined in the ["How the Screen Lib works" page](TODO URL)

# Main Methods
#### screen.setResolution(*int* w, *int* h)
Sets the screen resolution and buffer size to the given size, clearing the buffer by filling it with black and whitespace symbol.

#### screen.getResolution(): width, height
Returns the current screen resolution / buffer size in characters. There's also **screen.getWidth()** and **screen.getHeight()** for individual components of size.

#### screen.bind(*string* address, *boolean* reset=false)
Binds GPU to given screen component address. Buffer will be filled with black and whitespace symbol. If reset is true buffer will be resized to the current new screen resolution.


# Optimizing for Open OS
Fortunately, in our quest to be OpenOS compatabile, the screen lib automatically updates gpu component methods to utilize the double-buffer, so your OpenOS programs do not need to be updated. The only downside is that gpu methods will automatically update the buffer immediately after the call, negating any advantage gained by the double buffering. 

Thus, gpu extensive OpenOS programs should be optimized by adding a `true` flag to `set`, and `fill` methods, and  and calling `.update()` when rendering is ready. Other methods such as `copy` and `setBackground` do not need such a flag for optimization.

**Example: (Before)**
```lua
for i = 1, 10 do
    gpu.setBackground(0xFF0000)
    gpu.fill(1, i + 5, 10, 2, "j")
    gpu.set(1, i, "hello")
end
```

**Example: (After)**
```lua
for i = 1, 10 do
    screen.setBackground(0xFF0000)
    screen.fill(1, i + 5, 10, 2, "j", true) -- Note the extra true
    screen.set(1, i, "hello", true) -- Note the extra true
end
screen.update()
```