#!/usr/bin/env python3
"""Style gate: placement-map lint, token drift, no-purple palette, and worst-case contrast from Theme.swift tokens.
Usage: python3 scripts/style_check.py [file ...]   (default: every Swift file under Toodle/). Exit 1 on any failure."""
import itertools, math, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
THEME = ROOT / "Toodle/App/Theme.swift"

# Placement map: pattern -> files allowed to contain it.
PLACEMENT = [
    (r"ShaderLibrary\.(foil|dotGrid)\b", {"Theme.swift"}, "foil/dot grid: app-wide Backdrop only"),
    (r"ShaderLibrary\.metaballs", {"Theme.swift"}, "metaballs shader lives in Backdrop"),
    (r"metaballs:\s*true", {"HomeView.swift"}, "metaballs: landing (Home) only"),
    (r"ShaderLibrary\.caustics|Caustics\(\)", {"Theme.swift"}, "caustics: active/focused controls only (ToodleButtonStyle)"),
    (r"(?i)isoline", {"Theme.swift", "CommandCenterView.swift"}, "isolines: map preview only"),
    (r"(?i)reactionDiffusion", {"Theme.swift"}, "reaction-diffusion: loading/empty/success via Theme helper only"),
    (r"(?i)flowField", {"Theme.swift", "RootTabView.swift"}, "flow-field: screen changes only"),
]
TEAL = re.compile(r"\bteal\b|systemTeal|Color\(red:0\.08")
COLORS = r"(red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|black|white|gray|secondary)"
DRIFT = re.compile(r"Color\(red:|UIColor\(red:|#colorLiteral|backgroundColor = \.|(foregroundStyle|tint|background|fill|stroke|foregroundColor)\(\s*(Color)?\." + COLORS + r"\b|\bColor\." + COLORS + r"\b")
KINETIC = re.compile(r"symbolEffect|contentTransition|\.transition\(|KineticText\(")
ALERT = re.compile(r"\bband\b|RiskBadge|critical|\.fri\b")

def lint(files):
    errors = []
    for f in files:
        lines = f.read_text().splitlines()
        text = "\n".join(lines)
        for n, line in enumerate(lines, 1):
            where = f"{f.relative_to(ROOT)}:{n}"
            for pat, allowed, why in PLACEMENT:
                if re.search(pat, line) and f.name not in allowed:
                    errors.append(f"{where} placement: {why}")
            if TEAL.search(line.replace("toodle-logo-teal", "")):
                errors.append(f"{where} teal outside the logo")
            if f != THEME and DRIFT.search(line):
                errors.append(f"{where} token drift: hard-coded colour, use Tok.*")
            if ALERT.search(line) and KINETIC.search(line) and "kinetic:false" not in line:
                errors.append(f"{where} alert/risk indicator must be static")
        if "Backdrop(" in text and f != THEME:
            if not re.search(r"\.textZone\(|\.card\(\)", text):
                errors.append(f"{f.relative_to(ROOT)} foil behind text: screen has a Backdrop but no textZone/card panels")
            for n, line in enumerate(lines, 1):
                if "Backdrop(" in line and ".background" not in line:
                    errors.append(f"{f.relative_to(ROOT)}:{n} Backdrop must sit in .background (under content)")
    return errors

# ---- colour maths -------------------------------------------------------------------------------
def oklch_to_srgb(l, c, h):
    a, b = c * math.cos(math.radians(h)), c * math.sin(math.radians(h))
    L, M, S = ((l + 0.3963377774 * a + 0.2158037573 * b) ** 3, (l - 0.1055613458 * a - 0.0638541728 * b) ** 3, (l - 0.0894841775 * a - 1.2914855480 * b) ** 3)
    lin = (4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S, -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S, -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S)
    return tuple(min(1, max(0, 12.92 * v if v <= 0.0031308 else 1.055 * max(v, 0) ** (1 / 2.4) - 0.055)) for v in lin)

def luminance(rgb):
    lin = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]

def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

mix = lambda a, b, t: tuple(x + (y - x) * t for x, y in zip(a, b))

def tokens():
    src = THEME.read_text()
    toks = {m[0]: [tuple(map(float, m[1].split(","))), tuple(map(float, m[2].split(",")))]
            for m in re.findall(r"static let (\w+) = Color\.token\(\.oklch\(([^)]*)\), \.oklch\(([^)]*)\)\)", src)}
    num = lambda name: float(re.search(rf"static let {name} = ([\d.]+)", src).group(1))
    return toks, num("panelOpacity"), num("foilStrength")

def foil_samples(t, mode, strength):
    """Every colour the foil shader can output (Effects.metal `foil`): ramp x band x shade x specular, plus metaball chrome."""
    rgb = {k: oklch_to_srgb(*v[mode]) for k, v in t.items()}
    ramp = [rgb["foil1"], rgb["foil2"], rgb["foil3"], rgb["foil4"]]
    out = [rgb["ink"], rgb["glint"]]  # metaball chrome env colours can scroll under panels
    for i, x in itertools.product(range(3), [k / 8 for k in range(9)]):
        spectral = mix(ramp[i], ramp[i + 1], x)
        for band, shade, spec in itertools.product([0, 0.5, 1], [0.88, 1.03], [0, 0.3 * strength]):
            out.append(tuple(min(1, v * shade + spec) for v in mix(rgb["paper"], spectral, band * strength)))
    return rgb, out

def contrast_report():
    t, opacity, strength = tokens()
    rows, failures = [], []
    for mode, name in ((0, "light"), (1, "dark")):
        rgb, under = foil_samples(t, mode, strength)
        zones = [mix(u, rgb["panel"], opacity) for u in under]  # panel composited over every foil output
        checks = [("body text (ink) on text zone", rgb["ink"], zones, 4.5),
                  ("secondary text (inkMuted) on text zone", rgb["inkMuted"], zones, 4.5),
                  ("button label (panel) on ink", rgb["panel"], [rgb["ink"]], 4.5),
                  ("focus ring outer (accent) vs inner ring (panel)", rgb["accent"], [rgb["panel"]], 3.0),
                  ("focus ring outer (accent) vs text zone", rgb["accent"], zones, 3.0)]
        for label, fg, bgs, need in checks:
            worst = min(contrast(fg, b) for b in bgs)
            rows.append(f"{name:5}  {worst:5.2f}:1  (need {need}:1)  {label}")
            if worst < need:
                failures.append(f"contrast {name}: {label} {worst:.2f}:1 < {need}:1")
    for k, (light, dark) in t.items():  # no purple, and spectral hues stay clear of logo teal (h=183)
        for l, c, h in (light, dark):
            if c >= 0.03 and not 225 <= h <= 262:
                failures.append(f"palette: {k} hue {h} outside blue range 225-262")
    return rows, failures

if __name__ == "__main__":
    files = [pathlib.Path(p).resolve() for p in sys.argv[1:]] or sorted((ROOT / "Toodle").rglob("*.swift"))
    errors = lint(files)
    rows, failures = contrast_report()
    print("Worst-case sampled contrast (every foil output under each text zone):")
    print("\n".join("  " + r for r in rows))
    for e in errors + failures:
        print("FAIL", e)
    print(f"{len(errors)} lint failures, {len(failures)} contrast/palette failures")
    sys.exit(1 if errors or failures else 0)
