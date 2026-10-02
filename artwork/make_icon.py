"""加賀梅鉢を幾何形状で描く。アプリのビルドは行わない。"""
from pathlib import Path
from math import cos, sin, pi
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent.parent
scale = 3
size = 1024
background = (24, 28, 34)
gold = (218, 181, 91)
image = Image.new('RGB', (size * scale, size * scale), background)
draw = ImageDraw.Draw(image)
center = (512, 512)
petal_centers = [(512 + 258 * cos(-pi / 2 + n * 2 * pi / 5),
                  512 + 258 * sin(-pi / 2 + n * 2 * pi / 5)) for n in range(5)]
def disk(point, radius, fill):
    x, y = point
    draw.ellipse(tuple(v * scale for v in (x-radius, y-radius, x+radius, y+radius)), fill=fill)
# 梅鉢の五つの円形の花弁と、中心から伸びる花糸。
for point in petal_centers:
    draw.line(tuple(v * scale for v in (*center, *point)), fill=gold, width=18 * scale)
    disk(point, 122, gold)
disk(center, 62, gold)
image.resize((size, size), Image.Resampling.LANCZOS).save(root / 'kanazawa01/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
# 元の図形も保存し、将来の色・サイズ変更を可能にする。
shapes = []
for x, y in petal_centers:
    shapes.append(f'<path d="M512 512 L{x:.3f} {y:.3f}" stroke="#dab55b" stroke-width="18"/>')
    shapes.append(f'<circle cx="{x:.3f}" cy="{y:.3f}" r="122"/>')
svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n<rect width="1024" height="1024" fill="#181c22"/>\n<g fill="#dab55b">\n' + '\n'.join(shapes) + '\n<circle cx="512" cy="512" r="62"/>\n</g>\n</svg>\n'
(root / 'artwork/AppIcon.svg').write_text(svg)
manifest = {'images': [{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}], 'info': {'author':'xcode','version':1}}
(root / 'kanazawa01/Assets.xcassets/AppIcon.appiconset/Contents.json').write_text(json.dumps(manifest,indent=2)+'\n')
