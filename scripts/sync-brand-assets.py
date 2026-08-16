#!/usr/bin/env python3
"""Resize the images/ logos into the app asset catalog."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "images"
ASSETS = ROOT / "CursorStack" / "Resources" / "Assets.xcassets"
APP_ICON = ASSETS / "AppIcon.appiconset"

CHARCOAL = (24, 24, 27, 255)

APP_ICON_SIZES = [
    ("icon_16.png", 16),
    ("icon_32.png", 32),
    ("icon_64.png", 64),
    ("icon_128.png", 128),
    ("icon_256.png", 256),
    ("icon_512.png", 512),
    ("icon_1024.png", 1024),
]


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n")


def resize(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def app_icon_source() -> Image.Image:
    mark = Image.open(SOURCE / "cursorstack-logo-square-mono.png").convert("RGBA")
    canvas = Image.new("RGBA", mark.size, CHARCOAL)
    canvas.alpha_composite(mark)
    return canvas


def imageset(name: str, filename: str, *, template: bool = False, scale: str = "2x") -> Path:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    properties = {"template-rendering-intent": "template" if template else "original"}
    write_json(
        folder / "Contents.json",
        {
            "images": [{"filename": filename, "idiom": "universal", "scale": scale}],
            "info": {"author": "xcode", "version": 1},
            "properties": properties,
        },
    )
    return folder / filename


def crop_to_opaque(path: Path, padding_ratio: float = 0.04) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    box = image.split()[-1].getbbox()
    if box is None:
        return image
    left, top, right, bottom = box
    pad_x = int((right - left) * padding_ratio)
    pad_y = int((bottom - top) * padding_ratio)
    left = max(0, left - pad_x)
    top = max(0, top - pad_y)
    right = min(image.width, right + pad_x)
    bottom = min(image.height, bottom + pad_y)
    return image.crop((left, top, right, bottom))


def fit_square(image: Image.Image) -> Image.Image:
    side = max(image.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
    return square


def main() -> None:
    APP_ICON.mkdir(parents=True, exist_ok=True)
    icon = app_icon_source()
    for filename, size in APP_ICON_SIZES:
        resize(icon, size).save(APP_ICON / filename, "PNG")

    write_json(
        APP_ICON / "Contents.json",
        {
            "images": [
                {"filename": "icon_16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
                {"filename": "icon_32.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
                {"filename": "icon_32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
                {"filename": "icon_64.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
                {"filename": "icon_128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
                {"filename": "icon_256.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
                {"filename": "icon_256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
                {"filename": "icon_512.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
                {"filename": "icon_512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
                {"filename": "icon_1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"},
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )

    Image.open(SOURCE / "cursorstack-logo-square-color.png").convert("RGBA").resize(
        (512, 512), Image.Resampling.LANCZOS
    ).save(imageset("LogoSquareColor", "LogoSquareColor.png"), "PNG")

    Image.open(SOURCE / "cursorstack-logo-square-mono.png").convert("RGBA").resize(
        (512, 512), Image.Resampling.LANCZOS
    ).save(imageset("LogoSquareMono", "LogoSquareMono.png"), "PNG")

    for asset, source_name in [
        ("LogoFullColor", "cursorstack-logo-full-color.png"),
        ("LogoFullWhite", "cursorstack-logo-full-white.png"),
        ("LogoFullBlack", "cursorstack-logo-full-black.png"),
    ]:
        wordmark = crop_to_opaque(SOURCE / source_name)
        width = 900
        height = max(1, round(wordmark.height * (width / wordmark.width)))
        wordmark.resize((width, height), Image.Resampling.LANCZOS).save(
            imageset(asset, f"{asset}.png"), "PNG"
        )

    for asset, source_name in [
        ("LogoNameColor", "cursorstack-logo-name-color.png"),
        ("LogoNameMono", "cursorstack-logo-name-mono.png"),
        ("LogoNameWhite", "cursorstack-logo-name-white.png"),
        ("LogoNameBlack", "cursorstack-logo-name-black.png"),
    ]:
        name = crop_to_opaque(SOURCE / source_name, padding_ratio=0.02)
        width = 900
        height = max(1, round(name.height * (width / name.width)))
        name.resize((width, height), Image.Resampling.LANCZOS).save(
            imageset(asset, f"{asset}.png"), "PNG"
        )

    menu = fit_square(crop_to_opaque(SOURCE / "cursorstack-logo-square-mono.png", 0.08)).resize(
        (36, 36), Image.Resampling.LANCZOS
    )
    menu.save(imageset("MenuBarIcon", "MenuBarIcon.png", template=True), "PNG")

    print("Synced brand assets into CursorStack/Resources/Assets.xcassets")


if __name__ == "__main__":
    main()
