# 门外访客

`pending-visitors.png` 是8位独立像素角色的透明图集，使用内置 imagegen 生成，随后执行透明背景提取。每行一种角色，6列依次为正面站立/迈步、左侧站立/迈步、背面站立/迈步；右侧使用对应左侧帧镜像。未修改室内员工的素材。

角色从上到下：紫发黄衫、白发工装、红辫绿衣、卷发红夹克、草帽园丁、银发紫裙、眼镜蓝夹克、双马尾粉衣。便签持久化slot决定角色，新增或移除其他访客不会让原角色换脸。

最终资源保存在本目录的 [pending-visitors.png](pending-visitors.png)，随源码提供并随app/saver打包。解码时清理低alpha边缘，保留源PNG。

## 生成提示词（内置工具）

```text
Use case: stylized-concept.
Asset type: production sprite atlas for a cozy Stardew Valley-inspired pixel RPG Mac desktop garden.
Generate ONE atlas of EIGHT DISTINCT adult village visitors. True transparent background. Exactly EIGHT ROWS and SIX COLUMNS, equal cells, generous clear gaps. A tall canvas 2048x3072 or similar portrait ratio. EACH ROW is a different character, each row has SIX full-body sprites of that same character at identical scale, feet baseline and head size. Crisp coarse 16-bit square pixel clusters, dark brown outlines, warm natural shading, compact cute RPG proportions roughly 2.5 heads tall. Actual side and back drawings, flat cardinal directions, slight top-down RPG camera, no diagonal facings. No text, labels, borders, grid lines, backgrounds, floor or cast shadows.
Characters by ROW top to bottom:
1: woman with dark purple bob haircut, mustard yellow cardigan over cream blouse, rust trousers and brown boots.
2: stocky older man with bald crown, white side hair and white moustache, blue work overalls over coral shirt, dark boots.
3: woman with long auburn braid, forest green coat and dark leggings, brown shoes.
4: young adult with curly black hair and medium-brown skin, red-orange jacket over white shirt and navy jeans.
5: man with a broad straw gardening hat, cream shirt with rolled sleeves, teal trousers and brown boots.
6: woman with silver hair in a round bun, violet long dress with cream apron and dark shoes.
7: young adult with dark short undercut hair, round glasses, cobalt jacket, pale trousers and brown shoes.
8: woman with two short blonde pigtails, dusty rose sweater, dark blue skirt over leggings, burgundy shoes.
Six columns in EVERY row (strict order):
col1: straight FRONT facing DOWN, neutral standing with arms at sides and feet close.
col2: same FRONT, small walking contact step with image-left leg forward and right leg back, mild opposing arm swing.
col3: true LEFT SIDE PROFILE, neutral standing. One eye/nose at LEFT, not three-quarter.
col4: same LEFT SIDE PROFILE, modest walking contact with separated legs and natural opposite arm swing.
col5: straight BACK facing UP, neutral standing, rear hairstyle and clothing, NO face.
col6: same BACK, modest walking contact with left leg forward and right leg back, opposite arm swing.
Every sprite entirely within its equal cell. All 48 are separate isolated cutouts with genuine transparent alpha between them. Keep each row's identity consistent over poses; distinct hairstyle, silhouette, body shape and outfit across all eight rows, not mere recolors. No furniture, screens, notes, speech bubbles, props held in hands or scenery. Do not merge figures or omit rows. Output a production atlas, not a promotional illustration.
```

## 背景提取提示词（内置工具）

```text
Use case: background-extraction.
Edit the provided eight-row six-column pixel visitor sprite atlas. Remove ALL of the brown/gray blurred colored backdrop, haze and glow between and around the figures; replace with genuinely empty fully transparent pixels alpha=0. Preserve all 48 character drawings, their exact placement, sizes, outlines, clothing, colors, faces and poses. Keep the eight rows and six columns intact. Nothing behind the people, no shadow, no colored studio gradient, no visible checkerboard pattern. Sharp clean pixel sprite edges. Pixel art cutouts only with actual transparent alpha outside each character. Output same 1024x1536 canvas. This is background removal only; do not redraw or rearrange any person.
```
