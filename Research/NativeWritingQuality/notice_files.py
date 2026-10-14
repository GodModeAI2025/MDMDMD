"""Select original legal/documentation candidates without treating code as notices."""
from pathlib import PurePosixPath

CODE_SUFFIXES = {".class", ".java", ".scala", ".kt", ".kts", ".c", ".h", ".cc", ".cpp", ".js", ".py"}


def is_notice(name, include_readmes=False):
    path = PurePosixPath(name)
    if name.endswith("/") or path.suffix.lower() in CODE_SUFFIXES:
        return False
    tokens = ["LICENSE", "NOTICE", "COPYING", "COPYRIGHT"]
    if include_readmes:
        tokens.append("README")
    return any(token in path.name.upper() for token in tokens)
