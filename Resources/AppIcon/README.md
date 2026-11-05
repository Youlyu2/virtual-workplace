# 虚拟工位 App 图标

图标为原创暖色像素工位：木框、墨绿色背景、背影小人和薄荷绿显示器，与应用的小屋场景一致。

- `icon-source.png`：内置 imagegen 生成的透明 PNG 源图，原始输出保留，未手工改绘。
- `VirtualWorkplace.icns`：由源图通过原生 `sips` 与 `iconutil` 打包，覆盖16至1024像素。`scripts/build-app-icon.sh` 可重新生成。
- 应用使用 `CFBundleIconFile` 声明，并在启动时从包内载入图标，应用和 Dock 使用同一资源。
- 生成日期：2026-10-29。使用内置 imagegen，未使用 API/CLI fallback。

## 最终生成提示词

```text
Use case: stylized-concept.
Asset type: ONE finished macOS app icon for "虚拟工位" (Virtual Workplace), square 1024 by 1024 image, with genuine transparent pixels outside the icon tile.
Primary request: a beautiful original Stardew Valley-inspired cozy 16-bit pixel-art application icon that matches an earthy, sunlit wooden cabin workspace. This is a pixel game inventory-style icon, not a generic modern productivity logo.
Subject: a small brown-haired employee viewed STRICTLY FROM THE BACK, wearing a forest-green hoodie, sitting at a warm honey-colored wooden desk and working at one prominent glowing teal computer monitor. The back of the round pixel head and green shoulders are visible below the screen. The monitor MUST have a clear dark chunky pixel bezel, a small supporting neck and foot, and a simple pale mint green glowing screen with two or three large pixel strokes, no readable text. Include one tiny green leaf sprig as a subtle cabin motif.
Composition: one strong centered silhouette, the desk spans the lower half, monitor dominates the upper middle, employee back at lower center; easy to recognize at 32 pixels. A single rounded-square tile made from warm golden oak and a quiet deep forest-green inset provides the icon background, occupying about 88 percent of the square canvas. Rounded corners are stepped pixel corners, a restrained 1-2 layer pixel rim and pixel shadows add craft and depth. The finished icon sits centered with even transparent margin on all four sides. Everything forms one coherent app icon, no multiple variants or contact sheet.
Style/medium: crisp hand-crafted 2D pixel art with visibly square pixels, limited warm amber, chestnut brown, forest green and mint palette; detailed enough to feel charming, simple enough to be legible in the macOS Dock. Warm light from the upper left; limited pixel highlights and dark brown outlines, no vector gradients, no blur, no photorealism, no 3D toy, no glossy iOS blob, no perspective room miniature.
Text: none. No letters, no labels, no numbers, no logos, no watermark. No face or side profile. No farm-game copied assets. Transparent background beyond the rounded pixel icon tile; do not add a solid white canvas.
```
