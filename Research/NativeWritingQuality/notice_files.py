"""Select original legal/documentation candidates without treating code as notices."""
from pathlib import PurePosixPath
import re

NON_NOTICE_SUFFIXES = {
    ".class", ".java", ".scala", ".kt", ".kts", ".c", ".h", ".cc", ".cpp", ".js", ".py",
    ".sh", ".pl", ".pm", ".swift", ".go", ".rs", ".m", ".mm", ".bat", ".ps1",
    ".jar", ".zip", ".tar", ".gz", ".a", ".o", ".so", ".dylib", ".dll", ".exe",
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf", ".ico", ".icns", ".svg",
    ".hash", ".star", ".regex",
}


def is_notice(name, include_readmes=False):
    path = PurePosixPath(name)
    if name.endswith("/") or path.suffix.lower() in NON_NOTICE_SUFFIXES:
        return False
    tokens = [r"LICEN[CS]ES?", r"NOTICES?", "COPYING", r"COPYRIGHTS?"]
    if include_readmes:
        tokens.append("README")
    return re.search(r"(?:^|[^A-Z0-9])(?:" + "|".join(tokens) + r")(?:$|[^A-Z0-9])", path.name.upper()) is not None
