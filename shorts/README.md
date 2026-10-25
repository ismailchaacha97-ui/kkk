# Historical animated Shorts

## Boston Molasses Flood

- **Finished video:** `molasses_flood_animated_short.mp4`
- **Format:** 1080 × 1920, 30 fps, H.264/AAC, 42.7 seconds
- **Renderer:** `render_molasses_flood_short.py`
- **Original scene art:** `molasses_flood_scenes/`
- **Narration clips:** `molasses_flood_audio/`
- **Font files and SIL Open Font Licenses:** `assets/fonts/`

To re-render in an environment with Python, Pillow, NumPy, SciPy, and `imageio-ffmpeg` installed, run:

```bash
python shorts/render_molasses_flood_short.py
```

The first two seconds are an animated cold open; the rest combines camera moves, custom vector motion overlays, on-screen captions, original synthetic score, foley, and selected narration. Temporary decode/render files are written under `.cache/molasses_render/`.
