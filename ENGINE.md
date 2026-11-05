# Engine version

**The project has been ported to Defold 1.14.0** (2026-11-05). It was originally built with 1.12.4.

## What changed in the move to 1.14.0

- 1.14.0 removed the old constants `render.FORMAT_*`, `render.FILTER_*`,
  `render.WRAP_*` from `render.*` (they are now `nil`). As a result, `render.render_target` failed with
  `Required parameter key not found: 'format'` and the game would not start.
  `render/gem_room.render_script` now uses `graphics.TEXTURE_FORMAT_*`,
  `graphics.TEXTURE_FILTER_*` and `graphics.TEXTURE_WRAP_*`, with the old names kept
  as a fallback, so the script also works on 1.12.x.
- Shaders (`#version 140`, uniform blocks, `#include`) needed no porting.
- Defold's shader pipeline rejects `inverse()`, so the 3x3 inverse is computed by hand
  (see `shaders/gem.vp`). Keep this in mind when writing new shaders.
- For web builds, bob also converts shaders to ESSL 1.00 (WebGL1), so they cannot use
  `textureSize`, `texelFetch`, or `abs`/`min`/`clamp` on integers. Render target sizes are passed as
  uniforms, and a texel is read by sampling at its center (see `fetch_texel` in `shaders/dof_fast_common.glsl`).
  A Windows build does not catch these errors; verify with a `--platform wasm-web` build.
- The web build platform in bob is now called `wasm-web` (instead of `js-web`).

## Verified

- bob 1.14.0 builds for `x86_64-win32` and `wasm-web` without errors.
- Running on Windows: the scene renders at 60 FPS with vsync.
- The web build has not been run in a browser.
