# Local resource provenance and licenses

Source directory: `C:\Users\PC-02\Documents\animacion`. No downloads or new runtime dependencies.


## webgl-starfield-master

Archive: `C:\Users\PC-02\Documents\animacion\webgl-starfield-master.zip`

SHA256: `0b1e5390a594c3af70f072bbfbfe35008fe828ee6cdd9e6ed300a2a6db67d2f0`

Files actually ported to `Motion.js`: shaders/stars-fshader.glsl

Hash21 + pow(rand,130), sparse field capped at 38 stars. A local deterministic depth value adds 1–2 pixels of finite parallax, driven by the single opening clock.

```text
MIT License

Copyright (c) 2020 RocketBoots Web Game Kit

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```


## flubber-master

Archive: `C:\Users\PC-02\Documents\animacion\flubber-master.zip`

SHA256: `9c667d9092d6bb2dc4c74372ec9301befdd3676b9cc31dcbe875de2cdcd2bd1d`

Files actually ported to `Motion.js`: src/rotate.js; src/math.js

Cyclic minimum-squared-distance correspondence and interpolation of closed, arc-length-resampled official contours. Six semantic regions are extracted from the official PNGs; component pairing and topology handling are local adaptations. This uses real code from src/rotate.js and src/math.js, not the full SVG/DOM library. The old particle expansion has been removed: there is no auxiliary particle resource in the active implementation.

```text
MIT License

Copyright (c) 2017 Noah Veltman

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

```
