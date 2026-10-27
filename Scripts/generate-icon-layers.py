#!/usr/bin/env python3
"""Writes the app icon's layers (blades.svg, hub.svg) into the given directory.

Usage: Scripts/generate-icon-layers.py App/Resources/AppIcon.icon/Assets
The background gradient and Liquid Glass settings live in AppIcon.icon/icon.json.
"""
import math, sys
out = sys.argv[1]
C = 512.0

def polar(r, deg):
    a = math.radians(deg - 90)  # 0° points up
    return C + r * math.cos(a), C + r * math.sin(a)

def fmt(p):
    return f"{p[0]:.1f} {p[1]:.1f}"

def blade(offset):
    # Narrow root at the hub, a wide swept tip; leading edge concave, trailing edge convex.
    root_a = polar(96, offset - 16)
    root_b = polar(96, offset + 16)
    tip_lead = polar(330, offset + 22)
    tip_trail = polar(318, offset + 70)
    return " ".join([
        "M", fmt(root_a),
        "C", fmt(polar(200, offset - 6)), fmt(polar(300, offset + 2)), fmt(tip_lead),
        "C", fmt(polar(352, offset + 38)), fmt(polar(350, offset + 58)), fmt(tip_trail),
        "C", fmt(polar(250, offset + 64)), fmt(polar(150, offset + 40)), fmt(root_b),
        "Z",
    ])

blades = "\n".join(f'  <path d="{blade(i * 72)}" fill="#FFFFFF"/>' for i in range(5))
open(f"{out}/blades.svg", "w").write(f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
{blades}
</svg>
''')
open(f"{out}/hub.svg", "w").write('''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <circle cx="512" cy="512" r="108" fill="#FFFFFF"/>
</svg>
''')
