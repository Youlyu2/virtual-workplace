# 二维近景素材（0.7.0）

基于用户批准的 `designs/pixel-workplace-flat-approved.png`，通过 Codex 内置 imagegen 生成。未使用 CLI/API。近景使用二维平行格网，山谷继续使用共享全景相机；人物、猫、屏幕任务、时钟和进度由原生实时图层绘制。

- `flat-cabin-background.png`：无桌、屏幕、人物、猫与文字的独立房间底图，牌框留白，无固定阳光。原 `cabin-background`/night/rug patch 为旧版回退，不叠加到新素材。
- `flat-garden-foreground.png`：带透明通道的树、横向栅栏和水平小路前景；远山与天气在独立世界图层中绘制。
- `flat-distant-panorama.png`：无近景树、栅栏和固定云朵的横向远景，供室外与窗玻璃共用。
- `flat-room-window-cutout.png`：只使用玻璃透明度，保留新窗框、窗帘及花叶。
- `flat-desk-top.png`：带透明通道的矩形桌面和道具；与站姿同步升降，键鼠及人物位置不变。

## 运行时组合

新背景、庭院前景与窗玻璃分别绘制。庭院近景不进入窗玻璃的远景 pass，路径与门槛共享原生 y=110…220；门槛为 32 像素宽的原生平面石条。桌面使用原有 x=400、y=402 的锚点与 900×128 固定绘制框，屏幕及人物位置不变。

透明素材在解码缓存中清除 alpha≤8 的导出残留，严格纯红/纯绿键色仅在与透明区域连通时清除，保留原 PNG、暖色木材和花草。窗玻璃只取透明度，并与平行窗格几何范围相交；1671×941 的导出会归一到房间的 1672×941 坐标，避免一像素尺寸差导致整张遮罩失效。

## 房间生成提示词

Use case: precise-object-edit. PRODUCTION CLEAN BACKGROUND ASSET for a 2D pixel-art Mac app. The input is the user-approved double-screen concept. Return ONLY THE RIGHT HALF ROOM, defined precisely by source x=1086..2172 and y=56..666, as a standalone opaque 16:9 image, target 1672x941. Remove the black bars and left garden entirely. Do NOT recenter or recompose objects within that right-half crop. Same warm detailed 16-bit 2D farming-game art, strictly horizontal/vertical orthographic furniture and floor grid, no receding sidewalls.
Keep the front-facing window at far-left, shelves and paintings above, warm cream back wall, horizontal floorboards, rectangular teal rug, small bedside cabinet and EMPTY teal bed at far right, and original wooden frames of progress board and clock at upper right. Their positions remain EXACTLY as in the requested right-half crop.
REMOVE ALL dynamic layers: the entire central desk, its drawers/legs/tabletop/objects, all three monitors and their stems, person, chair, sleeping cat, status strip on rug, and ALL letters, numbers, symbols or text inside the progress board and clock. Fill their removed areas with matching continuous blank wall or flat floor/rug. No replacement furniture in the large empty central stage. Rug has no animal. The signs have blank parchment/wood interiors.
Window must remain a front-facing RECTANGULAR 3x3 grid, all mullions aligned to pixel axes; preserve the scenery visible through its glass for fallback. Keep window glass mostly unobstructed; plants and sill only at bottom edge; curtain lies beside the glass at left. No plants intruding across the middle panes. Neutral daylight WITHOUT baked sunbeams, diagonal cast shadows, weather/cloud sprites, stars or actual sun. All temporal lighting is drawn in code.
Room coordinate system after scaling is 1672x941, bottom-left origin. Keep empty desktop stage x400..1300 y275..735, bed far-right x~1430..1672. The rug stays x~430..1260 y0..235, entirely rectangular. Leave the left edge of wood floor fully open at y110..220: no vertical post, raised doorjamb, stone pillar, foliage or furniture across this passage. No exterior porch or door facade. The app draws a flat doorway threshold separately.
Return exactly one FULL-BLEED opaque 16:9 room background asset. No split panels, black bands, inset, crop marks, UI, labels, letters, fake transparency, characters, desk or monitors. This image is just the environment layer; native moving sprites and live text will be composited back in their fixed original coordinates.

## 庭院前景生成提示词

Use case: background-extraction. Production TRUE TRANSPARENT foreground sprite for a 2D farming-game panorama. Extract/adapt ONLY the near garden from the LEFT HALF of the input approved concept, preserving its flat 2D game-map projection. Return a standalone 16:9 transparent PNG, target 1672x941. The sprite represents the left display's near garden layer; distant mountains/valley/river/sky will be drawn separately behind it.
Keep the large tree anchored at the FAR LEFT edge and rising to the top, with trunk roots, green pixel foliage and a few near rocks. Keep a straight horizontal wooden fence spanning most of the width behind the path, small flower clumps/grass, and the horizontal dirt walkway. REMOVE ALL mountains, distant forests, farmhouses, river, sky, clouds, room/wall/window, and doorway stone tiles, leaving TRUE ALPHA TRANSPARENCY in their place, including all openings between fence rails.
GEOMETRY is critical: coordinates after scaling are 1672x941 bottom-left origin. Fill lower y0..280 with flat near grass/soil. The walkable dirt path is a perfectly horizontal, constant-width band across the ENTIRE width, x0..1672, y110..220; both ends remain open and at identical height. Fence base is near y280, fence top/posts near y390. Small grass/flower silhouettes may extend to y~300. Except for the tree at far left, EVERYTHING ABOVE y400 is transparent. Tree top may rise to y941; rightmost 15% must contain NO tree, post blocking walkway, vertical wall or large plant. Grass meets path naturally with irregular pixel edges, no diagonal route, depth scaling, vanishing points, diamond tile grid, steps or ramp. Strict 2D tilemap, upright tree/fence sprites, all similar-sized flowers remain same pixel scale.
Same saturated warm hand-drawn pixel clusters as the reference. Neutral even daytime lighting, no weather, sun, moon, night tint or long shadows. Do not paint a sky/background or checkerboard. Full 16:9 sprite with upper empty regions really transparent. It will be overlaid on an independently animated scenic background, so preserve genuine alpha around every tree leaf and through fence gaps.

## 桌面生成提示词

Use case: precise-object-edit / background-extraction. Production transparent pixel-game tabletop sprite. Reference1 is the EXISTING desktop sprite; reference2 is the approved NEW 2D scene. Redraw reference1's tabletop in the flat 2D tilemap projection of reference2.
Return just the horizontal wooden tabletop and existing small objects on TRUE TRANSPARENT ALPHA. Its silhouette is a long AXIS-ALIGNED RECTANGLE, parallel equal-length front/back edges, vertical short ends; NO trapezoid, convergence or diagonal side faces. Thick horizontal dark wooden front edge. Trimmed silhouette width:height about 7:1 (runtime draw900x128). Keep original props at approximately same relative positions: left books/open notebook/coffee cup, keyboard centered, mouse a little right of center, notepad/pen cup/phone on right. Remove baked sun streaks/shadows. Keep rich pixel woodgrain, warm honey wood, stepped dark-brown pixel outlines, 2D sprite shading matching approved cozy room.
NO desk legs, drawers, floor, wall, monitors or stems, person, hands, chair, cats, labels, scenery or cast ground shadow. Genuine transparent background. Fully isolated asset with some transparent margin. The entire tabletop will translate up when the user stands; all other objects are separate render layers. Preserve prop proportions and existing keyboard/mouse locations as much as possible; only flatten the tabletop perspective.

## 窗玻璃 alpha 提示词

Use case: background-extraction. Production exact alpha stencil. Edit the attached 1672x941 flat 2D room background. Keep every pixel of the whole room opaque and in exactly the same position, but make ONLY the visible sky, mountains and valley seen THROUGH THE NINE WINDOW GLASS PANES at left into GENUINE ALPHA TRANSPARENCY. This is not a room redesign. Window approximately x90..400,imageY175..410. Keep all window frames, thin mullions, wooden sill, left curtain, hanging leaves and every potted plant/flower overlapping the bottom panes FULLY OPAQUE. Precisely trace transparent holes around these foreground objects; do not erase the flowers. All other walls, flooring, blank signs, rug, bed and furniture remain opaque and unchanged. SAME1672x941 canvas, no margin, no letterbox, no crop, no object movement. No characters, text, monitors or desk. Genuine alpha=0 in window glass holes, not black/white/checkerboard painted over glass. Full-room image, only glass cut out. Used as alpha only by renderer.

## 纯远景全景提示词

Use case: precise-object-edit / panorama background layer. The reference is the approved pixel-art room/garden composition. Produce ONLY a wide continuous DISTANT MOUNTAIN AND RIVER VALLEY landscape background, a full-bleed opaque 3:1 panorama. This is the distant layer behind a separate 2D garden foreground; remove ALL room, house interior, large foreground tree, foreground fences, garden path, flowers, large rocks, near bushes, bridge, landing and UI. Do not include any near foreground framing at any edge.
Retain the approved left-side landscape language: broad calm pale-blue sky at upper 25%, layered blue mountain ranges and forests, rolling green fields, small amber crop fields, a winding turquoise river and a few TINY distant red-roof farmhouses. Extend the same valley continuously across the entire ultrawide panorama with coherent horizon and scale, no repeated halves or seams. Natural depth, atmospheric perspective and softly diminishing distant detail, in the SAME crisp handcrafted pixel-art medium (not photorealistic 3D).
Bottom of image is more distant/mid-distance valley pasture and river, NOT a nearby walking surface or foreground embankment. No objects large enough to compete with the separately layered garden tree. Neutral even daytime, no sun, moon, stars, clouds, precipitation, shadows sweeping across the image, letters or labels. Runtime will add weather/day-night. One seamless opaque panorama, edge to edge, no black bars, no frames, no room, no characters.

生成后的云朵由以下第二次内置 imagegen 编辑移除，最终素材为 `flat-distant-panorama.png`：

Edit this exact pixel-art panoramic valley image. Remove ONLY all white clouds from the sky and replace their pixels naturally with the uninterrupted existing clear blue sky. The entire sky must have ZERO clouds, stars, sun, moon, weather, labels or sprites; the app adds those dynamically. Preserve mountain contours, farms, forests, river, fields, positions, colors, pixel-art texture and same exact 3:1 canvas. No landscape alterations, no resizing, no framing, no other edits. Output fully opaque edge-to-edge panorama.
