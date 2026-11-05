# 手动动作与像素猫素材

使用内置 imagegen 生成，2026-10-29。源 PNG 随包提供；动作插值与身体、手臂、猫尾动画由原生渲染器完成。素材本身不包含任务或进度数据。

- [employee-actions.png](employee-actions.png)：四列人物动作，喝咖啡、伸懒腰、挥手、逗猫。严格背影，无桌椅。
- [cat-kit.png](cat-kit.png)：三列橘白猫，趴睡、坐起、站立。
- [rug-clean-patch.png](rug-clean-patch.png)：只用于替换原底图固定猫所在的小块地毯，对应原1672×941房间的世界坐标(x:500,y:55,width:220,height:135)，房间其他像素保持原素材。

## 四方向步行素材

- [employee-walk.png](employee-walk.png)：使用内置 imagegen 生成并经两次定向修正的透明四行四列步行图集，2026-10-29。行顺序为正面向下、左侧、右侧、背面向上；每行四个步态帧。正面和背面接触帧包含交替的左右领先脚，侧面包含对应的手臂摆动。
- 最终源图尺寸1086×1448，真实alpha。运行时按实际透明行间隙分割、以头部中心作水平锚点、统一身体缩放，以鞋底为地面基线；距离每20世界像素切帧，停步使用中立帧。
- 最终图集保存为本目录的 [employee-walk.png](employee-walk.png)，随源码提供并参与应用资源打包；未选迭代不随包发布。

### 初始四方向图集提示词

```text
Use case: stylized-concept.
Asset type: production sprite sheet for a native 16-bit pixel-art cozy Mac room.
Input image: employee-kit.png is ONLY a character identity and pixel-style reference. Generate a NEW asset, not an edit of that sheet.
Primary request: the SAME shaggy brown-haired adult worker wearing a forest-green hoodie, navy trousers and brown shoes in FOUR cardinal walking directions, real front and real side drawings. Match the reference's compact RPG adult proportions and crisp square pixel texture, warm restrained earthy colors and dark brown outlines. No smooth illustration or 3D.

Composition: one TRUE TRANSPARENT PNG containing exactly FOUR ROWS and FOUR COLUMNS (16 separate full-body sprites), ideally 1536 wide by 2048 high. Every cell equal size with generous fully transparent gaps. All characters same physical size and same feet baseline within each row, head and torso stable between walking frames. Every sprite entirely inside its cell. Use a normal classic RPG camera, slight view from above, NEVER diagonal or 3/4 facings.

ROW 1 (top): DOWN, straight FRONT view toward viewer, simple tiny pixel face, two eyes, hoodie front. Four walk-cycle frames.
ROW 2: LEFT, TRUE 90-DEGREE SIDE PROFILE looking and walking left. One visible eye/nose facing left, not a back view.
ROW 3: RIGHT, TRUE 90-DEGREE SIDE PROFILE looking and walking right. One visible eye/nose facing right, not a back view.
ROW 4 (bottom): UP, straight BACK view walking away, rear hair and hoodie hood matching reference.

COLUMN 1 in every row: neutral passing pose, feet together/near together, arms relaxed.
COLUMN 2: one clear walking contact pose, left leg forward/right leg back, opposite natural arm swing.
COLUMN 3: opposite passing pose with feet near center.
COLUMN 4: opposite walking contact, right leg forward/left leg back and reversed arm swing.
Legs articulate naturally at hip/knee, shoes stay coherent. Side-view stride is clearly distinct in columns2/4. Keep all four frames narrow, no high-kicking. Hands naturally down beside waist, never raised near ears.

Constraints: TRUE TRANSPARENT alpha everywhere outside the sprites. NO background, checkerboard painted into pixels, ground shadow, glow, chair, desk, props, cat, text, labels, arrows, frame borders, scenery or extra people. No copies of seated pose. Exactly4rows×4columns. Do not shrink individual frames or change clothing/head size between poses. All sixteen are ONE same character.
```

### 对侧步态修正提示词

```text
Use case: precise-object-edit. Edit target: the supplied transparent4×4walking sprite sheet. Preserve the exact same character, pixel art style, colors, face/hair/hoodie/body size, allrowdirections and grid placement, and preserve true transparency.

Make ONLY ONE targeted walking-cycle correction: in the FOURTH COLUMN of EVERY row (rightmost sprite), redraw the arms and legs as the OPPOSITE LEG AND ARM PHASE from that row's SECOND COLUMN. Do not duplicate column2's leading foot.

Specifically FRONT row1: column2 currently has the IMAGE-RIGHT shoe lower/forward. In column4 put the IMAGE-LEFT shoe lower/forward and IMAGE-RIGHT shoe lifted/back, with opposite arm swing. Keep head/torso unchanged.
BACK row4: column2 currently has IMAGE-RIGHT shoe lower/forward. In column4 put IMAGE-LEFT shoe lower/forward and IMAGE-RIGHT shoe lifted/back, opposite arm swing. Keep rear hair/hood unchanged.
LEFT-PROFILE row2: column4 must swap which anatomical leg crosses in front and which arm swings toward the LEFT compared with column2. A distinct opposite contact pose, still facing exactlyleft.
RIGHT-PROFILE row3: column4 must swap which anatomical leg crosses in front and which arm swings toward the RIGHT compared with column2. A distinct opposite contact pose, still facing exactlyright.

Columns1,2,3 are invariants, leave them unchanged. Column4 headandtorso size/topposition must also remain unchanged. Allshoes contact the same rowgroundbaseline, no vertical drift, no new props, no text, no shadows/glow/background. Crisp coarse16bitpixelclusters, no smoothing. Outputsame4rows×4columns PNG, genuinelytransparentalphaoutsidecharacters.
```

### 最终正面领先脚修正提示词

```text
Use case: precise-object-edit. The supplied image is a4rows×4columns transparent pixel RPG walking sprite sheet. Change ONLY the legs below the hoodie of the TOP-RIGHT person (row1column4). That one person's IMAGE-LEFT brown shoe MUST extend LOWER than the IMAGE-RIGHT brown shoe. Put IMAGE-LEFT leg straight forward with its shoe at the lowest bottom baseline. Bend and lift IMAGE-RIGHT knee/shoe BACK AND UP visibly above that baseline. This must be the exact opposite of the other front-facing stepping person in row1column2, whose IMAGE-RIGHT shoe is lowest. Mirror the leg action horizontally, not the head. Keep both shoes brown, trousers navy, the pants continuous to the hoodie waist. All other15persons are exact invariants; do not change them. Do not change top-right head, face, hair, hoodie or arms. Keep existingcanvas/grid/scale/transparent alpha. No added background, text, label, shadow,glow or scenery. Exactly one repaired leg phase, clear image-left foot forward and image-right foot back.
```


## 最终生成提示词

### rug_patch

```text
Use case: precise-object-edit. Edit target: the supplied small pixel-art rug crop. Remove ONLY the orange-and-white sleeping cat and its dark cast shadow. Reconstruct the green and gold woven rug pattern underneath the cat, matching the surrounding exact tile scale, grain, golden light and perspective. Preserve every existing rug border, color and pixel outside the cat as closely as possible. This is an EMPTY RUG CLEAN PLATE for replacing a baked cat with an independently animated sprite. One rectangular texture patch with exactly the same crop and framing, original crop ratio 220:135, no new objects, no animal, no text, no blur, no invented furniture. Handcrafted crisp 16-bit RPG pixel pattern. OPAQUE image, not transparent.
```

### cat_kit

```text
Use case: game sprite asset. The supplied crop is the reference for ONE small orange tabby with white muzzle/chest/paws in a cozy Stardew Valley-inspired 16-bit pixel room. Extract and redraw the SAME charming cat as a transparent THREE EQUAL COLUMN sprite sheet, preferably 1536 by 1024, three separate poses with wide transparent gaps and same physical scale and ground baseline. LEFT: curled sleeping cat, head at right, eyes closed, white front paws in front, orange striped back; MIDDLE: same cat sitting upright awake, head facing to the RIGHT, big attentive but small pixel eyes and white chest, ears perked; RIGHT: same cat standing on all four paws and facing RIGHT in a side-to-slight-top view. All tails on LEFT of body, clearly separated and behind body where possible so we can animate tail separately. Consistent orange tabby stripe pattern, white muzzle and belly, brown pixel outline, warm upper-left sunlight; logical sprite density around48 by40 pixels per cat, upscaled crisp square pixel clusters, absolutely no smooth 3D. Character only, no ground shadow, no rug, no room, no marks, no text, no frames, no margins with painted texture. True transparent alpha outside cats, not a colored studio glow. Three poses fully in respective equal-width cells, no cat fragments across cells.
```

### employee_actions

```text
Use case: game sprite pose sheet. The provided employee-kit.png is the exact character style reference. Create ONE TRUE TRANSPARENT PNG with FOUR EQUAL WIDTH COLUMNS, ideally2048 by1024, each one complete fullbody pose of the SAME brown-haired adult worker, strictly DIRECT REAR VIEW, forest-green hoodie, navy trousers, brown shoes, compact classic 16-bit Stardew Valley-inspired RPG proportions. Preserve the reference's character body/head size ratio, garment shading and pixel outlines. NO chair, NO desk, NO furniture, NO background, NO text, NO floor shadow or glow. Each of four people same physical scale, same exact shoe baseline near bottom, centered in own cell, generous empty gap and room above hands, no cropping. COLUMN1 COFFEE: relaxed standing, right elbow bent and right hand holding a small cream coffee mug beside the right back of head, cup clearly separate from hair silhouette; left arm relaxed. COLUMN2 STRETCH: same worker standing, both arms reaching upward in a comfortable overhead stretch, both hands separate from head, slight outward angle, rear hair remains visible between arms. COLUMN3 WAVE: worker standing, right upper arm out and right forearm/hand raised near above shoulder height, open palm seen from behind at right, the whole waving hand and sleeve separate from head, left arm down. COLUMN4 PLAY WITH CAT: standing worker backview leaning slightly to the LEFT, left arm extended down/out to left with dangling small simple cat teaser ribbon, right arm relaxed; shoes remain planted. All faces invisible, no eyes/side profile/turning toward viewer. Character should look professionally drawn as an upscaled hand-placed coarse pixel sprite, not smooth digital painting or3D toy. Rich but restrained warm earthy palette. Four full characters only, exactly four columns, no separators.
```
