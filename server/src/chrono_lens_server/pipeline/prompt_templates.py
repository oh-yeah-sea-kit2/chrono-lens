"""Era ID → prompt / negative prompt mapping."""

from typing import Tuple

ERA_PROMPTS: dict[int, Tuple[str, str]] = {
    0x00: (
        "",
        "",
    ),
    0x01: (  # 大正 (1912-1926)
        "Taisho era Japan 1920s photograph, sepia tone, hand-colored photo, "
        "vintage film grain, people in kimono and western dress, wooden buildings, "
        "rickshaw, gas lamp, cobblestone street, soft bokeh, analog photography",
        "modern cars, neon signs, plastic, digital artifacts, color photography, "
        "skyscrapers, smartphones, pavement, concrete",
    ),
    0x02: (  # 昭和初期 (1926-1945)
        "Showa period Japan 1930s, black and white photograph, film grain, "
        "bicycles, streetcar, prewar architecture, Japanese soldiers, "
        "traditional market, monochrome, high contrast",
        "color photography, modern buildings, smartphones, SUVs, "
        "digital noise, neon signs",
    ),
    0x03: (  # 昭和中期 (1945-1970)
        "Postwar Showa Japan 1960s photograph, slightly faded color film, "
        "Kodachrome, light poles, wood and tile buildings, "
        "retro cars, Japanese shop signs, cheerful crowds",
        "modern cars, skyscrapers, digital artifacts, smartphones, LED signs",
    ),
    0x04: (  # 明治 (1868-1912)
        "Meiji era Japan 1890s photograph, silver gelatin print, "
        "rickshaw, samurai architecture, early western suits mixed with kimono, "
        "dirt road, wooden telegraph poles, soft sepia, vignette",
        "modern buildings, cars, electricity pylons, concrete, digital artifacts",
    ),
}

DEFAULT_ERA = 0x01


def get_prompts(era_id: int) -> Tuple[str, str]:
    return ERA_PROMPTS.get(era_id, ERA_PROMPTS[DEFAULT_ERA])
