from __future__ import annotations

import re


def normalize_whitespace(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def apply_prompt_term_replacements(text: str, prompt_terms: list[str]) -> str:
    normalized = normalize_whitespace(text)
    for term in prompt_terms:
        replacement = normalize_whitespace(term)
        if not replacement:
            continue
        pattern = re.compile(rf"(?<!\w){re.escape(replacement)}(?!\w)", re.IGNORECASE)
        normalized = pattern.sub(replacement, normalized)
    return normalize_whitespace(normalized)
