# CasaPlay tvOS brand assets generator. Designed by 𝐂𝓪sΔηⓞשα.
# Usage: python3 Scripts/make_tv_assets.py <path to Assets.xcassets>
import sys, os, json, math, colorsys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

CAT = sys.argv[1]
BRAND = os.path.join(CAT, "App Icon & Top Shelf Image.brandassets")
INFO = {"author": "xcode", "version": 1}
BG = (7, 8, 11)
AMBER = (240, 166, 70)
WHITE = (243, 241, 236)
SEC = (169, 171, 177)
FONT_BOLD = "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf"
FONT_MED = "/usr/share/fonts/opentype/inter/InterDisplay-Medium.otf"
SS = 2  # supersampling factor


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")


def glow_background(w, h, center=(0.72, 0.15), radius=0.75, strength=95):
    img = Image.new("RGB", (w, h), BG)
    glow = Image.new("L", (w, h), 0)
    cx, cy = center[0] * w, center[1] * h
    r = radius * max(w, h) * 0.5
    ImageDraw.Draw(glow).ellipse((cx - r, cy - r, cx + r, cy + r), fill=strength)
    glow = glow.filter(ImageFilter.GaussianBlur(r * 0.45))
    return Image.composite(Image.new("RGB", (w, h), (120, 70, 20)), img, glow)


def house_geometry(cx, cy, size):
    """size = house height. Returns outer, inner polygons and inner box."""
    h = size
    w = h * 0.97
    top = cy - h / 2
    base = cy + h / 2
    eave = top + h * 0.40
    t = h * 0.092
    left, right = cx - w / 2, cx + w / 2
    a = math.atan((eave - top) / (w / 2))
    outer = [(left, eave), (cx, top), (right, eave), (right, base), (left, base)]
    ipy = top + t / math.cos(a)
    iey = ipy + (cx - (left + t)) * math.tan(a)
    inner = [(left + t, iey), (cx, ipy), (right - t, iey), (right - t, base - t), (left + t, base - t)]
    return outer, inner, (eave, base - t, t)


def draw_house(layer, cx, cy, size):
    outer, inner, _ = house_geometry(cx, cy, size)
    mask = Image.new("L", layer.size, 0)
    md = ImageDraw.Draw(mask)
    md.polygon(outer, fill=255)
    md.polygon(inner, fill=0)
    layer.paste(Image.new("RGBA", layer.size, AMBER + (255,)), (0, 0), mask)


def draw_play(layer, cx, cy, size):
    _, _, (eave, floor, t) = house_geometry(cx, cy, size)
    th = size * 0.34
    tx = cx - th * 0.293
    ty = (eave + floor) / 2 + size * 0.02
    ImageDraw.Draw(layer).polygon([(tx, ty - th / 2), (tx, ty + th / 2), (tx + th * 0.88, ty)], fill=WHITE + (255,))


def down(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


# ---------- App icon image stacks (Back / Middle / Front) ----------

def icon_layers(w, h):
    W, H = w * SS, h * SS
    back = glow_background(W, H).convert("RGBA")
    # house sized to stay inside the safe zone when tvOS scales and crops on focus
    size = H * 0.56
    cx, cy = W / 2, H * 0.5
    middle = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_house(middle, cx, cy, size)
    front = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_play(front, cx, cy, size)
    return {"Back": down(back.convert("RGB"), w, h), "Middle": down(middle, w, h), "Front": down(front, w, h)}


def write_stack(name, sizes):
    """sizes: list of (scale, w, h)."""
    stack = os.path.join(BRAND, name + ".imagestack")
    order = ["Front", "Middle", "Back"]
    write_json(os.path.join(stack, "Contents.json"),
               {"info": INFO, "layers": [{"filename": n + ".imagestacklayer"} for n in order]})
    rendered = {scale: icon_layers(w, h) for scale, w, h in sizes}
    for n in order:
        layer_dir = os.path.join(stack, n + ".imagestacklayer")
        write_json(os.path.join(layer_dir, "Contents.json"), {"info": INFO})
        imgset = os.path.join(layer_dir, "Content.imageset")
        images = []
        for scale, w, h in sizes:
            fn = f"{n.lower()}@{scale}.png" if scale != "1x" or len(sizes) > 1 else f"{n.lower()}.png"
            os.makedirs(imgset, exist_ok=True)
            rendered[scale][n].save(os.path.join(imgset, fn))
            images.append({"filename": fn, "idiom": "tv", "scale": scale})
        write_json(os.path.join(imgset, "Contents.json"), {"images": images, "info": INFO})
    return rendered


# ---------- Top Shelf ----------

POSTERS = [
    (24, "THE LAST FERRY"), (205, "NORTHERN LIGHT"), (340, "VELVET HOUR"),
    (150, "HIGH COUNTRY"), (265, "SIGNAL"), (35, "SALT & STONE"),
    (190, "DEEP WATER"), (5, "EMBER"), (290, "NIGHT TRAIN"),
]


def poster(w, h, hue, title, radius):
    base = hue / 360
    def hsv(s, v):
        r, g, b = colorsys.hsv_to_rgb(base, s, v)
        return (int(r * 255), int(g * 255), int(b * 255))
    top, bot = hsv(0.55, 0.34), hsv(0.45, 0.08)
    sw, sh = 32, 48
    small = Image.new("RGB", (sw, sh))
    px = small.load()
    for y in range(sh):
        for x in range(sw):
            t = min(1, max(0, (y / (sh - 1)) * 0.75 + (1 - x / (sw - 1)) * 0.25))
            px[x, y] = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    img = small.resize((w, h), Image.BICUBIC)
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.25, -h * 0.25, w * 1.2, h * 0.55), fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.2))
    img = Image.composite(Image.new("RGB", (w, h), hsv(0.5, 0.95)), img, glow)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_BOLD, int(w * 0.075))
    words = title.split(" ")
    lines = [" ".join(words[:2])] if len(words) <= 2 else [" ".join(words[:-1]), words[-1]]
    if len(words) <= 2:
        lines = [title]
    y = h - w * 0.12 - len(lines) * w * 0.1
    for line in lines:
        tw = d.textlength(line, font=font)
        d.text(((w - tw) / 2, y), line, font=font, fill=(235, 235, 235))
        y += w * 0.1
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    return img, mask


def top_shelf(w, h):
    W, H = w * SS, h * SS
    img = glow_background(W, H, center=(0.18, 0.2), radius=0.9, strength=80).convert("RGBA")

    # poster wall on the right, fading into the background on its left edge
    ph = int(H * 0.66)
    pw = int(ph / 1.5)
    gap = int(pw * 0.09)
    radius = int(pw * 0.06)
    start_x = int(W * 0.58)
    y0 = (H - ph) // 2
    wall = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = start_x
    i = 0
    while x < W:
        hue, title = POSTERS[i % len(POSTERS)]
        p, m = poster(pw, ph, hue, title, radius)
        # alternate small vertical offsets for rhythm
        dy = int(ph * 0.05) * (1 if i % 2 else -1)
        wall.paste(p, (x, y0 + dy), m)
        x += pw + gap
        i += 1
    fade = Image.new("L", (W, H), 0)
    fd = ImageDraw.Draw(fade)
    fade_from, fade_to = start_x - pw * 0.2, start_x + pw * 1.3
    for xx in range(W):
        a = 0 if xx < fade_from else min(1, (xx - fade_from) / (fade_to - fade_from))
        fd.line([(xx, 0), (xx, H)], fill=int(255 * (a ** 1.4) * 0.9))
    wall_alpha = wall.getchannel("A")
    from PIL import ImageChops
    wall.putalpha(ImageChops.multiply(wall_alpha, fade))
    img.alpha_composite(wall)

    # logo + wordmark on the left
    mark = H * 0.30
    mx = W * 0.075 + mark * 0.5
    my = H * 0.42
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_house(layer, mx, my, mark)
    draw_play(layer, mx, my, mark)
    img.alpha_composite(layer)
    d = ImageDraw.Draw(img)
    word = ImageFont.truetype(FONT_BOLD, int(H * 0.15))
    tx = mx + mark * 0.5 + H * 0.06
    d.text((tx, my), "Casa", font=word, fill=WHITE, anchor="lm")
    cw = d.textlength("Casa", font=word)
    d.text((tx + cw, my), "Play", font=word, fill=AMBER, anchor="lm")
    tag = ImageFont.truetype(FONT_MED, int(H * 0.05))
    d.text((W * 0.075, my + mark * 0.5 + H * 0.12), "Your movies in 4K, from your Mac, NAS or media server.",
           font=tag, fill=SEC, anchor="lm")
    return down(img.convert("RGB"), w, h)


def write_shelf(name, w, h):
    imgset = os.path.join(BRAND, name + ".imageset")
    os.makedirs(imgset, exist_ok=True)
    images = []
    for scale, f in (("1x", 1), ("2x", 2)):
        fn = f"{name.lower().replace(' ', '-')}@{scale}.png"
        top_shelf(w * f, h * f).save(os.path.join(imgset, fn))
        images.append({"filename": fn, "idiom": "tv", "scale": scale})
    write_json(os.path.join(imgset, "Contents.json"), {"images": images, "info": INFO})


write_stack("App Icon - App Store", [("1x", 1280, 768)])
write_stack("App Icon", [("1x", 400, 240), ("2x", 800, 480)])
write_shelf("Top Shelf Image", 1920, 720)
write_shelf("Top Shelf Image Wide", 2320, 720)
write_json(os.path.join(BRAND, "Contents.json"), {
    "assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
    ],
    "info": INFO,
})
print("done")
