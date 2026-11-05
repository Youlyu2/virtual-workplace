# 全屏像素小屋素材

当前 0.7.0 运行素材由 Codex 内置 imagegen 基于用户确认的二维近景稿生成，随应用和系统屏保打包，本地运行无需图像服务。

优先使用 `flat-cabin-background.png`、`flat-desk-top.png`、`flat-garden-foreground.png`、`flat-distant-panorama.png` 和 `flat-room-window-cutout.png`。完整制作提示词见 [二维近景素材](FLAT_SCENE.md)。新房间不含固定人物、猫、桌子、屏幕或文字；原生动态层继续负责这些内容。新平面门槛替代藤蔓衔接，旧夜间底图和猫覆盖贴片不会叠到新素材上。

以下为旧素材及共用人物素材的记录，旧背景仅作回退：

- `cabin-background.png`：1672×941 房间底图。移除了人物、工作桌和显示器；时钟及今日看板保持空白，供实时图层填充。
- `outdoor-panorama.png`：0.6.1共享横向全景，两屏和房间玻璃按同一世界坐标裁切；[提示词](PANORAMA.md)。
- `room-window-cutout.png`：仅使用玻璃区域alpha，保留原房间颜色、窗框和藤叶。
- `scene-edge-ivy.png`：0.6.2透明前景衔接，包含藤叶、底部植物和细木边；按相邻屏幕的世界坐标裁剪并同步昼夜调色。[完整提示词](SEAM.md)。
- `outdoor-landscape.png`：独立全屏像素山谷；天气、云、水面和夜空由原生图层绘制。
- `cabin-background-night.png`：移除固定猫与阳光的同布局夜间灯光底图，昼夜过渡时混合；[素材及完整提示词](OUTDOORS.md)。
- `desk-top.png`：透明木桌与桌面物品，可随站姿上移；桌腿及抽屉由原生像素图层绘制。
- `employee-kit.png`：三列透明像素素材，依次为坐姿人物与椅子、站姿人物、空椅子。角色严格只露后脑与后背，睡觉后脑从站姿中裁取。
- `employee-actions.png`：四列透明背影动作素材，依次为喝咖啡、伸懒腰、挥手和逗猫；人物动作与真实任务信息分开绘制。
- `cat-kit.png`：三列橘白猫素材，包含趴睡、坐起和站立姿态，运行时独立绘制呼吸、尾巴、移动及互动反应。
- `rug-clean-patch.png`：固定猫所在区域的空地毯素材。运行时只在原猫所在小区域覆盖clean plate，再绘制独立猫，底图其他房间区域不作替换。
- 前版 `Resources/Characters` 仅为历史设计素材，当前全屏场景不再绘制3D卡通角色。

人物图集的透明边缘在解码缓存内执行像素透明度测试，以去掉低透明光晕；原 PNG 不被改写。人物、椅子、桌面与背景分层合成；任务信息、进度、日期、时钟和完成统计均为原生实时文字，不在 PNG 中写死。

0.4.0动作、猫和局部地毯素材的完整生成提示词见 [动画素材记录](ANIMATIONS.md)。下文保留原房间、桌面与基础人物的生成记录。

## 最终提示词

### 房间底图

Use case: precise-object-edit. Production background clean plate for an animated macOS pixel-art workspace. Edit the supplied approved concept image, preserving EXACTLY its room composition, camera, wide 16:9 framing, art style, color palette, window at left, sunlight, all decorative plants, shelves, rugs, sleeping cat on rug, side cabinets, and the EMPTY bed at far right. Keep the large wall-mounted wooden progress board at upper-right and wood clock plaque at top-right in exactly their existing locations, but REMOVE ALL WRITING, NUMBERS, ICONS AND CLOCK CONTENT from inside them: both their inner surfaces must be completely blank warm parchment/wood for runtime text. MOST IMPORTANT: REMOVE THE CENTRAL WORK DESK ENTIRELY, INCLUDING its drawers, desktop objects, keyboard, mouse, books, coffee cup, pen pot, ALL THREE monitors, all monitor stands, the employee and the employee's rolling chair. Replace the removed central desk area naturally with the underlying matching cream cabin wall above and warm plank floor below, continuous with the surrounding room, no holes or transparent gaps. We will put the work desk, all its objects, monitors, actor, chair and text back as separately animated layers in code. Retain the SMALL side cabinets left/right at the room edges and right cabinet beside the bed, but NOT the main center work desk. There should be a spacious empty central wall/floor stage, roughly x25%..77%, y25%..74%, without new furniture, no new props, no duplicate chairs or desks. Preserve the pixel-art low-resolution square clusters, dark brown outlines, rich amber wooden floor, warm green palette, handcrafted 16-bit RPG feel; no 3D, no smooth vector art. Bed must remain EMPTY with white pillow and teal quilt, no sleeping human. No characters, no readable letters or numerals anywhere on room signs, no UI, no labels, no watermark. Match the original wide image geometry as closely as possible; avoid moving the bed/window/cork board/clock because dynamic overlays will align to their original locations. Return one full opaque 16:9 clean background image, not a design board and not separate panels.

### 可升降桌面

Use case: background-extraction / game sprite asset. From the supplied pixel-art cabin office reference, extract and redraw ONLY THE CENTRAL WOODEN DESK'S TABLETOP as a standalone transparent pixel-art game sprite. Preserve the exact 16-bit pixel-art style, warm honey-brown wood grain, dark brown pixel outlines, warm sunny lighting, slightly top-down frontal view seen from behind the employee. Keep the wide horizontal desktop surface and its thick front edge, with small original desktop objects arranged naturally: a couple of books and coffee cup on left, small keyboard at center-back, mouse, pen cup and notebook on right. REMOVE ALL THREE MONITORS AND THEIR STANDS, ALL TEXT OR UI, THE CHARACTER, THE CHAIR, THE DESK LEGS, ALL DRAWER UNITS, ALL FLOOR AND ROOM BACKGROUND. Absolutely no monitor fragments, no human hair or hands, no plants rising into monitor area. This sprite will move vertically as an adjustable desk, while the legs are drawn separately at runtime. One clean wide horizontal tabletop with 4:1 aspect silhouette, not an atlas or scene. True transparent alpha everywhere outside the desktop and small objects. Keep its front edge straight and horizontal and back edge slightly narrower, mild classic RPG desk perspective, not strongly isometric. No cast shadow on ground, no labels, no watermark, no smooth 3D rendering. Maintain visible square pixel clusters. The tabletop will span about 900 pixels in a 1672-wide room, so desktop objects must be small. Transparent output should have generous margins so no object is clipped.

### 像素人物与椅子

Use case: game sprite asset extraction and pose design. The reference is the APPROVED pixel-art room. Create a TRUE 2D 16-BIT PIXEL ART sprite sheet of the TINY WORKER AT THE DESK in this exact design style. This must be crisp, hand-placed square pixel clusters like a classic Stardew Valley-inspired RPG farmer. NOT a smooth illustration, NOT 3D, NOT a big-headed toy, NOT a realistic person. Character normal compact RPG proportions: head about 1/4 to 1/3 height, brown rear hair with small detailed pixel highlights, muted green hoodie/shirt, dark navy pants, brown shoes. Strict direct REAR view in every sprite: no face, no eyes, no side profile, no turning. One transparent PNG with THREE EQUAL SQUARE COLUMNS, each isolated full sprite centered in its own column with large transparent margins. LEFT COLUMN: the worker SITTING UPRIGHT WORKING IN THE OFFICE CHAIR, viewed directly from behind, both hands raised naturally forward at an invisible desk, normal stable feet. Include the entire cozy wooden-framed chair with green upholstered rear cushion and small black rolling base, matching the approved room reference. Character's green shoulders/upper back and entire hair clearly visible above the chair back. No desk or keyboard in sprite. MIDDLE COLUMN: exactly the same worker STANDING UPRIGHT WORKING at an invisible standing desk, hands forward at chest level, both feet grounded, no chair, same hair and outfit, same head width/physical character scale as sitting. RIGHT COLUMN: the EMPTY OFFICE CHAIR from the left column, matching exactly its size and angle, same rear wood frame, green cushion and black rolling base, no person. Align all shoes/chair wheels to the SAME baseline near bottom of the atlas. All three figures fully inside own cell; no fragments from neighboring cells, no room, no desk, no monitor, no floor, no cast shadow, no text, no labels, no borders or watermark. Pixel character must look charming and professionally drawn with rich but limited warm palette, dark brown pixel outlines, subtle dithered shading, stepped highlights. Deliberately coarse pixel grid (about 32x56 logical pixels for the standing character) upscaled with nearest-neighbor; absolutely no fuzzy edges or dense realistic detail. This is production sprite art for the approved cozy wooden office wallpaper. Genuine alpha transparency outside silhouettes.
